# APNs push in doit

How Apple Push Notification service (APNs) fits into doit, what the runner's
`sandbox` vs `production` flag does, and how to configure it for Xcode dev
builds vs TestFlight.

## Role in the system

```text
Runner (VM)                    Apple APNs              iOS app
    |                              |                      |
    |  JWT (.p8 key) + device token|                      |
    |----------------------------->|                      |
    |                              |---- notification --->|
    |                              |                      |
    |                              |     (if app backgrounded / killed)
```

Doit uses APNs as a **backup** channel. When the app is open, task and agent
updates flow through **Supabase Realtime** into `TodoStore` — that is the
primary in-app path. See [`task-realtime.md`](task-realtime.md) and
[`README.md`](../README.md).

The runner sends pushes at key moments (run finished, needs OAuth, activity
sync while backgrounded). Implementation: [`runner/runner/push.py`](../runner/runner/push.py).

## Sandbox vs production (Apple's two environments)

Apple does **not** use one global push pipe. Every device token is tied to an
**environment**:

| How the app is installed | APNs environment | APNs API host |
| ------------------------ | ------------------ | ------------- |
| Xcode → Run on device (Debug) | **Sandbox** | `api.sandbox.push.apple.com` |
| **TestFlight** | **Production** | `api.push.apple.com` |
| App Store | **Production** | `api.push.apple.com` |

TestFlight is **production** APNs, even though it is beta testing. There is no
separate "TestFlight APNs environment."

Sandbox and production tokens for the **same physical iPhone** are different
hex strings. Opening the TestFlight build and allowing notifications registers
a production token; an old sandbox token from an Xcode install may still sit in
the database but only works against the sandbox endpoint.

## The runner flag: `APNS_USE_SANDBOX`

On the runner VM, `/opt/doit/runner/.env`:

```bash
APNS_USE_SANDBOX=true   # sandbox host  → Xcode dev installs
APNS_USE_SANDBOX=false  # production host → TestFlight / App Store
```

[`runner/runner/push.py`](../runner/runner/push.py) reads this via
[`config.py`](../runner/runner/config.py) and picks **one** base URL for all
sends:

- `true` → `https://api.sandbox.push.apple.com`
- `false` → `https://api.push.apple.com`

After changing the flag:

```bash
ssh root@<vm> 'systemctl restart doit-runner'
```

### Current limitation: one environment at a time

The runner has a **single** boolean. It cannot simultaneously deliver to
sandbox tokens (Xcode dev) and production tokens (TestFlight) with one config.

| VM setting | Xcode dev push | TestFlight push |
| ---------- | -------------- | --------------- |
| `APNS_USE_SANDBOX=true` | Works | Does not work |
| `APNS_USE_SANDBOX=false` | Does not work | Works |

**Workaround today:** flip the flag when you switch between "I am testing from
Xcode" and "I am testing TestFlight." For local dev without push, rely on
Realtime (most UI updates still work).

**Possible future improvement:** dual-send (try both endpoints per notification)
or store `apns_environment` per row in `devices` and route each token to the
correct host. Not implemented yet.

## Apple Developer setup (New Material)

### App ID

Under **Identifiers**, `com.newmaterial.doit` must have **Push Notifications**
enabled.

### APNs auth key (`.p8`)

Create under **Certificates, IDs & Profiles → Keys**:

1. Enable **Apple Push Notifications service (APNs)**.
2. Prefer **Sandbox & Production** when configuring the key so one `.p8`
   works for both endpoints (only the runner **host** changes with
   `APNS_USE_SANDBOX`).
3. Download the `.p8` once; store on the VM at e.g.
   `/etc/doit/AuthKey_<KEY_ID>.p8` (mode `600`).

Sign in with Apple uses a **different** portal surface (App ID capability +
Services ID + Supabase). It does not use this APNs key unless you also enabled
Sign in with Apple on the same key for OAuth secret generation.

### Team and bundle ID

| Setting | doit value |
| ------- | ---------- |
| Team ID | `433N42F295` (New Material, Inc.) |
| `APNS_TOPIC` | `com.newmaterial.doit` (main app bundle ID, not the widget) |

The Live Activity widget extension (`com.newmaterial.doit.doitActivityWidget`)
does not receive pushes; the **host app** topic is used.

## Runner environment variables

See [`runner/.env.example`](../runner/.env.example):

