"""Supabase REST client wrapper for the runner (uses service_role)."""
from __future__ import annotations

import logging
from typing import Any

from supabase import Client, create_client

from .config import Config
from .hermes import HermesEndpoint

log = logging.getLogger(__name__)


class DB:
    def __init__(self, cfg: Config) -> None:
        self._client: Client = create_client(
            cfg.supabase_url,
            cfg.supabase_service_role_key,
        )

    # ------------------------------------------------------------------
    # Claiming work
    # ------------------------------------------------------------------

    def claim_next_requested_todo(self) -> dict | None:
        """Atomically transition one 'requested' todo to 'running' and return it.

        We do this in two phases: select one row id, then update WHERE id=?
        AND status='requested'. PostgREST returns the updated row, which is
        empty if someone else won the race — in which case we retry.
        """
        # Find one candidate.
        resp = (
            self._client.table("todos")
            .select("*")
            .eq("status", "requested")
            .order("created_at")
            .limit(1)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            return None
        candidate = rows[0]

        # Try to claim it.
        upd = (
            self._client.table("todos")
            .update({"status": "running"})
            .eq("id", candidate["id"])
            .eq("status", "requested")
            .execute()
        )
        claimed = upd.data or []
        if not claimed:
            # Lost the race; caller can retry.
            return None
        return claimed[0]

    # ------------------------------------------------------------------
    # Lookups
    # ------------------------------------------------------------------

    def get_user_hermes(self, user_id: str) -> HermesEndpoint | None:
        resp = (
            self._client.table("user_hermes")
            .select("api_host, api_port, api_key")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            return None
        r = rows[0]
        return HermesEndpoint(
            host=r.get("api_host") or "127.0.0.1",
            port=int(r["api_port"]),
            api_key=r["api_key"],
        )

    def get_todo(self, todo_id: str) -> dict | None:
        resp = (
            self._client.table("todos")
            .select("*")
            .eq("id", todo_id)
            .limit(1)
            .execute()
        )
        rows = resp.data or []
        return rows[0] if rows else None

    def list_apns_tokens(self, user_id: str) -> list[str]:
        resp = (
            self._client.table("devices")
            .select("apns_token")
            .eq("user_id", user_id)
            .execute()
        )
        return [r["apns_token"] for r in (resp.data or [])]

    def list_memories(self, user_id: str, limit: int = 20) -> list[dict]:
        try:
            resp = (
                self._client.table("memories")
                .select("title, body, category")
                .eq("user_id", user_id)
                .order("updated_at", desc=True)
                .limit(limit)
                .execute()
            )
            return resp.data or []
        except Exception as e:
            log.error("list_memories(%s) failed: %s", user_id, e)
            return []

    # ------------------------------------------------------------------
    # Writes
    # ------------------------------------------------------------------

    def update_todo(self, todo_id: str, fields: dict[str, Any]) -> None:
        try:
            self._client.table("todos").update(fields).eq("id", todo_id).execute()
        except Exception as e:
            log.error("update_todo(%s) failed: %s", todo_id, e)

    def insert_step(
        self,
        *,
        todo_id: str,
        user_id: str,
        kind: str,
        text: str | None = None,
        url: str | None = None,
        tool_name: str | None = None,
    ) -> None:
        try:
            self._client.table("todo_steps").insert(
                {
                    "todo_id": todo_id,
                    "user_id": user_id,
                    "kind": kind,
                    "text": text,
                    "url": url,
                    "tool_name": tool_name,
                }
            ).execute()
        except Exception as e:
            log.error("insert_step(%s, %s) failed: %s", todo_id, kind, e)
