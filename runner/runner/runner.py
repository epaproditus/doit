"""Main poll loop: claim requested todos, drive Hermes, stream steps + push."""
from __future__ import annotations

import asyncio
import logging
from contextlib import suppress

import httpx

from .config import Config, load
from .db import DB
from .events import translate
from .hermes import HermesClient
from .push import Pusher, PushPayload

log = logging.getLogger(__name__)


def setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


async def run_one_todo(
    cfg: Config,
    db: DB,
    pusher: Pusher,
    todo: dict,
) -> None:
    todo_id = todo["id"]
    user_id = todo["user_id"]
    title = todo["title"]
    detail = todo.get("detail") or ""
    prompt = _build_prompt(title, detail, db.list_memories(user_id))

    log.info("processing todo %s user=%s title=%r", todo_id, user_id, title)

    endpoint = db.get_user_hermes(user_id)
    if endpoint is None:
        db.update_todo(
            todo_id,
            {
                "status": "failed",
                "error_message": "No Hermes profile is provisioned for this user.",
            },
        )
        db.insert_step(
            todo_id=todo_id,
            user_id=user_id,
            kind="error",
            text="No Hermes profile provisioned. Ask the admin to add you.",
        )
        await pusher.send(
            db.list_apns_tokens(user_id),
            PushPayload(
                title="Couldn't start your task",
                body="Your account isn't set up yet.",
                todo_id=todo_id,
                kind="failed",
            ),
        )
        return

    hermes = HermesClient(endpoint)
    cancel_watcher: asyncio.Task | None = None
    run_id: str | None = None
    terminal_status: str | None = None

    try:
        run_id = await hermes.start_run(prompt, session_id=f"todo-{todo_id}")
        db.update_todo(todo_id, {"hermes_run_id": run_id})
        log.info("todo %s started run %s", todo_id, run_id)

        cancel_event = asyncio.Event()
        cancel_watcher = asyncio.create_task(
            _watch_for_cancel(cfg, db, todo_id, cancel_event)
        )

        consume_task = asyncio.create_task(
            _consume_run(cfg, db, pusher, hermes, todo, run_id)
        )

        done, pending = await asyncio.wait(
            {consume_task, asyncio.create_task(cancel_event.wait())},
            timeout=cfg.run_timeout_secs,
            return_when=asyncio.FIRST_COMPLETED,
        )
        for t in pending:
            t.cancel()

        if cancel_event.is_set():
            log.info("todo %s cancelled by user", todo_id)
            with suppress(Exception):
                await hermes.stop_run(run_id)
            terminal_status = "cancelled"
            db.update_todo(todo_id, {"status": "cancelled"})
            db.insert_step(
                todo_id=todo_id,
                user_id=user_id,
                kind="error",
                text="Cancelled by user.",
            )
        elif consume_task in done:
            terminal_status = consume_task.result()
        else:
            log.warning("todo %s timed out after %ss", todo_id, cfg.run_timeout_secs)
            with suppress(Exception):
                await hermes.stop_run(run_id)
            terminal_status = "failed"
            db.update_todo(
                todo_id,
                {"status": "failed", "error_message": "Timed out."},
            )
            db.insert_step(
                todo_id=todo_id,
                user_id=user_id,
                kind="error",
                text="The agent took too long and was stopped.",
            )

    except httpx.HTTPError as e:
        log.exception("hermes call failed for todo %s", todo_id)
        terminal_status = "failed"
        db.update_todo(
            todo_id,
            {"status": "failed", "error_message": f"Hermes error: {e}"},
        )
        db.insert_step(
            todo_id=todo_id,
            user_id=user_id,
            kind="error",
            text=f"Couldn't reach the agent: {e}",
        )
    except Exception as e:
        log.exception("unexpected failure processing todo %s", todo_id)
        terminal_status = "failed"
        db.update_todo(
            todo_id,
            {"status": "failed", "error_message": str(e)},
        )
    finally:
        if cancel_watcher:
            cancel_watcher.cancel()
            with suppress(asyncio.CancelledError, Exception):
                await cancel_watcher
        await hermes.aclose()

    # Terminal push.
    if terminal_status == "done":
        await pusher.send(
            db.list_apns_tokens(user_id),
            PushPayload(
                title="Done",
                body=_short(title),
                todo_id=todo_id,
                kind="done",
            ),
        )
    elif terminal_status == "failed":
        await pusher.send(
            db.list_apns_tokens(user_id),
            PushPayload(
                title="Task failed",
                body=_short(title),
                todo_id=todo_id,
                kind="failed",
            ),
        )
    # needs_auth pushes are sent inline by _consume_run when the URL appears.
    # cancelled produces no push (the user did it themselves).


