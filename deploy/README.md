# Deploy instances manifest

| File | Tracked | Purpose |
|------|---------|---------|
| `instances.example.json` | Yes | Default single agent at `~/openclaw` |
| `instances.json` | **No** (gitignored) | Your real paths and instance ids |

## First-time setup

```bash
cp deploy/instances.example.json deploy/instances.json
# Edit deploy/instances.json — set "path" to your VM clone folder name
```

On the VM, copy the same file into each clone (or only into the clone you use for `make deploy-all`):

```bash
cp deploy/instances.example.json deploy/instances.json
```

## GitHub Actions

The workflow does **not** commit `instances.json`. It uses, in order:

1. Repository **variable** **`DEPLOY_INSTANCES_JSON`** (preferred) or **secret** with the same name — one line, same JSON as your local `instances.json`
2. `deploy/instances.json` if present in the checkout (unusual; gitignored by default)
3. `deploy/instances.example.json` → deploys `~/openclaw`

**If deploy still targets `~/openclaw`:** open the workflow run → **prepare** job → **Load deploy instances**. It must log `Using repository variable DEPLOY_INSTANCES_JSON` and `path=oc_uros`. If it says `instances.example.json`, the variable is missing on **that** GitHub repo (e.g. `openclaw/openclaw` vs your local folder name) or was added under Secrets without the workflow reading it (this repo checks both).

For a custom folder (e.g. `my-stack`) without renaming the clone, set **Settings → Secrets and variables → Actions → Variables**:

- Name: `DEPLOY_INSTANCES_JSON`
- Value: `{"instances":[{"id":"primary","path":"my-stack"}]}`

See [docs/GITHUB_ACTIONS.md](../docs/GITHUB_ACTIONS.md).
