"""Translate Hermes SSE events into doit todo_steps + status transitions."""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

# Anything that smells like a Composio OAuth redirect URL the user must visit.
# Composio surfaces these via its connection meta-tools; the exact host varies
# by upstream provider, so we accept any HTTPS URL emitted by a connection tool.
_OAUTH_URL_RE = re.compile(r"https://[^\s'\"<>]+")


@dataclass
class Translated:
    """Effect of one Hermes event on our DB."""
    step_kind: Literal[
        "thought", "tool_started", "tool_result", "oauth_needed", "final", "error"
    ] | None = None
    text: str | None = None
    url: str | None = None
    tool_name: str | None = None
    new_status: Literal["running", "needs_auth", "done", "failed"] | None = None
    final_text: str | None = None  # accumulated assistant final text


_CONNECTION_TOOL_HINTS = ("connect", "composio_manage_connections", "composio_wait")


def _looks_like_oauth_url(text: str, tool_name: str | None) -> str | None:
    """If this tool output contains an OAuth URL the user should open, return it."""
    if not text:
        return None
    tn = (tool_name or "").lower()
    is_connection_tool = any(h in tn for h in _CONNECTION_TOOL_HINTS)
    # Be conservative: only treat as OAuth if it came from a connection-y tool,
    # OR the text explicitly says "authorize" / "connect".
    lower = text.lower()
    signals = (
        "authorize",
        "authorization url",
        "connect your",
        "please visit",
        "click the following link",
    )
    if not (is_connection_tool or any(s in lower for s in signals)):
        return None
    m = _OAUTH_URL_RE.search(text)
    return m.group(0) if m else None


def translate(event_name: str, data: dict) -> Translated | None:
    """Map one Hermes SSE event to a Translated effect, or None to skip."""
    actual_event = str(data.get("event") or event_name or "")

    # ----- Hermes run API lifecycle/tool events -----
    if actual_event == "tool.started":
        tool_name = data.get("tool") or data.get("name")
        preview = data.get("preview")
        text = f"Using {tool_name}."
        if preview:
            text = f"{text} {preview}"
        return Translated(
            step_kind="tool_started",
            text=text,
            tool_name=str(tool_name) if tool_name else None,
        )

    if actual_event == "tool.completed":
        tool_name = data.get("tool") or data.get("name")
        is_error = bool(data.get("error"))
        duration = data.get("duration")
        text = "Tool failed." if is_error else "Tool completed."
        if isinstance(duration, (int, float)):
            text = f"{text} ({duration:.1f}s)"
        return Translated(
            step_kind="error" if is_error else "tool_result",
            text=text,
            tool_name=str(tool_name) if tool_name else None,
        )

    if actual_event == "reasoning.available":
        text = str(data.get("text") or "").strip()
        if text:
            return Translated(step_kind="thought", text=_truncate(text, 1000))

    if actual_event == "run.completed":
        text = str(data.get("output") or "").strip()
        return Translated(
            step_kind="final",
            text=_truncate(text, 2000) if text else "Done.",
            new_status="done",
            final_text=text,
        )

    # ----- tool start (Hermes-custom event on Chat Completions stream) -----
    if actual_event == "hermes.tool.progress":
        tool_name = data.get("tool") or data.get("name")
        message = data.get("message") or data.get("title") or "Working..."
        return Translated(
            step_kind="tool_started",
            text=str(message),
            tool_name=str(tool_name) if tool_name else None,
        )

    # ----- Responses-API style output items -----
    if actual_event in ("response.output_item.added", "response.output_item.done"):
        item = data.get("item") or {}
        itype = item.get("type")
        if itype == "function_call" and actual_event == "response.output_item.added":
            return Translated(
                step_kind="tool_started",
                text=_summarize_tool_call(item),
                tool_name=str(item.get("name") or ""),
            )
        if itype == "function_call_output" and actual_event == "response.output_item.done":
            output = item.get("output")
            text = _stringify_output(output)
            tool_name = str(item.get("name") or item.get("call_id") or "")
            oauth_url = _looks_like_oauth_url(text, tool_name)
            if oauth_url:
                return Translated(
                    step_kind="oauth_needed",
                    text="Connect an account to continue.",
                    url=oauth_url,
                    tool_name=tool_name,
                    new_status="needs_auth",
                )
            return Translated(
                step_kind="tool_result",
                text=_truncate(text, 600),
                tool_name=tool_name,
            )

    # ----- final assistant text (Responses style) -----
    if actual_event == "response.completed":
        resp = data.get("response") or {}
        text = _extract_final_text(resp)
        return Translated(
            step_kind="final",
            text=_truncate(text, 2000) if text else "Done.",
            new_status="done",
            final_text=text,
        )

    # ----- chat.completions style final -----
    if actual_event in ("done", "message", "") and data.get("choices"):
        choice = (data.get("choices") or [{}])[0]
        finish = choice.get("finish_reason")
        if finish in ("stop", "length"):
            msg = (choice.get("message") or {}).get("content") or ""
            return Translated(
                step_kind="final",
                text=_truncate(msg, 2000) if msg else "Done.",
                new_status="done",
                final_text=msg,
            )

    # ----- explicit run lifecycle -----
    if actual_event in ("run.completed", "response.completed"):
        return Translated(step_kind="final", text="Done.", new_status="done")
    if actual_event in ("run.failed", "response.failed", "error"):
        msg = data.get("error") or data.get("message") or "The run failed."
        return Translated(step_kind="error", text=str(msg), new_status="failed")

    return None


def _summarize_tool_call(item: dict) -> str:
    name = item.get("name") or "tool"
    args = item.get("arguments")
    if isinstance(args, str) and args:
        return f"{name}({_truncate(args, 200)})"
    return f"{name}(...)"


def _stringify_output(output) -> str:
    if output is None:
        return ""
    if isinstance(output, str):
        return output
    if isinstance(output, dict):
        return str(output.get("text") or output.get("content") or output)
    return str(output)


def _extract_final_text(resp: dict) -> str:
    out = resp.get("output") or []
    parts: list[str] = []
    for item in out:
        if item.get("type") != "message":
            continue
        for c in item.get("content") or []:
            if c.get("type") == "output_text":
                parts.append(c.get("text") or "")
    return "\n".join(p for p in parts if p)


def _truncate(text: str, limit: int) -> str:
    text = text or ""
    return text if len(text) <= limit else text[: limit - 1] + "\u2026"
