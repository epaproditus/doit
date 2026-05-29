# doit

A "do-it-for-me" todo iOS app. Each todo can be executed by a cloud-hosted
[Hermes Agent](https://hermes-agent.nousresearch.com/docs/), which works in the
background and streams its thinking back into the app in real time.

## Architecture

```
iOS (SwiftUI, Sign in with Apple)
   |
   v
Supabase (managed) ............... Auth + Postgres + Realtime + Edge Function
   ^
   |
Runner (on one VM) ............... watches Supabase -> drives Hermes -> sends APNs
   |
   v
Hermes Gateway (same VM) ......... one profile per user, isolated memory + OAuth
   |
   v
Composio Connect (MCP) ........... managed OAuth for Gmail, Calendar, Slack, ...
```

- **One VM total**, not one per user. Each user gets a Hermes **profile** with
  its own API server port, memory, and OAuth connections.
- The **runner** is the only custom backend; it's outbound-only (no public port).
- Real-world actions (sending email, etc.) go through **Composio Connect** so we
  never build OAuth or store tokens ourselves.

## Layout

```
doit/
|-- ios/         SwiftUI app (Xcode project)
|-- runner/      Python worker: Supabase -> Hermes /v1/runs -> APNs
|-- hermes/      Deploy config + setup runbook (NOT Hermes source)
|-- supabase/    SQL migrations + Edge Functions
```

## Required accounts

| Service | Purpose | Already have? |
| --- | --- | --- |
| Apple Developer | Sign in with Apple, APNs push | yes |
| Supabase | Auth, DB, Realtime, Edge Functions | yes |
| Cloud VM provider (Hetzner / DigitalOcean) | runs Hermes + runner | needed |
| Nous Portal | LLM + Hermes built-in tools | needed |
| Composio | OAuth integrations (Gmail, etc.) | needed |

See `hermes/setup.md` for provisioning the VM and `supabase/README.md` for the
managed-side setup.
