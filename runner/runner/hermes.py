"""Thin Hermes API client: create runs and consume their SSE event stream."""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import AsyncIterator

import httpx

log = logging.getLogger(__name__)


@dataclass
class HermesEndpoint:
    host: str
    port: int
    api_key: str

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"


@dataclass
class HermesEvent:
    """One Server-Sent Event from /v1/runs/{id}/events."""
    event: str
    data: dict


SYSTEM_INSTRUCTIONS = (
    "You are a personal assistant completing a single todo for the user. "
    "Work end-to-end and finish the task. "
    "Use Composio tools for any real-world action (email, calendar, etc.). "
    "If a required app is not connected, call the Composio connection meta-tool "
    "to obtain an OAuth URL and clearly surface that URL in your reply so the "
    "user can approve it. After approval, continue and complete the task. "
    "When you are done, end your final reply with a one-line summary of what "
    "you did."
)


class HermesClient:
    """Per-user Hermes client."""

    def __init__(self, endpoint: HermesEndpoint) -> None:
        self._endpoint = endpoint
        self._client = httpx.AsyncClient(
            base_url=endpoint.base_url,
            headers={"Authorization": f"Bearer {endpoint.api_key}"},
            timeout=httpx.Timeout(connect=10.0, read=None, write=30.0, pool=30.0),
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def start_run(self, todo_text: str, session_id: str | None = None) -> str:
        """POST /v1/runs. Returns the new run_id."""
        body: dict = {
            "input": todo_text,
            "instructions": SYSTEM_INSTRUCTIONS,
        }
        if session_id:
            body["session_id"] = session_id
        resp = await self._client.post("/v1/runs", json=body)
        resp.raise_for_status()
        data = resp.json()
        run_id = data.get("run_id") or data.get("id")
        if not run_id:
            raise RuntimeError(f"hermes /v1/runs missing run_id: {data}")
        return str(run_id)

    async def stop_run(self, run_id: str) -> None:
        try:
            await self._client.post(f"/v1/runs/{run_id}/stop")
        except httpx.HTTPError as e:
            log.warning("stop_run %s failed: %s", run_id, e)

    async def stream_events(self, run_id: str) -> AsyncIterator[HermesEvent]:
        """Consume /v1/runs/{id}/events. Yields HermesEvent until terminal."""
        url = f"/v1/runs/{run_id}/events"
        async with self._client.stream("GET", url) as resp:
            resp.raise_for_status()
            async for ev in _parse_sse(resp):
                yield ev


async def _parse_sse(resp: httpx.Response) -> AsyncIterator[HermesEvent]:
    """Minimal SSE parser (event: + data: lines, blank line terminates)."""
    current_event = "message"
    data_lines: list[str] = []
    async for raw in resp.aiter_lines():
        line = raw.rstrip("\r")
        if line == "":
            if not data_lines:
                current_event = "message"
                continue
            payload = "\n".join(data_lines)
            data_lines = []
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                data = {"raw": payload}
            yield HermesEvent(event=current_event, data=data)
            current_event = "message"
            continue
        if line.startswith(":"):
            # comment / keep-alive
            continue
        if line.startswith("event:"):
            current_event = line[len("event:"):].strip()
        elif line.startswith("data:"):
            data_lines.append(line[len("data:"):].lstrip())
        # ignore id:/retry: for now
