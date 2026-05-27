# Operator workspace instructions

Files here are copied into each agent **`workspace/`** by `scripts/sync-operator-workspace.sh` (also run from `make init`, `make init-vm`, and `make deploy`).

| File | Behavior |
|------|----------|
| **`TOOLS.md`** | Overwritten every sync — tool/skill conventions (goplaces, gog, Maps URLs). |
| **`AGENTS.md`** | Operator block between HTML markers is merged; other lines in `workspace/AGENTS.md` are kept. |

**Not modified:** `memory/`, `SOUL.md`, `USER.md`, `IDENTITY.md`, `skills/`, or arbitrary user files.

**Per-instance overrides:** `instances/<deploy-instance-id>/TOOLS.md` or `AGENTS.md` (see `deploy/instances.json` `id` field).

Edit these in git and roll out with `make deploy` / `make deploy-all`. Ask users to send `/new` in Telegram after an update.
