# Deployment

## Prerequisites on the VM

- Ubuntu 24.04, Docker + Compose v2 (`scripts/install-docker.sh`).
- Recommended: `scripts/setup-swap.sh` (4G) on **e2-micro**.
- `jq` installed (`scripts/setup-server.sh` includes it).
- `gcloud` CLI installed when `USE_GSM_SECRETS=true`.
- This repository cloned to e.g. `~/openclaw` or `/opt/openclaw` (must match the deploy workflow default or your `DEPLOY_PATH`).
- VM attached service account with IAM:
  - `roles/secretmanager.secretAccessor` (when using GSM runtime secrets)
  - `roles/aiplatform.user` (optional — only if you use **Vertex** / `google-vertex`)

## Initial bootstrap

1. `cp .env.example .env` and fill GCP + Telegram + paths.
2. **Local workstation:** `make init` (see README). **GCP VM first boot:** `make init-vm`. **VM updates:** `make deploy`.
   - Ensures `OPENCLAW_GATEWAY_TOKEN` exists (appends to `.env` if missing).
   - Writes `$OPENCLAW_CONFIG_DIR/openclaw.json` and `exec-approvals.json` from autonomy flags (re-runs overwrite these files—keep advanced edits elsewhere or adjust the script).
3. `./scripts/validate-env.sh`
4. `./scripts/fetch-secrets-gsm.sh` (required for `USE_GSM_SECRETS=true`; writes `.env.generated` with Telegram and optional `OPENAI_API_KEY` / `GEMINI_API_KEY` / `GOOGLE_PLACES_API_KEY` when `GSM_OPENAI_API_KEY_SECRET` / `GSM_GEMINI_API_KEY_SECRET` / `GSM_GOOGLE_PLACES_API_KEY_SECRET` are set)
5. `./scripts/docker-compose.sh up -d`
6. `./scripts/healthcheck.sh`
7. One-time Telegram registration:

   ```bash
   ./scripts/docker-compose.sh run -T --rm openclaw-cli channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"
   ```

## Image pinning

For reproducibility, set in `.env`:

```bash
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:main
```

Replace `main` with a release tag when you verify one (see GHCR tags in the upstream repo).

## Non-interactive Vertex onboarding

OpenClaw’s Docker flow often uses `./scripts/docker/setup.sh` **inside the upstream repository**. This template **does not** vendor that tree; instead it **seeds** `openclaw.json` with a primary model ref **`google/<GEMINI_MODEL>`** (Gemini developer API + `GEMINI_API_KEY`).

If the gateway rejects the model ref, run:

```bash
./scripts/docker-compose.sh run -T --rm openclaw-cli models list --provider google
```

and adjust **`GEMINI_MODEL`** / `openclaw.json`. For **Vertex** (`google-vertex`) instead, set **`primary`** manually and enable **Vertex AI API** + ADC; see [docs/GOOGLE_INTEGRATIONS.md](GOOGLE_INTEGRATIONS.md).

## Compose overrides

- Development / more RAM: `./scripts/docker-compose.sh -f docker-compose.dev.yml up -d`

## Resource hints (e2-micro)

The default Compose file sets `mem_limit` **768m** for the gateway. Raise `OPENCLAW_MEMORY_LIMIT` in `.env` on larger instances.

## Rollback

- `make rollback` checks out the SHA stored in `.deploy-state/previous-sha` and restarts Compose. Ensure deploys record state (see `scripts/deploy.sh`).

## Related

- [OpenClaw Docker](https://docs.openclaw.ai/install/docker)
- [Docker VM runtime / persistence](https://docs.openclaw.ai/install/docker-vm-runtime)
