#!/usr/bin/env bash
# Testing CI pipeline run
# PesuClaw Sync — GitOps reconciler
#
# Reads the tenant manifest and reconciles the VM to match desired state.
# Designed to run:
#   - On a systemd timer (every 5 min)
#   - Manually: ./sync.sh --tenant sugato
#   - From install.sh on first boot
#
# Idempotent: safe to run repeatedly. Only changes what's different.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${OPENCLAW_HOME:-/home/openclaw/.openclaw}"
OPENCLAW_USER="openclaw"
BIN_DIR="/opt/pesuclaw/bin"
TENANT_ID=""
DRY_RUN=false
VERBOSE=false

# ── Parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant) TENANT_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$TENANT_ID" ]]; then
  # Try to read from /etc/openclaw/tenant-id
  if [[ -f /etc/openclaw/tenant-id ]]; then
    TENANT_ID=$(cat /etc/openclaw/tenant-id)
  else
    echo "Error: --tenant required (or set /etc/openclaw/tenant-id)"
    exit 1
  fi
fi

MANIFEST="$SCRIPT_DIR/manifests/${TENANT_ID}.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: Manifest not found: $MANIFEST"
  exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────
log() { echo "[sync] $*"; }
vlog() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[sync] $*"
  fi
}
changed=0

