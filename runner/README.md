# runner

Thin always-on worker that bridges Supabase and Hermes. No web server, no auth,
no public ports — outbound calls only.

## What it does

A single async loop:

1. Polls Supabase for `todos.status = 'requested'` (atomically claims one by
   flipping it to `running`).
2. Looks up the user's Hermes endpoint in `user_hermes`.
3. `POST http://127.0.0.1:<port>/v1/runs` with the todo text + a system prompt.
4. Consumes `GET /v1/runs/{id}/events` (Server-Sent Events).
5. Translates Hermes events into rows in `todo_steps` and status changes on
   `todos`. The iOS app sees them live via Supabase Realtime.
6. Sends APNs pushes on the key moments: **needs Gmail auth**, **done**,
   **failed**.

Concurrently it polls the todo's status — if the user sets it to `cancelled`,
the runner calls `POST /v1/runs/{id}/stop` and exits the inner loop cleanly.

## Layout

```
runner/
|-- runner/
|   |-- __main__.py     entrypoint (python -m runner)
|   |-- runner.py       main loop + per-todo orchestration
|   |-- hermes.py       /v1/runs client + SSE parser
|   |-- events.py       map Hermes events -> todo_steps + status
|   |-- db.py           Supabase REST (service_role)
|   |-- push.py         APNs (aioapns)
|   |-- config.py       env loading
|-- requirements.txt
|-- Dockerfile
|-- .env.example
```

## Local run

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # fill in real values
python -m runner
```

## Deploy on the VM (systemd)

See `../hermes/setup.md` for the full provisioning runbook. The runner is the
last step there.

## Notes

- The runner uses Supabase's **service_role** key so its writes bypass RLS.
  Keep that key off the iOS app at all costs — it's server-only.
- For the "thinking timeline" we deliberately ignore token-by-token deltas
  (they'd be too noisy) and emit one row per **tool started** + **tool result**,
  plus a single **final** row at the end. Good UX, low write volume.
- OAuth detection: when a tool emits text that looks like a Composio OAuth
  redirect URL, the runner writes a `oauth_needed` step + flips status to
  `needs_auth` + fires a push. The iOS app opens the URL via
  `ASWebAuthenticationSession` and the user just re-taps "Do it" once they're
  back. (Composio holds the OAuth tokens server-side, so the next run sees the
  connection already in place.)
