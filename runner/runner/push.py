"""APNs push via token-based auth (.p8)."""
from __future__ import annotations

import time
import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Any

import httpx
import jwt

from .config import Config

log = logging.getLogger(__name__)


@dataclass
class PushPayload:
    title: str
    body: str
    todo_id: str
    kind: str  # "oauth_needed" | "done" | "failed" | "activity_sync"


class Pusher:
    def __init__(self, cfg: Config) -> None:
        self._enabled = bool(
            cfg.apns_key_path
            and cfg.apns_key_id
            and cfg.apns_team_id
            and cfg.apns_topic
        )
        self._cfg = cfg
        self._clients: dict[str, httpx.AsyncClient] = {}
        self._jwt: str | None = None
        self._jwt_iat = 0
        if not self._enabled:
            log.warning("APNs not configured; pushes will be no-ops.")

    @property
    def default_environment(self) -> str:
        return "sandbox" if self._cfg.apns_use_sandbox else "production"

    def _ensure(self, environment: str | None = None) -> httpx.AsyncClient:
        env = environment or self.default_environment
        if env not in {"sandbox", "production"}:
            env = self.default_environment
        if env not in self._clients:
            assert self._enabled
            self._clients[env] = httpx.AsyncClient(
                http2=True,
                base_url=(
                    "https://api.sandbox.push.apple.com"
                    if env == "sandbox"
                    else "https://api.push.apple.com"
                ),
                timeout=20.0,
            )
        return self._clients[env]

    def _bearer_token(self) -> str:
        # Apple recommends reusing APNs provider tokens for up to one hour.
        now = int(time.time())
        if self._jwt and now - self._jwt_iat < 50 * 60:
            return self._jwt
        with open(self._cfg.apns_key_path, "r", encoding="utf-8") as f:
            private_key = f.read()
        self._jwt_iat = now
        self._jwt = jwt.encode(
            {"iss": self._cfg.apns_team_id, "iat": now},
            private_key,
            algorithm="ES256",
            headers={"kid": self._cfg.apns_key_id},
        )
        return self._jwt

    def _token_entries(self, tokens: list[Any]) -> list[tuple[str, str]]:
        entries: list[tuple[str, str]] = []
        for item in tokens:
            if isinstance(item, str):
                entries.append((item, self.default_environment))
            elif isinstance(item, dict):
                token = str(item.get("token") or item.get("apns_token") or "")
                environment = str(item.get("environment") or item.get("apns_environment") or self.default_environment)
                if token:
                    entries.append((token, environment))
        return entries

    async def send(self, tokens: list[Any], payload: PushPayload) -> list[str]:
        if not self._enabled or not tokens:
            return []
        message = {
            "aps": {
                "alert": {"title": payload.title, "body": payload.body},
                "sound": "default",
            },
            "todo_id": payload.todo_id,
            "kind": payload.kind,
        }
        invalid: list[str] = []
        for token, environment in self._token_entries(tokens):
            client = self._ensure(environment)
            try:
                resp = await client.post(
                    f"/3/device/{token}",
                    json=message,
                    headers={
                        "authorization": f"bearer {self._bearer_token()}",
                        "apns-topic": self._cfg.apns_topic,
                        "apns-push-type": "alert",
                        "apns-priority": "10",
                    },
                )
                if resp.status_code == 200:
                    log.info("APNs send succeeded env=%s token=%s", environment, token[:8])
                else:
                    reason = _apns_reason(resp)
                    log.warning(
                        "APNs send failed env=%s token=%s: %s %s",
                        environment,
                        token[:8],
                        resp.status_code,
                        resp.text,
                    )
                    if reason == "BadDeviceToken":
                        invalid.append(token)
            except Exception as e:
                log.warning("APNs send failed env=%s token=%s: %s", environment, token[:8], e)
        return invalid

    async def send_activity_sync(self, tokens: list[Any], todo_id: str) -> list[str]:
        """Silent push so the app can refresh agent activity and update Live Activities."""
        if not self._enabled or not tokens:
            return []
        message = {
            "aps": {"content-available": 1},
            "todo_id": todo_id,
            "kind": "activity_sync",
        }
        invalid: list[str] = []
        for token, environment in self._token_entries(tokens):
            client = self._ensure(environment)
            try:
                resp = await client.post(
                    f"/3/device/{token}",
                    json=message,
                    headers={
                        "authorization": f"bearer {self._bearer_token()}",
                        "apns-topic": self._cfg.apns_topic,
                        "apns-push-type": "background",
                        "apns-priority": "5",
                    },
                )
                if resp.status_code == 200:
                    log.info("APNs activity_sync succeeded env=%s token=%s", environment, token[:8])
                else:
                    reason = _apns_reason(resp)
                    log.warning(
                        "APNs activity_sync failed env=%s token=%s: %s %s",
                        environment,
                        token[:8],
                        resp.status_code,
                        resp.text,
                    )
                    if reason == "BadDeviceToken":
                        invalid.append(token)
            except Exception as e:
                log.warning("APNs activity_sync failed env=%s token=%s: %s", environment, token[:8], e)
        return invalid

    async def send_live_activity(
        self,
        tokens: list[Any],
        *,
        event: str,
        content_state: dict[str, Any],
        dismissal_date: datetime | None = None,
    ) -> list[str]:
        """Push an ActivityKit Live Activity update directly to the system UI."""
        if not self._enabled or not tokens:
            return []
        aps: dict[str, Any] = {
            "timestamp": int(time.time()),
            "event": event,
            "content-state": content_state,
        }
        if dismissal_date is not None:
            aps["dismissal-date"] = int(dismissal_date.timestamp())
        message = {"aps": aps}
        invalid: list[str] = []
        topic = f"{self._cfg.apns_topic}.push-type.liveactivity"
        for token, environment in self._token_entries(tokens):
            client = self._ensure(environment)
            try:
                resp = await client.post(
                    f"/3/device/{token}",
                    json=message,
                    headers={
                        "authorization": f"bearer {self._bearer_token()}",
                        "apns-topic": topic,
                        "apns-push-type": "liveactivity",
                        "apns-priority": "10",
                    },
                )
                if resp.status_code == 200:
                    log.info("APNs liveactivity %s succeeded env=%s token=%s", event, environment, token[:8])
                else:
                    reason = _apns_reason(resp)
                    log.warning(
                        "APNs liveactivity %s failed env=%s token=%s: %s %s",
                        event,
                        environment,
                        token[:8],
                        resp.status_code,
                        resp.text,
                    )
                    if reason in {"BadDeviceToken", "Unregistered"}:
                        invalid.append(token)
            except Exception as e:
                log.warning(
                    "APNs liveactivity %s failed env=%s token=%s: %s",
                    event,
                    environment,
                    token[:8],
                    e,
                )
        return invalid


def _apns_reason(resp: httpx.Response) -> str | None:
    try:
        data = resp.json()
    except Exception:
        return None
    reason = data.get("reason")
    return str(reason) if reason else None
