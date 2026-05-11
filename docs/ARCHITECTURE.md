# Architecture

## Components

| Layer | Responsibility |
|-------|----------------|
| **Telegram** | Primary human ↔ agent channel (HTTP long poll / Bot API). |
| **OpenClaw gateway** | WebSocket gateway, sessions, tool routing, channel adapters. Runs in Docker (`openclaw-gateway`). |
| **OpenClaw CLI** | Sidecar image sharing the gateway network namespace for non-interactive `docker compose run` operations. |
| **Vertex AI** | Default LLM backend via provider `google-vertex` and **Application Default Credentials**. |
| **Persistent volumes** | Host paths `OPENCLAW_CONFIG_DIR` → `/home/node/.openclaw`, `OPENCLAW_WORKSPACE_DIR` → workspace inside OpenClaw home. |
| **GitHub Actions** | Optional CD: SSH to VM, enforce GSM mode, fetch runtime secrets, `docker compose pull && up`, health probe. |

## Trust boundaries

- Anyone who can message your Telegram bot **influences** the agent (subject to OpenClaw channel allowlists you configure upstream).
- VM service account IAM and Secret Manager access are privileged boundaries; keep IAM roles least-privilege.
- **Exec approvals** and `tools.exec` reduce accidental shell execution but are **not** a multi-tenant isolation boundary.

## Data flow (happy path)

1. Inbound Telegram message hits the gateway container.
2. Gateway selects the configured model (`google-vertex/...`) and calls Vertex with ADC.
3. Tool use (files, optional shell) operates against the **mounted workspace** and host policy.
4. Reply returns via Telegram.

## What this repo adds vs upstream OpenClaw

- Opinionated **`.env`**, **bootstrap**, and **validation** scripts.
- **GCP-focused** documentation and deploy automation.
- **Autonomy mode** presets written to `openclaw.json` and `exec-approvals.json`.

See also [DEPLOYMENT.md](DEPLOYMENT.md) and [SECURITY.md](SECURITY.md).
