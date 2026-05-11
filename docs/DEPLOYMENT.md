# Deployment

## Prerequisites on the VM

- Ubuntu 24.04, Docker + Compose v2 (`scripts/install-docker.sh`).
- Recommended: `scripts/setup-swap.sh` (4G) on **e2-micro**.
- `jq` installed (`scripts/setup-server.sh` includes it).
- `gcloud` CLI installed when `USE_GSM_SECRETS=true`.
- This repository cloned to e.g. `~/openclaw-gcp-agent` or `/opt/openclaw-gcp-agent`.
- VM attached service account with IAM:
  - `roles/aiplatform.user` (Vertex)
  - `roles/secretmanager.secretAccessor` (when using GSM runtime secrets)

## Initial bootstrap

1. `cp .env.example .env` and fill GCP + Telegram + paths.
2. `./scripts/bootstrap-config.sh`
   - Ensures `OPENCLAW_GATEWAY_TOKEN` exists (appends to `.env` if missing).
   - Writes `$OPENCLAW_CONFIG_DIR/openclaw.json` and `exec-approvals.json` from autonomy flags (re-runs overwrite these files—keep advanced edits elsewhere or adjust the script).
3. `./scripts/validate-env.sh`
4. `./scripts/fetch-secrets-gsm.sh` (required for `USE_GSM_SECRETS=true`; writes `.env.generated`)
5. `docker compose up -d`
6. `./scripts/healthcheck.sh`
7. One-time Telegram registration:

   ```bash
   docker compose run -T --rm openclaw-cli channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"
   ```

## Image pinning

For reproducibility, set in `.env`:

```bash
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:main
```

Replace `main` with a release tag when you verify one (see GHCR tags in the upstream repo).

## Non-interactive Vertex onboarding

OpenClaw’s Docker flow often uses `./scripts/docker/setup.sh` **inside the upstream repository**. This template **does not** vendor that tree; instead it **seeds** `openclaw.json` with a primary model ref `google-vertex/<VERTEX_MODEL>`.

**TODO:** Confirm the exact non-interactive `onboard` / `models auth` steps for `google-vertex` for your pinned image version. If the gateway rejects the model ref, run:

```bash
docker compose run -T --rm openclaw-cli models list --provider google-vertex
```

and adjust `VERTEX_MODEL` / `openclaw.json`.

## Compose overrides

- Development / more RAM: `docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d`

## Resource hints (e2-micro)

The default Compose file sets `mem_limit` **768m** for the gateway. Raise `OPENCLAW_MEMORY_LIMIT` in `.env` on larger instances.

## Rollback

- `make rollback` checks out the SHA stored in `.deploy-state/previous-sha` and restarts Compose. Ensure deploys record state (see `scripts/deploy.sh`).

## Related

- [OpenClaw Docker](https://docs.openclaw.ai/install/docker)
- [Docker VM runtime / persistence](https://docs.openclaw.ai/install/docker-vm-runtime)
