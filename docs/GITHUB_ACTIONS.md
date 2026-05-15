# GitHub Actions

## Workflows

| File | When | What |
|------|------|------|
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | PR + push | ShellCheck, compose config, required files, secret-pattern scan |
| [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) | Push to `main` or `master` + manual | SSH deploy using the instances manifest (see below) |

## Deploy manifest (default + your override)

| File | In git? | Purpose |
|------|---------|---------|
| [deploy/instances.example.json](../deploy/instances.example.json) | Yes | Default: one agent at **`~/openclaw`** |
| `deploy/instances.json` | **No** (gitignored) | Your real folder names and extra instances |

### Local / VM setup

```bash
make deploy-instances-init   # copies example → instances.json once
# edit deploy/instances.json — set "path" to your clone directory name under $HOME
```

Copy the same `deploy/instances.json` into your VM clone(s) for `make deploy-all`.

Details: [deploy/README.md](../deploy/README.md).

### What GitHub Actions uses

On each push, the workflow picks the manifest in this order:

1. Repository variable **`DEPLOY_INSTANCES_JSON`** (optional) — same JSON as your local `instances.json`, as a single line
2. `deploy/instances.json` if it exists in the checkout (unusual; file is gitignored by default)
3. **`deploy/instances.example.json`** → deploys **`~/openclaw`**

**Single agent, default path:** clone to `~/openclaw`, push to `main` — nothing else required.

**Custom clone folder** (e.g. `~/my-stack`): either

- Set **Settings → Secrets and variables → Actions → Variables** → `DEPLOY_INSTANCES_JSON` = `{"instances":[{"id":"primary","path":"my-stack"}]}`, or  
- Symlink: `ln -sfn ~/my-stack ~/openclaw` and keep the default example manifest.

## Multi-instance deploy (two agents on one VM)

One push can update **multiple clones**. Each agent needs its own folder, `.env`, Telegram bot, GSM secrets, and **unique host ports**.

Add entries in your **gitignored** `deploy/instances.json` (start from the example):

```json
{
  "instances": [
    { "id": "primary", "path": "openclaw" },
    { "id": "secondary", "path": "openclaw-secondary" }
  ]
}
```

Mirror that JSON in **`DEPLOY_INSTANCES_JSON`** for CI, or CI will only deploy paths listed in the example file.

The workflow runs a **matrix job** per instance (`fail-fast: false`).

### Per-instance setup on the VM

Repeat **once per agent**:

1. Clone: `mkdir -p ~/openclaw-secondary && cd ~/openclaw-secondary && git clone … .`
2. Unique `.env` (ports, `GSM_*` secret names, optional gog vars)
3. `make init-vm` in that directory
4. Add the entry to `deploy/instances.json` and update `DEPLOY_INSTANCES_JSON` if you use it

### Manual deploy all instances on the VM

```bash
cd ~/openclaw
make deploy-all
```

## One-time VM preparation (shared)

1. At least one clone (default **`~/openclaw`**, or your path in `instances.json`).

2. VM service account IAM: `roles/secretmanager.secretAccessor` (+ optional `roles/aiplatform.user`).

3. **Deploy user + `sudo`:** passwordless `sudo` for `chown` (see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)).

4. Per-clone `.env` with `USE_GSM_SECRETS=true`, `GSM_PROJECT_ID`, `GSM_TELEGRAM_BOT_TOKEN_SECRET`, etc.

## Secrets

| Secret / variable | Notes |
|-------------------|--------|
| `GCP_VM_HOST` | VM IP or hostname |
| `GCP_VM_USER` | SSH user; must own every `path` in the manifest |
| `GCP_VM_SSH_KEY` | Private SSH key |
| `GCP_VM_PORT` | Optional; default **22** |
| `DEPLOY_INSTANCES_JSON` | Optional **variable** — overrides example for custom paths / multi-instance |

## What deploy does (per instance)

1. `git pull` on the target clone.
2. Ensures `USE_GSM_SECRETS=true` in `.env`.
3. `./scripts/remote-deploy.sh` (reown, bootstrap, GSM fetch, compose up, healthcheck).

## Branch protection

Require `ci` on PRs before merging to `main`.
