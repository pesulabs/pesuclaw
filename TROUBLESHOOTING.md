# PesuClaw Troubleshooting Guide

This guide covers common issues encountered when deploying OpenClaw instances using the `pesuclaw` GitOps synchronization scripts (`install.sh` and `sync.sh`), particularly focusing on configuration strictness and service initialization failures.

## 1. OpenClaw Service Fails to Start ("Missing Config" Error)

If the `openclaw.service` crashes continuously and `journalctl -u openclaw` shows a `Missing config. Run openclaw setup...` error immediately after `sync.sh` completes, the gateway validation might be rejecting the generated `openclaw.json` or its `$include` dependencies.

### Common Causes & Solutions:

**A. `$include` Path Sandboxing Escapes**
OpenClaw enforces strict file boundary checks. The `$include` paths defined in `openclaw.json` *must* resolve inside the `OPENCLAW_HOME` directory.
- **Problem:** If `$include` points to a global path like `/opt/pesuclaw/config/base.jsonc`, the `openclaw doctor` engine will throw an `Include path escapes config directory` error, preventing the service from booting.
- **Fix:** In `pesuclaw/sync.sh`, ensure the config template layers (`base.jsonc`, `<tenant>.jsonc`) are copied *into* the `$OPENCLAW_HOME/config/` directory first, and that the seeded `openclaw.json` references them via relative internal paths (e.g., `"./config/base.jsonc"`).

**B. Strict JSON Parsing vs. JSONC**
While the extension `.jsonc` implies comments are allowed, internal components of OpenClaw (such as the `auth-profiles` loader) use strict NodeJS `JSON.parse` under the hood.
- **Problem:** JavaScript-style comments (`//`) or trailing commas inside `base.jsonc` or `<tenant>.jsonc` will cause the load process to fail with syntax errors.
- **Fix:** Ensure all config layers (in `pesuclaw/config/`) contain strictly compliant JSON. Remove all comments and trailing commas natively from the repository files. 

**C. Deprecated JSON Schema Keys**
As OpenClaw evolves, deprecated keys trigger fatal validation errors instead of warnings.
- **Problem:** Keys like `tools.elevated: []` (expected object), `cron.hotReload`, or `channels.defaults.configWrites` will cause a `Config invalid` crash on startup.
- **Fix:** Stay up-to-date with OpenClaw's expected schema and remove or update these properties directly within `pesuclaw/config/base.jsonc`.

**D. Double Path Resolution for `OPENCLAW_HOME`**
- **Problem:** If `Environment=OPENCLAW_HOME=/home/openclaw/.openclaw` is set in the `openclaw.service` unit, OpenClaw attempts to map the root path globally inside its execution node, sometimes defaulting to searching in `~/.openclaw/.openclaw/openclaw.json`.
- **Fix:** `OPENCLAW_HOME` in `openclaw.service` (and internal `PATH` checks) should just point to `/home/openclaw`. The application automatically targets the `.openclaw` subdirectory natively.

## 2. Gateway Authentication Token

The OpenClaw gateway relies on an authorization token to accept external or local API calls (e.g., from the Canvas or Web UI).

**A. Secret Manager Authentication Lag**
- **Problem:** Originally, the tenant's gateway token was provisioned via Google Cloud Secret Manager. However, if the VM boots up and GCP authentication methods aren't instantaneously ready or reachable (e.g., network initialization lag, or expired dev tokens), `sync.sh` fails to extract the token, causing a config initialization failure on `openclaw.json`.
- **Fix:** The gateway token should be generated and kept locally if remote ingress isn't exclusively required. 
- In `pesuclaw/sync.sh`, the system generates a secure 32-character random string (`openssl rand -hex 16` or `urandom`) and stores it directly into `/etc/openclaw/env` as `OPENCLAW_GATEWAY_TOKEN` across initial boots.

## 3. Silent Skill Synchronization Failures

The `pesuclaw/sync.sh` script installs skills designated in the `manifests/<tenant>.yaml` file.

- **Problem:** If a skill is listed in the yaml manifest (e.g., `whatsapp-sales`) but its corresponding folder does not exist inside the `pesuclaw/skills/` remote repository (e.g., it hasn't been committed to Git), `sync.sh` will print a soft `Warning: Skill source not found` and continue executing without failing the reconciliation. 
- **Fix:** If a skill fails to deploy to `~/.openclaw/skills/`, check the remote repository first to ensure the folder (`skills/<skill-name>`) is tracked, committed, and pulled successfully during the first phase of `sync.sh`.
