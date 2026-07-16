"""BYO Hermes connector entrypoint.

Runs beside a user's existing Hermes gateway and processes only the Supabase
work paired to that connector token.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import os
import shlex
import subprocess
import time
from contextlib import suppress
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import httpx

from .connector_api import ConnectorAPI
from .events import translate
from .hermes import HermesClient, HermesEndpoint
from .model_settings import _replace_top_level_block, _atomic_write
from .prompt import build_prompt, session_id_for_todo, session_key_for_user
from .runner import setup_logging
from .scheduler import TaskPool, UserGates

log = logging.getLogger(__name__)

_HEARTBEAT_INTERVAL_SECS = 15.0
_STALE_SCAN_INTERVAL_SECS = 30.0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Doit BYO Hermes connector")
    parser.add_argument("--supabase-url", required=True)
    parser.add_argument("--supabase-anon-key", default=os.environ.get("SUPABASE_ANON_KEY", ""))
    parser.add_argument("--connector-token", required=True)
    parser.add_argument("--hermes-url", default="http://127.0.0.1:8643")
    parser.add_argument("--hermes-api-key", default=os.environ.get("HERMES_API_KEY", ""))
    parser.add_argument("--profile-name", default="byo-hermes")
    parser.add_argument("--poll-interval-secs", type=float, default=float(os.environ.get("POLL_INTERVAL_SECS", "2")))
    parser.add_argument("--max-concurrent-runs", type=int, default=int(os.environ.get("MAX_CONCURRENT_RUNS", "1")))
    return parser.parse_args()


def _endpoint_parts(url: str) -> tuple[str, int]:
    parsed = urlparse(url)
    if parsed.scheme != "http":
        raise RuntimeError("Hermes URL must start with http://")
    if not parsed.hostname:
        raise RuntimeError("Hermes URL is missing a host")
    default_port = 443 if parsed.scheme == "https" else 80
    return parsed.hostname, parsed.port or default_port


def _capabilities(*, hermes_status: str = "unchecked") -> dict[str, str]:
    return {
        "Hermes": hermes_status,
        "Models": "managed by your Hermes",
        "Memory": "local to your Hermes profile",
        "Integrations": "managed by your Hermes",
    }


def _friendly_hermes_error(endpoint: HermesEndpoint, exc: BaseException) -> str:
    base = endpoint.base_url
    if isinstance(exc, (httpx.ConnectError, httpx.ConnectTimeout)):
        return (
            f"The connector is online, but it cannot reach Hermes at {base}. "
            "Check that Hermes is running, the port is correct, and systemd is using the same URL."
        )
    if isinstance(exc, httpx.ReadTimeout):
        return f"The connector reached Hermes at {base}, but Hermes did not respond in time."
    if isinstance(exc, httpx.HTTPStatusError):
        status = exc.response.status_code
        if status in {401, 403}:
            return (
                f"Hermes at {base} rejected the connector credentials. "
                "Check whether --hermes-api-key is required and correct."
            )
        return f"Hermes at {base} rejected the task request with HTTP {status}."
    return str(exc) or f"Hermes at {base} could not start the task."


async def _check_hermes_health(endpoint: HermesEndpoint) -> tuple[bool, str]:
    headers = {"Authorization": f"Bearer {endpoint.api_key}"} if endpoint.api_key else {}
    try:
        async with httpx.AsyncClient(
            base_url=endpoint.base_url,
            headers=headers,
            timeout=httpx.Timeout(connect=5.0, read=5.0, write=5.0, pool=5.0),
        ) as client:
            resp = await client.get("/health")
        if resp.status_code < 400:
            return True, "reachable"
        if resp.status_code in {401, 403}:
            return False, "auth failed"
        return False, f"health HTTP {resp.status_code}"
    except Exception as exc:
        return False, _friendly_hermes_error(endpoint, exc)


def _profiles_dir() -> Path:
    """Return the Hermes profiles directory."""
    return Path(os.environ.get("HERMES_PROFILES_DIR", os.path.expanduser("~/.hermes/profiles")))


async def _apply_model_setting(
    api: ConnectorAPI,
    profile_name: str,
    setting: dict,
) -> None:
    """Apply a pending model setting and report back via the API.

    Edits the profile's config.yaml directly, then restarts the Hermes
    gateway service for that profile.
    """
    provider = str(setting["provider"])
    model = str(setting["model"])
    base_url = str(setting.get("base_url") or "").strip() or None

    # Build the model block for config.yaml
    lines = [
        "model:",
        f"  provider: {provider}",
        f"  default: {model}",
    ]
    if base_url:
        lines.append(f"  base_url: {base_url}")
    model_block = "\n".join(lines)

    try:
        profile_dir = _profiles_dir() / profile_name
        config_path = profile_dir / "config.yaml"

        if not config_path.exists():
            raise RuntimeError(f"Profile config not found: {config_path}")

        # Read, replace the model block, write atomically
        existing = config_path.read_text()
        updated = _replace_top_level_block(existing, "model", model_block)
        _atomic_write(config_path, updated)

        log.info(
            "applied model setting profile=%s provider=%s model=%s%s",
            profile_name, provider, model,
            f" base_url={base_url}" if base_url else "",
        )

        # Report applied status
        await api.report_model_apply(
            apply_status="applied",
            provider=provider,
            model=model,
        )

        # Restart Hermes
        _restart_hermes(profile_name)

    except Exception as exc:
        log.error("failed to apply model setting: %s", exc)
        try:
            await api.report_model_apply(
                apply_status="failed",
                provider=provider,
                model=model,
                apply_error=str(exc),
            )
        except Exception as report_exc:
            log.error("failed to report model apply failure: %s", report_exc)


def _restart_hermes(profile_name: str) -> None:
    """Restart the Hermes gateway for the given profile."""
    # Try profile-specific gateway first, then the default gateway
    services = [
        f"hermes-gateway-{profile_name}.service",
        "hermes-gateway.service",
    ]
    for svc in services:
        try:
            subprocess.run(
                ["sudo", "systemctl", "restart", svc],
                check=True, timeout=30, capture_output=True, text=True,
            )
            log.info("restarted %s", svc)
            return
        except subprocess.CalledProcessError as exc:
            log.debug("could not restart %s: %s", svc, exc.stderr.strip())
        except FileNotFoundError:
            log.debug("sudo/systemctl not available")
    log.warning("could not restart Hermes for profile %s", profile_name)


async def _heartbeat_loop(
    api: ConnectorAPI,
    *,
    profile_name: str,
    endpoint: HermesEndpoint,
    endpoint_url: str,
) -> None:
    while True:
        _, hermes_status = await _check_hermes_health(endpoint)
        resp = await api.heartbeat(
            profile_name=profile_name,
            endpoint_url=endpoint_url,
            capabilities=_capabilities(hermes_status=hermes_status),
        )
        # Apply any pending model setting (at most one per heartbeat tick)
        pending = resp.get("pending_model_setting")
        if pending and isinstance(pending, dict) and pending.get("provider") and pending.get("model"):
            log.info(
                "pending model setting detected provider=%s model=%s",
                pending["provider"], pending["model"],
            )
            await _apply_model_setting(api, profile_name, pending)
        await asyncio.sleep(_HEARTBEAT_INTERVAL_SECS)


async def _lease_loop(api: ConnectorAPI, todo_id: str) -> None:
    while True:
        await asyncio.sleep(60)
        await api.touch_lease(todo_id)


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


async def _run_todo(
    api: ConnectorAPI,
    *,
    endpoint: HermesEndpoint,
    todo: dict,
) -> None:
    todo_id = str(todo["id"])
    user_id = str(todo["user_id"])
    title = str(todo.get("title") or "")
    detail = str(todo.get("detail") or "")
    original_title = str(todo.get("original_title") or "")
    prompt = build_prompt(
        title,
        detail,
        original_title=original_title,
        preparation_summary=todo.get("preparation_summary"),
        connection_slug=todo.get("connection_slug"),
        topic=todo.get("topic"),
    )
    session_id = session_id_for_todo(user_id, todo_id)
    session_key = session_key_for_user(user_id)
    hermes = HermesClient(endpoint)
    lease = asyncio.create_task(_lease_loop(api, todo_id))
    terminal_status: str | None = None
    try:
        await api.insert_step(
            todo_id=todo_id,
            kind="thought",
            text="Starting task with your Hermes connector.",
        )
        run_id = await hermes.start_run(prompt, session_id=session_id, session_key=session_key)
        await api.update_todo(
            todo_id,
            {"hermes_run_id": run_id, "hermes_session_id": session_id},
        )
        async for event in hermes.stream_events(run_id):
            effect = translate(event.event, event.data)
            if effect is None:
                continue
            if effect.step_kind:
                await api.insert_step(
                    todo_id=todo_id,
                    kind=effect.step_kind,
                    text=effect.text,
                    url=effect.url,
                    tool_name=effect.tool_name,
                )
            if effect.new_status:
                terminal_status = effect.new_status
                fields: dict[str, object] = {"status": effect.new_status}
                if effect.new_status == "failed":
                    fields["error_message"] = effect.text or "Hermes run failed."
                if effect.new_status == "done":
                    fields["completed_at"] = _iso_now()
                await api.update_todo(todo_id, fields)
                if effect.new_status in {"done", "failed", "needs_auth", "needs_input"}:
                    break
        if terminal_status is None:
            await api.insert_step(todo_id=todo_id, kind="final", text="Done.")
            await api.update_todo(todo_id, {"status": "done", "completed_at": _iso_now()})
    except Exception as exc:
        message = _friendly_hermes_error(endpoint, exc)
        log.exception("BYO connector task failed todo=%s", todo_id)
        with suppress(Exception):
            await api.insert_step(todo_id=todo_id, kind="error", text=message)
            await api.update_todo(todo_id, {"status": "failed", "error_message": message})
    finally:
        lease.cancel()
        with suppress(asyncio.CancelledError, Exception):
            await lease
        await hermes.aclose()


async def connector_loop() -> None:
    setup_logging()
    args = _parse_args()
    if not args.supabase_anon_key:
        raise RuntimeError("missing --supabase-anon-key")

    api = ConnectorAPI(
        supabase_url=args.supabase_url,
        supabase_anon_key=args.supabase_anon_key,
        connector_token=args.connector_token,
    )
    host, port = _endpoint_parts(args.hermes_url)
    endpoint = HermesEndpoint(
        profile_name=args.profile_name,
        host=host,
        port=port,
        api_key=args.hermes_api_key,
    )
    _, initial_hermes_status = await _check_hermes_health(endpoint)
    await api.register(
        profile_name=args.profile_name,
        endpoint_url=args.hermes_url,
        capabilities=_capabilities(hermes_status=initial_hermes_status),
    )

    gates = UserGates()
    pool = TaskPool(max(1, args.max_concurrent_runs))
    heartbeat = asyncio.create_task(
        _heartbeat_loop(
            api,
            profile_name=args.profile_name,
            endpoint=endpoint,
            endpoint_url=args.hermes_url,
        )
    )
    last_stale_scan = 0.0

    log.info("BYO connector online endpoint=%s", args.hermes_url)
    try:
        while True:
            if not pool.has_capacity:
                await pool.wait_for_capacity(args.poll_interval_secs)
                continue

            now = time.time()
            todo = None
            if now - last_stale_scan >= _STALE_SCAN_INTERVAL_SECS:
                last_stale_scan = now
                todo = await api.recover_stale()
            if todo is None:
                todo = await api.claim_next()
            if todo is not None:
                pool.spawn(
                    _run_todo(api, endpoint=endpoint, todo=todo),
                    name=f"byo-todo:{todo['id']}",
                )
                continue

            await asyncio.sleep(args.poll_interval_secs)
    finally:
        heartbeat.cancel()
        with suppress(asyncio.CancelledError, Exception):
            await heartbeat


def main() -> None:
    asyncio.run(connector_loop())


if __name__ == "__main__":
    main()
