# PesuClaw

Overlay runtime for [OpenClaw](https://github.com/openclaw/openclaw) — custom skills, config, and deployment tooling for the Sugato multi-tenant platform.

**This is NOT a fork.** OpenClaw is installed from npm as an upstream dependency. This repo contains only:

- **`install.sh`** — One-click provisioning (Node.js + OpenClaw + skills + config + systemd)
- **`update.sh`** — Update OpenClaw without losing customizations
- **`backup.sh`** — Daily state backup to GCS
- **`config/`** — Platform base config + per-tenant overrides
- **`skills/`** — Custom skills deployed to `~/.openclaw/skills/`
- **`workspace-templates/`** — Bootstrap workspace files (AGENTS.md, SOUL.md, IDENTITY.md)
- **`systemd/`** — Service and timer units

## Quick Start

```bash
# On a fresh Debian 12 VM:
curl -fsSL https://raw.githubusercontent.com/sugato/pesuclaw/main/install.sh | bash -s -- --tenant sugato

# Or clone and run:
git clone https://github.com/sugato/pesuclaw.git /opt/pesuclaw
cd /opt/pesuclaw
./install.sh --tenant sugato
```

## Update OpenClaw

```bash
cd /opt/pesuclaw
./update.sh
```

## Architecture

See `architecture/openclaw-application-layer-v1.md` in the Sugato.org repo for the full design rationale.