async def _consume_run(
    cfg: Config,
    db: DB,
    pusher: Pusher,
    hermes: HermesClient,
    todo: dict,
    run_id: str,
) -> str:
    """Consume the SSE stream and return the terminal status."""
    todo_id = todo["id"]
    user_id = todo["user_id"]
    terminal: str | None = None

    async for ev in hermes.stream_events(run_id):
        effect = translate(ev.event, ev.data)
        if effect is None:
            continue
        if effect.step_kind:
            db.insert_step(
                todo_id=todo_id,
                user_id=user_id,
                kind=effect.step_kind,
                text=effect.text,
                url=effect.url,
                tool_name=effect.tool_name,
            )
        if effect.new_status:
            fields: dict = {"status": effect.new_status}
            if effect.new_status == "done":
                fields["completed_at"] = "now()"
            elif effect.new_status == "failed":
                fields["error_message"] = effect.text or "Agent reported a failure."
            # Supabase REST can't take SQL like "now()" — drop it and let the
            # trigger keep updated_at fresh; we don't strictly need completed_at
            # to be wall-clock-accurate for the prototype.
            fields.pop("completed_at", None)
            db.update_todo(todo_id, fields)

            if effect.new_status == "needs_auth" and effect.url:
                await pusher.send(
                    db.list_apns_tokens(user_id),
                    PushPayload(
                        title="Connect an account",
                        body="Tap to authorize so the agent can finish.",
                        todo_id=todo_id,
                        kind="oauth_needed",
                    ),
                )
                # The run usually pauses here in practice; we stop consuming
                # so the next "Do it" can resume cleanly with fresh creds.
                return "needs_auth"

            if effect.new_status in ("done", "failed"):
                terminal = effect.new_status
                # Drain until the stream actually closes so we don't miss tail
                # events, but with a small grace.
                break

    if terminal is None:
        db.insert_step(
            todo_id=todo_id,
            user_id=user_id,
            kind="final",
            text="Done.",
        )
        db.update_todo(todo_id, {"status": "done"})
        terminal = "done"

    return terminal


async def _watch_for_cancel(
    cfg: Config,
    db: DB,
    todo_id: str,
    cancel_event: asyncio.Event,
) -> None:
    """Set `cancel_event` if the user flips the todo to status='cancelled'."""
    while not cancel_event.is_set():
        await asyncio.sleep(max(cfg.poll_interval_secs, 1.0))
        row = db.get_todo(todo_id)
        if row is None:
            cancel_event.set()
            return
        if row.get("status") == "cancelled":
            cancel_event.set()
            return


def _short(s: str, limit: int = 80) -> str:
    return s if len(s) <= limit else s[: limit - 1] + "\u2026"


def _build_prompt(title: str, detail: str, memories: list[dict]) -> str:
    task = f"{title}\n\n{detail}".strip() if detail else title
    if not memories:
        return task

    lines = [
        "Visible user memories:",
        "Use these facts when relevant. Do not mention them unless they help complete the task.",
    ]
    for memory in memories:
        category = memory.get("category")
        prefix = f"[{category}] " if category else ""
        lines.append(f"- {prefix}{memory.get('title')}: {memory.get('body')}")

    return f"{task}\n\n" + "\n".join(lines)


async def main_loop() -> None:
    setup_logging()
    cfg = load()
    db = DB(cfg)
    pusher = Pusher(cfg)
    log.info("doit runner online; polling every %ss", cfg.poll_interval_secs)

    while True:
        try:
            todo = db.claim_next_requested_todo()
        except Exception:
            log.exception("claim failed; will retry")
            todo = None

        if todo is None:
            await asyncio.sleep(cfg.poll_interval_secs)
            continue

        try:
            await run_one_todo(cfg, db, pusher, todo)
        except Exception:
            log.exception("run_one_todo crashed for %s", todo.get("id"))


def main() -> None:
    asyncio.run(main_loop())


if __name__ == "__main__":
    main()
