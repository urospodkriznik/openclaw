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

1. Repository variable **`DEPLOY_INSTANCES_JSON`** (optional — same JSON as your local `instances.json`, one line)
2. `deploy/instances.json` if present in the checkout (e.g. you force-added it on a private fork)
3. `deploy/instances.example.json` → deploys `~/openclaw`

For a custom folder (e.g. `my-stack`) without renaming the clone, set **Settings → Secrets and variables → Actions → Variables**:

- Name: `DEPLOY_INSTANCES_JSON`
- Value: `{"instances":[{"id":"primary","path":"my-stack"}]}`

See [docs/GITHUB_ACTIONS.md](../docs/GITHUB_ACTIONS.md).