read_yaml() {
  # Simple YAML list reader — extracts values under a key
  # Usage: read_yaml manifests/sugato.yaml skills
  local file="$1" key="$2"
  awk -v key="$key:" '
    $0 ~ "^"key { found=1; next }
    found && /^[a-z_]/ { found=0 }
    found && /^  - / { gsub(/^  - /, ""); gsub(/#.*/, ""); gsub(/[[:space:]]+$/, ""); if ($0 != "") print }
  ' "$file"
}

read_yaml_value() {
  # Read a single YAML value
  local file="$1" key="$2"
  grep "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/#.*//' | xargs || true
}

# ── 1. Pull latest repo ──────────────────────────────────────────────
log "Pulling latest pesuclaw repo..."
cd "$SCRIPT_DIR"
if [[ "$DRY_RUN" == "false" ]]; then
  git pull --ff-only -q 2>/dev/null || log "Warning: git pull failed (offline or conflict)"
fi

# Re-read manifest after pull
DESIRED_VERSION=$(read_yaml_value "$MANIFEST" "openclaw_version")
WORKSPACE_TEMPLATE=$(read_yaml_value "$MANIFEST" "workspace_template")
CONFIG_OVERRIDE=$(read_yaml_value "$MANIFEST" "config_override")

log "Reconciling tenant: $TENANT_ID"
log "  Desired OpenClaw: $DESIRED_VERSION"

# ── 2. Reconcile OpenClaw version ─────────────────────────────────────
# Extract semver only: "OpenClaw 2026.3.13 (61d171a)" -> "2026.3.13"
CURRENT_VERSION=$(openclaw --version 2>/dev/null | awk '{print $2}' || echo "not-installed")

if [[ "$DESIRED_VERSION" == "latest" ]]; then
  # Check if an update is available
  AVAILABLE=$(npm view openclaw version 2>/dev/null || echo "$CURRENT_VERSION")
  if [[ "$CURRENT_VERSION" != "$AVAILABLE" ]]; then
    log "  Updating OpenClaw: $CURRENT_VERSION -> $AVAILABLE"
    if [[ "$DRY_RUN" == "false" ]]; then
      npm install -g "openclaw@latest" --loglevel=warn
      changed=1
    fi
  else
    vlog "  OpenClaw $CURRENT_VERSION is current"
  fi
else
  if [[ "$CURRENT_VERSION" != "$DESIRED_VERSION" ]]; then
    log "  Pinning OpenClaw: $CURRENT_VERSION -> $DESIRED_VERSION"
    if [[ "$DRY_RUN" == "false" ]]; then
      npm install -g "openclaw@${DESIRED_VERSION}" --loglevel=warn
      changed=1
    fi
  else
    vlog "  OpenClaw $CURRENT_VERSION matches manifest"
  fi
fi

# ── 3. Reconcile system packages ──────────────────────────────────────
DESIRED_PACKAGES=$(read_yaml "$MANIFEST" "packages")
if [[ -n "$DESIRED_PACKAGES" ]]; then
  MISSING_PACKAGES=""
  while IFS= read -r pkg; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    else
      vlog "  Package '$pkg' already installed"
    fi
  done <<< "$DESIRED_PACKAGES"

  if [[ -n "$MISSING_PACKAGES" ]]; then
    log "  Installing packages:$MISSING_PACKAGES"
    if [[ "$DRY_RUN" == "false" ]]; then
      apt-get update -qq
      # shellcheck disable=SC2086
      apt-get install -y -qq $MISSING_PACKAGES
    fi
  fi
fi

# ── 4. Reconcile pip packages ─────────────────────────────────────────
DESIRED_PIP=$(read_yaml "$MANIFEST" "pip")
if [[ -n "$DESIRED_PIP" ]]; then
  while IFS= read -r pkg; do
    if ! pip3 show "$pkg" &>/dev/null 2>&1; then
      log "  Installing pip: $pkg"
      if [[ "$DRY_RUN" == "false" ]]; then
        pip3 install "$pkg" -q
      fi
    else
      vlog "  Pip '$pkg' already installed"
    fi
  done <<< "$DESIRED_PIP"
fi

# ── 5. Reconcile npm global packages ─────────────────────────────────
DESIRED_NPM=$(read_yaml "$MANIFEST" "npm_global")
if [[ -n "$DESIRED_NPM" ]]; then
  while IFS= read -r pkg; do
    if ! npm list -g "$pkg" &>/dev/null 2>&1; then
      log "  Installing npm global: $pkg"
      if [[ "$DRY_RUN" == "false" ]]; then
        npm install -g "$pkg" --loglevel=warn
      fi
    else
      vlog "  Npm '$pkg' already installed"
    fi
  done <<< "$DESIRED_NPM"
fi

# ── 6. Reconcile mem0 plugin ──────────────────────────────────────────
vlog "  Ensuring mem0 plugin is installed..."
if command -v openclaw &>/dev/null; then
  if ! su - "$OPENCLAW_USER" -c "openclaw plugins list 2>/dev/null" | grep -q "openclaw-mem0"; then
    log "  Installing mem0 plugin..."
    if [[ "$DRY_RUN" == "false" ]]; then
      su - "$OPENCLAW_USER" -c "openclaw plugins install @mem0/openclaw-mem0" 2>/dev/null || \
        log "  Warning: mem0 plugin install failed"
      # Fix known packaging issues in @mem0/openclaw-mem0
      MEM0_DIR="$OPENCLAW_HOME/extensions/openclaw-mem0"
      if [[ -d "$MEM0_DIR" ]]; then
        # Fix entry point: ./index.ts -> ./dist/index.js (source not included in npm package)
        sed -i 's|"./index.ts"|"./dist/index.js"|' "$MEM0_DIR/package.json" 2>/dev/null
        # Create plugin manifest if missing
        if [[ ! -f "$MEM0_DIR/openclaw.plugin.json" ]]; then
          cat > "$MEM0_DIR/openclaw.plugin.json" <<'PLUGINJSON'
{
  "id": "openclaw-mem0",
  "name": "Memory (Mem0)",
  "kind": "memory",
  "description": "Mem0 memory backend — Mem0 platform or self-hosted open-source",
  "configSchema": {
    "type": "object",
    "additionalProperties": true,
    "properties": {
      "mode": { "type": "string", "enum": ["open-source", "platform"] },
      "autoRecall": { "type": "boolean" },
      "autoCapture": { "type": "boolean" },
      "topK": { "type": "number" },
      "searchThreshold": { "type": "number" },
      "oss": { "type": "object", "additionalProperties": true }
    }
  }
}
PLUGINJSON
          chown "$OPENCLAW_USER:$OPENCLAW_USER" "$MEM0_DIR/openclaw.plugin.json"
        fi
      fi
      changed=1
    fi
  else
    vlog "  mem0 plugin already installed"
  fi
fi

# ── 7. Reconcile skills ──────────────────────────────────────────────
log "  Syncing skills..."
DESIRED_SKILLS=$(read_yaml "$MANIFEST" "skills")
SKILLS_DIR="$OPENCLAW_HOME/skills"
mkdir -p "$SKILLS_DIR"

# Install desired skills
if [[ -n "$DESIRED_SKILLS" ]]; then
  while IFS= read -r skill; do
    SRC="$SCRIPT_DIR/skills/$skill"
    DST="$SKILLS_DIR/$skill"
    if [[ -d "$SRC" ]]; then
      # Check if skill needs updating (compare timestamps)
      if [[ ! -d "$DST" ]] || [[ "$SRC/SKILL.md" -nt "$DST/SKILL.md" ]] 2>/dev/null; then
        log "    Installing skill: $skill"
        if [[ "$DRY_RUN" == "false" ]]; then
          cp -r "$SRC" "$DST"
          changed=1
        fi
      else
        vlog "    Skill '$skill' is current"
      fi
    else
      log "    Warning: Skill source not found: $SRC"
    fi
  done <<< "$DESIRED_SKILLS"
fi

# Remove skills not in manifest (optional — only managed skills)
for existing_skill in "$SKILLS_DIR"/*/; do
  skill_name=$(basename "$existing_skill")
  if [[ -n "$DESIRED_SKILLS" ]] && ! echo "$DESIRED_SKILLS" | grep -qx "$skill_name"; then
    # Only remove if the skill came from pesuclaw (has a .managed marker)
    if [[ -f "$existing_skill/.managed" ]]; then
      log "    Removing unmanaged skill: $skill_name"
      if [[ "$DRY_RUN" == "false" ]]; then
        rm -rf "$existing_skill"
        changed=1
      fi
    fi
  fi
done

# ── 8. Reconcile custom tools ────────────────────────────────────────
DESIRED_TOOLS=$(read_yaml "$MANIFEST" "tools")
mkdir -p "$BIN_DIR"
if [[ -n "$DESIRED_TOOLS" ]]; then
  while IFS= read -r tool; do
    SRC="$SCRIPT_DIR/tools/$tool"
    DST="$BIN_DIR/$tool"
    if [[ -f "$SRC" ]]; then
      if [[ ! -f "$DST" ]] || ! cmp -s "$SRC" "$DST"; then
        log "    Installing tool: $tool"
        if [[ "$DRY_RUN" == "false" ]]; then
          cp "$SRC" "$DST"
          chmod +x "$DST"
          changed=1
        fi
      else
        vlog "    Tool '$tool' is current"
      fi
    else
      log "    Warning: Tool source not found: $SRC"
    fi
  done <<< "$DESIRED_TOOLS"
fi

# ── 9. Reconcile config ($include approach) ──────────────────────────
# Config files from the repo are deployed as $include layers.
# OpenClaw's openclaw.json references them via $include and is NEVER overwritten
# after first boot — runtime changes (channels, models, agents) are preserved.
#
# On the VM:
#   /opt/pesuclaw/config/base.jsonc           ← platform security defaults (from repo)
#   /opt/pesuclaw/config/tenants/<id>.jsonc    ← tenant security overrides (from repo)
#   ~/.openclaw/openclaw.json                 ← runtime config (managed by OpenClaw)
#       $include: [base, tenant override]

INCLUDE_DIR="$OPENCLAW_HOME/config"
mkdir -p "$INCLUDE_DIR/tenants"

# Deploy base config (always update from repo)
BASE_SRC="$SCRIPT_DIR/config/base.jsonc"
BASE_DST="$INCLUDE_DIR/base.jsonc"
if [[ -f "$BASE_SRC" ]]; then
  if [[ ! -f "$BASE_DST" ]] || ! cmp -s "$BASE_SRC" "$BASE_DST"; then
    log "  Updating base config layer"
    if [[ "$DRY_RUN" == "false" ]]; then
      cp "$BASE_SRC" "$BASE_DST"
      changed=1
    fi
  else
    vlog "  Base config is current"
  fi
fi

# Deploy tenant override config (always update from repo)
if [[ -n "$CONFIG_OVERRIDE" && -f "$SCRIPT_DIR/config/$CONFIG_OVERRIDE" ]]; then
  TENANT_SRC="$SCRIPT_DIR/config/$CONFIG_OVERRIDE"
  TENANT_DST="$INCLUDE_DIR/$(basename "$CONFIG_OVERRIDE")"
  if [[ ! -f "$TENANT_DST" ]] || ! cmp -s "$TENANT_SRC" "$TENANT_DST"; then
    log "  Updating tenant config layer: $CONFIG_OVERRIDE"
    if [[ "$DRY_RUN" == "false" ]]; then
      cp "$TENANT_SRC" "$TENANT_DST"
      changed=1
    fi
  else
    vlog "  Tenant config layer is current"
  fi
fi

# Seed/repair openclaw.json
OC_CONFIG="$OPENCLAW_HOME/openclaw.json"
TENANT_CONFIG_BASENAME=""
if [[ -n "$CONFIG_OVERRIDE" ]]; then
  TENANT_CONFIG_BASENAME="$(basename "$CONFIG_OVERRIDE")"
fi

write_openclaw_config() {
  local out_file="$1"
  local include_lines="    \"./config/base.jsonc\""
  if [[ -n "$TENANT_CONFIG_BASENAME" ]]; then
    include_lines+=$'\n    ,"./config/'"$TENANT_CONFIG_BASENAME"'"'
  fi

  cat > "$out_file" <<SEED
{
  "\$include": [
$include_lines
  ],

  "gateway": {
    "mode": "local",
    "port": 8080,
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "\${OPENCLAW_GATEWAY_TOKEN}"
    }
  },

  "agents": {
    "defaults": {
      "model": { "primary": "google/gemini-2.5-flash" },
      "userTimezone": "America/Argentina/Buenos_Aires",
      "maxConcurrent": 2,
      "heartbeat": {
        "every": "30m",
        "target": "last",
        "lightContext": true,
        "activeHours": {
          "start": "09:00",
          "end": "22:00",
          "timezone": "America/Argentina/Buenos_Aires"
        }
      }
    },
    "list": [
      { "id": "main", "default": true }
    ]
  },

  "plugins": {
    "enabled": true,
    "slots": {
      "memory": "openclaw-mem0"
    }
  }
}
SEED
}

# ── Reconcile secrets from GCP Secret Manager ─────────────────────────
# Reads secrets: map from manifest (secret-name: ENV_VAR) and ensures
# each is present in /etc/openclaw/env. Only fetches missing ones.
SECRETS_BLOCK=$(awk '/^secrets:/{found=1; next} found && /^[^ ]/{exit} found && /^ /{print}' "$MANIFEST")
if [[ -n "$SECRETS_BLOCK" ]]; then
  while IFS=': ' read -r secret_name env_var; do
    # Skip empty lines and comments
    [[ -z "$secret_name" || "$secret_name" == \#* ]] && continue
    # Trim leading spaces from YAML indent
    secret_name=$(echo "$secret_name" | xargs)
    env_var=$(echo "$env_var" | xargs)
    if ! grep -q "^${env_var}=" /etc/openclaw/env 2>/dev/null; then
      SECRET_VAL=$(gcloud secrets versions access latest --secret="$secret_name" --project=sugato-489514 2>/dev/null || true)
      if [[ -n "$SECRET_VAL" ]]; then
        echo "${env_var}=${SECRET_VAL}" >> /etc/openclaw/env
        log "  Provisioned secret: $env_var"
        changed=1
      else
        log "  Warning: secret '$secret_name' not found in Secret Manager"
      fi
    fi
  done <<< "$SECRETS_BLOCK"
fi

# Generate a local gateway token if not present
if ! grep -q "^OPENCLAW_GATEWAY_TOKEN=" /etc/openclaw/env; then
  NEW_TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 || true)
  echo "OPENCLAW_GATEWAY_TOKEN=$NEW_TOKEN" >> /etc/openclaw/env
  log "  Generated local OPENCLAW_GATEWAY_TOKEN."
fi

if [[ ! -f "$OC_CONFIG" ]]; then
  log "  Seeding initial openclaw.json with \$include references"
  if [[ "$DRY_RUN" == "false" ]]; then
    write_openclaw_config "$OC_CONFIG"
    changed=1
  fi
else
  # Auto-repair known bad config signatures from older templates
  NEED_REPAIR=false
  if grep -q 'configWrites' "$OC_CONFIG" 2>/dev/null; then
    NEED_REPAIR=true
    log "  Detected deprecated key in openclaw.json (configWrites)"
  fi
  # shellcheck disable=SC2016
  if grep -Eq '"\$include"[[:space:]]*:[[:space:]]*"\./config/"' "$OC_CONFIG" 2>/dev/null || \
     grep -Eq '"\./config/"' "$OC_CONFIG" 2>/dev/null; then
    NEED_REPAIR=true
    log "  Detected invalid include target in openclaw.json (./config/)"
  fi

  if [[ "$NEED_REPAIR" == "true" && "$DRY_RUN" == "false" ]]; then
    backup="$OC_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    cp "$OC_CONFIG" "$backup"
    log "  Backed up invalid config to $(basename "$backup")"
    write_openclaw_config "$OC_CONFIG"
    changed=1
    log "  Rewrote openclaw.json to known-good template"
  fi
fi

# ── 10. Reconcile workspace templates (only on first deploy) ─────────
if [[ -n "$WORKSPACE_TEMPLATE" ]]; then
  TEMPLATE_DIR="$SCRIPT_DIR/workspace-templates/$WORKSPACE_TEMPLATE"
  if [[ ! -d "$TEMPLATE_DIR" ]]; then
    TEMPLATE_DIR="$SCRIPT_DIR/workspace-templates/standard"
  fi
  WORKSPACE="$OPENCLAW_HOME/workspace"
  mkdir -p "$WORKSPACE"

  for f in AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md; do
    if [[ -f "$TEMPLATE_DIR/$f" ]]; then
      if [[ ! -f "$WORKSPACE/$f" ]] || ! cmp -s "$TEMPLATE_DIR/$f" "$WORKSPACE/$f"; then
        log "  Updating workspace: $f"
        if [[ "$DRY_RUN" == "false" ]]; then
          cp "$TEMPLATE_DIR/$f" "$WORKSPACE/$f"
          changed=1
        fi
      else
        vlog "  Workspace '$f' is current"
      fi
    fi
  done
fi

# ── 11. Fix ownership ────────────────────────────────────────────────
if [[ "$DRY_RUN" == "false" ]]; then
  chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_HOME"
fi

# ── 12. Restart if needed ────────────────────────────────────────────
if [[ $changed -gt 0 ]]; then
  log "Changes detected — restarting OpenClaw gateway..."
  if [[ "$DRY_RUN" == "false" ]]; then
    systemctl restart openclaw 2>/dev/null || log "  Warning: systemctl restart failed (not running as service?)"
    sleep 2
    if systemctl is-active --quiet openclaw 2>/dev/null; then
      log "  ✓ Gateway restarted successfully"
    else
      log "  ✗ Gateway may not be running. Check: journalctl -u openclaw -n 20"
    fi
  fi
else
  vlog "No changes — gateway not restarted"
fi

log "Sync complete for tenant: $TENANT_ID"