| Variable | Purpose |
| -------- | ------- |
| `APNS_KEY_PATH` | Path to `.p8` on the VM |
| `APNS_KEY_ID` | 10-character Key ID from Apple |
| `APNS_TEAM_ID` | Apple Developer Team ID |
| `APNS_TOPIC` | Main app bundle ID (`com.newmaterial.doit`) |
| `APNS_USE_SANDBOX` | `true` = sandbox, `false` = production |

If any of `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, or `APNS_TOPIC` is
missing, the runner logs a warning and **skips all pushes** (no-op).

Deploy script [`scripts/deploy-runner.sh`](../scripts/deploy-runner.sh) does
**not** overwrite VM `.env` — APNS changes are manual on the droplet.

## iOS app: token registration

[`ios/doit/doit/Push/PushManager.swift`](../ios/doit/doit/Push/PushManager.swift):

1. After sign-in, requests notification permission.
2. Calls `registerForRemoteNotifications()`.
3. On token from the system, upserts into Supabase `devices` as
   `(user_id, apns_token)`.

Schema ([`20240601000001_init.sql`](../supabase/migrations/20240601000001_init.sql)):

```sql
create table devices (
    user_id    uuid not null references auth.users(id) on delete cascade,
    apns_token text not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, apns_token)
);
```

A user can have **multiple** tokens (e.g. old sandbox + new production) because
the primary key is the pair. The runner does not filter by environment today —
it sends every stored token to the **one** endpoint selected by
`APNS_USE_SANDBOX`. Wrong-environment tokens get `BadDeviceToken` from Apple
and are logged as warnings.

Push does **not** work in the iOS Simulator; use a real device or TestFlight.

## Operational cheat sheet

### Shipping TestFlight (production pushes)

```bash
APNS_USE_SANDBOX=false
APNS_TOPIC=com.newmaterial.doit
APNS_TEAM_ID=433N42F295
# ... key path / id ...
systemctl restart doit-runner
```

Install from TestFlight, open the app, tap **Allow** for notifications so a
**production** token is registered.

### Local Xcode dev (sandbox pushes)

```bash
APNS_USE_SANDBOX=true
systemctl restart doit-runner
```

Build with Xcode → Run to a plugged-in iPhone (not TestFlight build).

### Verify credentials on the VM (without a real device token)

From `/opt/doit/runner` with the venv:

```bash
.venv/bin/python - <<'PY'
import httpx
from runner.config import load
from runner.push import Pusher

cfg = load()
p = Pusher(cfg)
base = "https://api.sandbox.push.apple.com" if cfg.apns_use_sandbox else "https://api.push.apple.com"
token = p._bearer_token()
resp = httpx.Client(http2=True, base_url=base, timeout=20).post(
    "/3/device/0000000000000000000000000000000000000000000000000000000000000000",
    json={},
    headers={
        "authorization": f"bearer {token}",
        "apns-topic": cfg.apns_topic,
        "apns-push-type": "background",
        "apns-priority": "5",
    },
)
print(resp.status_code, resp.text)
PY
```

| Response | Meaning |
| -------- | ------- |
| `400 BadDeviceToken` | JWT and topic are **valid** (fake token rejected as expected) |
| `403 InvalidProviderToken` | Wrong team ID, wrong `.p8`, or key not allowed for this environment |

## Troubleshooting

| Symptom | Check |
| ------- | ----- |
| No push on TestFlight | `APNS_USE_SANDBOX=false`; user opened TestFlight build and allowed notifications; `devices` row exists for that user |
| No push on Xcode dev | `APNS_USE_SANDBOX=true`; not using TestFlight build on the same test |
| `InvalidProviderToken` in logs | `APNS_TEAM_ID` matches key's team; `.p8` on VM matches `APNS_KEY_ID` |
| Push sent but app unchanged | App may be foregrounded — Realtime handles in-app; push is for background. Check `todo_id` / `kind` in payload |
| Sign-in works but push fails | Separate systems — Sign in with Apple does not depend on APNs key |

Runner logs: `journalctl -u doit-runner -f` on the VM.

## Related docs

- [`DEMO.md`](../DEMO.md) — end-to-end demo; push is one step in the flow
- [`runner/README.md`](../runner/README.md) — runner deploy and env overview
- [`hermes/setup.md`](../hermes/setup.md) — VM provisioning (runner `.env` lives here)
