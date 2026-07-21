"""Async chat-mode handler: persistent Hermes conversations outside the todo lifecycle.

Unlike todos (one-shot tasks), a conversation maintains an ongoing Hermes
session. The runner polls for new user messages in each active conversation,
sends them to Hermes, streams the assistant reply back into the DB, and
repeats. There is no "requested → running → done" lifecycle — the session
stays open for continuous back-and-forth.
"""
from __future__ import annotations

import logging
import uuid

from .config import Config
from .db import DB
from .hermes import HermesClient, HermesEndpoint
from .events import extract_terminal_text

log = logging.getLogger(__name__)

_CHAT_SYSTEM_PROMPT = """You are in chat mode. The user is having a free-form
conversation with you. There is no task to complete — just converse helpfully.
You have access to your usual tools (web search, email, etc.) and should use
them when the user asks a question that benefits from them.

Keep responses conversational and concise. Do not produce structured task
output like artifacts or deliverables. If the user wants something saved,
ask them if they would like to create a task for it."""


async def poll_and_process_chat_conversations(db: DB, cfg: Config) -> None:
    """Check every active conversation for new user messages and process one turn per conversation.

    Called from the main runner loop alongside todo polling.
    Only processes conversations that are not already being handled.
    """
    try:
        resp = (
            db._client.table("conversations")
            .select("*")
            .eq("status", "active")
            .execute()
        )
        conversations = resp.data or []
    except Exception as e:
        log.error("poll_and_process_chat_conversations: failed to list: %s", e)
        return

    if not hasattr(poll_and_process_chat_conversations, "_in_progress"):
        poll_and_process_chat_conversations._in_progress = set()

    for conv in conversations:
        conv_id = conv["id"]
        user_id = conv["user_id"]
        hermes_session_id = conv.get("hermes_session_id")

        if conv_id in poll_and_process_chat_conversations._in_progress:
            log.debug("chat(%s): already processing, skipping", conv_id)
            continue

        try:
            msgs_resp = (
                db._client.table("conversation_messages")
                .select("*")
                .eq("conversation_id", conv_id)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
        except Exception as e:
            log.error("chat(%s): failed to fetch latest msg: %s", conv_id, e)
            continue

        latest_msgs = msgs_resp.data or []
        if not latest_msgs:
            continue
        latest = latest_msgs[0]
        if latest.get("role") != "user":
            continue

        profile = _hermes_profile_for_user(db, user_id)
        if not profile:
            log.warning("chat(%s): no Hermes profile for user=%s", conv_id, user_id)
            continue

        if not hermes_session_id:
            hermes_session_id = str(uuid.uuid4())
            db.upsert_conversation_session(conv_id, hermes_session_id)

        transcript = db.list_conversation_messages(conv_id, limit=50)

        endpoint = HermesEndpoint(
            profile_name=profile.get("profile_name", "chat"),
            host=profile["api_host"],
            port=int(profile["api_port"]),
            api_key=profile["api_key"],
        )
        hermes = HermesClient(endpoint)

        poll_and_process_chat_conversations._in_progress.add(conv_id)
        try:
            await _process_chat_turn(
                db=db,
                hermes=hermes,
                conv_id=conv_id,
                user_id=user_id,
                user_message=latest["body"],
                session_id=hermes_session_id,
                transcript=transcript,
            )
        except Exception as e:
            log.error("chat(%s): turn processing failed: %s", conv_id, e)
        finally:
            poll_and_process_chat_conversations._in_progress.discard(conv_id)
            await hermes.aclose()


async def _process_chat_turn(
    db: DB,
    hermes: HermesClient,
    conv_id: str,
    user_id: str,
    user_message: str,
    session_id: str,
    transcript: list[dict],
) -> None:
    """Send a user message through Hermes and persist the assistant reply."""
    transcript_text = _transcript_to_text(transcript)

    full_prompt = (
        f"{_CHAT_SYSTEM_PROMPT}\n\n"
        f"Conversation so far:\n{transcript_text}\n\n"
        f"User: {user_message}"
    )

    run_id = await hermes.start_run(
        full_prompt,
        session_id=session_id,
        instructions=_CHAT_SYSTEM_PROMPT,
    )
    db.upsert_conversation_run(conv_id, run_id)

    assistant_text = ""
    try:
        async for event in hermes.stream_events(run_id):
            if event.event in ("done", "run.completed", "response.completed"):
                terminal_text = extract_terminal_text(event.event, event.data)
                if terminal_text:
                    assistant_text = terminal_text
            elif event.event == "error":
                log.error("chat(%s): Hermes run error: %s", conv_id, event.data)
                assistant_text = assistant_text or f"I encountered an error: {event.data}"
    except Exception as e:
        log.error("chat(%s): SSE stream failed: %s", conv_id, e)
        assistant_text = assistant_text or f"Sorry, the stream was interrupted: {e}"

    if not assistant_text:
        run = await hermes.get_run(run_id)
        assistant_text = (
            run.get("output")
            or (run.get("choices") or [{}])[0].get("message", {}).get("content")
            or ""
        )

    if assistant_text:
        db.insert_conversation_message(
            conversation_id=conv_id,
            user_id=user_id,
            role="assistant",
            body=assistant_text.strip(),
        )


def _transcript_to_text(transcript: list[dict]) -> str:
    """Collapse a message list into a plain-text transcript."""
    lines: list[str] = []
    for msg in transcript:
        role = msg.get("role", "unknown")
        body = msg.get("body", "")
        lines.append(f"{role.capitalize()}: {body}")
    return "\n".join(lines)


def _hermes_profile_for_user(db: DB, user_id: str) -> dict | None:
    """Look up the user's Hermes profile."""
    try:
        resp = (
            db._client.table("user_hermes")
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        return resp.data
    except Exception as e:
        log.error("_hermes_profile_for_user(%s) failed: %s", user_id, e)
        return None
