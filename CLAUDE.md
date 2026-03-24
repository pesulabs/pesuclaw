# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## What This Repository Is

**pesuclaw** is the overlay runtime for [OpenClaw](https://github.com/openclaw/openclaw) — the custom skills, config, and GitOps deployment tooling for the Sugato multi-tenant AI agent platform.

This is **not a fork**. OpenClaw is installed from npm as an upstream dependency. This repo contains only the Sugato-specific layer on top.

## Repository Structure

- `config/base.jsonc` — Platform-wide OpenClaw base config (all tenants inherit this)
- `config/tenants/<tenant>.jsonc` — Per-tenant config overrides
- `manifests/<tenant>.yaml` — Tenant deployment manifests (version pins, feature flags)
- `skills/` — Custom skills deployed to `~/.openclaw/skills/` on each VM
- `workspace-templates/` — Bootstrap files synced to `~/.openclaw/workspace/` (AGENTS.md, SOUL.md, IDENTITY.md)
- `systemd/` — Systemd service and timer unit files
- `sync.sh` — 12-step idempotent reconciler (runs every 5 min via systemd timer on each VM)
- `install.sh` — One-click VM provisioning
- `update.sh` — Update OpenClaw without losing customizations
- `backup.sh` — Daily state backup to GCS

## Tenants

| Tenant | VM | Purpose |
|--------|-----|---------|
| `orchestrator` | `vm-orchestrator` | Platform control plane |
| `sugato` | `vm-sugato` | Sugato's own OpenClaw agent |
| `casa-gourmet` | `vm-casa-gourmet` | Client tenant |

GCP project: `sugato-489514`, region: `us-central1-a`

## Sync Flow

```
1. Edit config, skill, or manifest in this repo
2. git push to master (after PR from staging)
3. sync.sh on each VM runs every 5 min (pesuclaw-sync.timer)
   OR trigger manually: ./sync.sh
4. sync.sh 12-step reconciliation:
   Pull repo → OpenClaw version → packages → skills → workspace-templates → config → restart if changed
5. Verify: systemctl status openclaw, openclaw --version, journalctl -u openclaw -n 20
```

## Git Workflow

**Never push directly to master.**

```
feature branch → staging → PR staging → master → merge
```

- Work on a feature branch
- Merge feature → `staging`
- Open PR from `staging` → `master`
- Merge only after verification

## Skills

Each skill lives in `skills/<skill-name>/` with:
- `SKILL.md` — Skill definition loaded by OpenClaw
- `_meta.json` — Metadata (name, version, description)
- `scripts/` — Supporting scripts the skill can invoke
- `references/` — Reference docs the skill can read

Current skills: `agentmail`, `here-now`, `memory-consolidator`, `memory-extractor`, `memory-forget`, `memory-hygiene`, `memory-reflect`, `youtube-transcript`

## Key Files

- `config/base.jsonc` — Edit this for platform-wide changes
- `config/tenants/<tenant>.jsonc` — Edit for tenant-specific overrides
- `manifests/<tenant>.yaml` — Pin OpenClaw version per tenant here
- `sync.sh` — Source of truth for what gets deployed and how

## Agent Routing (sugato-ops)

Delegate to sugato-ops agents automatically — do not wait for the user to name one.

| Task pattern | Agent |
|---|---|
| pesuclaw sync status, OpenClaw version, config drift, skill deployment, rollout | `deploy-worker` |
| Per-tenant VM service status, openclaw logs, config on VM | `tenant-worker` |
| GCP VM state, infrastructure underlying a tenant | `infra-worker` |
| mem0, pgvector, DB connectivity issues on a VM | `debug-worker` |
| Task spans infrastructure + deployment | `ops-worker` |

## Conventions

- Config files use `.jsonc` (JSON with comments) — do not convert to plain JSON
- Manifests use `.yaml` — one file per tenant
- Skill names are kebab-case
- Never modify `sync.sh` without testing on a non-production tenant first
- `workspace-templates/standard/` is the base; tenant-specific overrides go in `workspace-templates/<tenant>/`
