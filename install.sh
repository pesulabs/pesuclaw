#!/usr/bin/env bash
# PesuClaw Installer — first-boot provisioning
#
# Usage:
#   ./install.sh --tenant <tenant-id>
#
# This script handles one-time setup ONLY:
#   1. Install Node.js 22 LTS
#   2. Create openclaw user
#   3. Create directories and systemd units
#   4. Store tenant ID for sync.sh
#   5. Run sync.sh for initial reconciliation
#
# After install, sync.sh runs every 5 minutes via systemd timer
# to keep the VM in sync with the manifest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="/home/openclaw/.openclaw"
OPENCLAW_USER="openclaw"
TENANT_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant) TENANT_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$TENANT_ID" ]]; then
  echo "Error: --tenant is required"
  echo "Usage: ./install.sh --tenant <tenant-id>"
  exit 1
fi

# Check manifest exists
if [[ ! -f "$SCRIPT_DIR/manifests/${TENANT_ID}.yaml" ]]; then
  echo "Error: No manifest found at manifests/${TENANT_ID}.yaml"
  exit 1
fi

echo "═══════════════════════════════════════════════════"
echo "  PesuClaw Installer"
echo "  Tenant: $TENANT_ID"
echo "═══════════════════════════════════════════════════"

# ── 1. System dependencies ───────────────────────────────────────────
echo ">>> Installing base dependencies..."
apt-get update -qq
apt-get install -y -qq curl git jq

# ── 2. Tailscale VPN ──────────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  echo ">>> Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo ">>> Tailscale $(tailscale version | head -1) already installed"
fi

# ── 3. Cloud SQL Auth Proxy ─────────────────────────────────────────
if ! command -v cloud-sql-proxy &>/dev/null; then
  echo ">>> Installing Cloud SQL Auth Proxy..."
  curl -sSfL -o /usr/local/bin/cloud-sql-proxy \
    https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.3/cloud-sql-proxy.linux.amd64
  chmod +x /usr/local/bin/cloud-sql-proxy
else
  echo ">>> Cloud SQL Auth Proxy already installed"
fi

# ── 3. Node.js 22 LTS ───────────────────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]]; then
  echo ">>> Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
else
  echo ">>> Node.js $(node -v) already installed"
fi

# ── 4. Create openclaw user ──────────────────────────────────────────
if ! id "$OPENCLAW_USER" &>/dev/null; then
  echo ">>> Creating user: $OPENCLAW_USER"
  useradd --system --create-home --shell /bin/bash "$OPENCLAW_USER"
fi

# ── 5. Create directories ───────────────────────────────────────────
echo ">>> Creating directories..."
mkdir -p "$OPENCLAW_HOME"/{workspace,skills,agents}
mkdir -p /opt/pesuclaw/bin
mkdir -p /etc/openclaw
chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_HOME"

# ── 6. Store tenant ID ──────────────────────────────────────────────
echo "$TENANT_ID" > /etc/openclaw/tenant-id

# ── 7. Create secrets env file ──────────────────────────────────────
if [[ ! -f /etc/openclaw/env ]]; then
  {
    echo "# Secrets — populate from GCP Secret Manager"
    echo "# GEMINI_API_KEY="
    echo "# OPENAI_API_KEY="
    echo "# TELEGRAM_BOT_TOKEN="
  } > /etc/openclaw/env
  chmod 600 /etc/openclaw/env
fi

# ── 8. Install systemd units ────────────────────────────────────────
echo ">>> Installing systemd units..."

# Gateway service
cat > /etc/systemd/system/openclaw.service <<EOF
[Unit]
Description=OpenClaw Gateway (${TENANT_ID})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${OPENCLAW_USER}
WorkingDirectory=${OPENCLAW_HOME}/workspace
Environment=OPENCLAW_HOME=/home/openclaw
Environment=TENANT_ID=${TENANT_ID}
Environment=PATH=/opt/pesuclaw/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=-/etc/openclaw/env
ExecStart=/usr/bin/openclaw gateway
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/home/openclaw /tmp
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

# Sync timer (GitOps reconciler — every 5 minutes)
cat > /etc/systemd/system/pesuclaw-sync.service <<EOF
[Unit]
Description=PesuClaw GitOps Sync (${TENANT_ID})

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/sync.sh --tenant ${TENANT_ID}
User=root
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/pesuclaw-sync.timer <<EOF
[Unit]
Description=PesuClaw GitOps Sync Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Backup timer (daily at 3am)
cat > /etc/systemd/system/openclaw-backup.service <<EOF
[Unit]
Description=OpenClaw Daily Backup (${TENANT_ID})

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/backup.sh --tenant ${TENANT_ID}
User=root
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/openclaw-backup.timer <<EOF
[Unit]
Description=OpenClaw Daily Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=900

[Install]
WantedBy=timers.target
EOF

# Update timer (OpenClaw runtime update daily at 4am)
cat > /etc/systemd/system/pesuclaw-update.service <<EOF
[Unit]
Description=PesuClaw OpenClaw Runtime Update (${TENANT_ID})

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/sync.sh --tenant ${TENANT_ID}
User=root
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/pesuclaw-update.timer <<EOF
[Unit]
Description=PesuClaw Daily OpenClaw Update Timer

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF

# Cloud SQL Auth Proxy (provides local 127.0.0.1:5432 → Cloud SQL)
cat > /etc/systemd/system/cloud-sql-proxy.service <<EOF
[Unit]
Description=Cloud SQL Auth Proxy (${TENANT_ID})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloud-sql-proxy \
  --auto-iam-authn \
  --private-ip \
  sugato-489514:us-central1:oc-shared-db
Restart=always
RestartSec=5
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

# ── 9. Enable timers and services ──────────────────────────────────
systemctl daemon-reload
systemctl enable --now cloud-sql-proxy
systemctl enable openclaw.service
systemctl enable pesuclaw-sync.timer
systemctl start pesuclaw-sync.timer
systemctl enable pesuclaw-update.timer
systemctl start pesuclaw-update.timer
systemctl enable openclaw-backup.timer
systemctl start openclaw-backup.timer

# ── 10. Join Tailscale network ─────────────────────────────────────
echo ">>> Joining Tailscale network..."
if tailscale status &>/dev/null 2>&1; then
  echo "  Already connected to Tailnet"
else
  TS_AUTHKEY=$(gcloud secrets versions access latest \
    --secret="${TENANT_ID}-tailscale-authkey" \
    --project=sugato-489514 2>/dev/null || true)
  if [[ -n "$TS_AUTHKEY" ]]; then
    tailscale up --authkey="$TS_AUTHKEY" --hostname="vm-${TENANT_ID}" --accept-routes
    echo "  Joined Tailnet as vm-${TENANT_ID}"
    # Expose OpenClaw gateway over HTTPS via Tailscale Serve
    tailscale serve --bg http://localhost:8080
    echo "  HTTPS dashboard: https://vm-${TENANT_ID}.chimp-ulmer.ts.net/"
  else
    echo "  Warning: No Tailscale auth key found in Secret Manager"
    echo "  Create secret '${TENANT_ID}-tailscale-authkey' and run: tailscale up --authkey=<key> --hostname=vm-${TENANT_ID}"
  fi
fi

# ── 11. Install mem0 plugin ─────────────────────────────────────────
echo ">>> Installing mem0 memory plugin..."
su - "$OPENCLAW_USER" -c "openclaw plugins install @mem0/openclaw-mem0" 2>/dev/null || {
  echo "  Warning: mem0 plugin install failed (openclaw may not be installed yet)"
  echo "  sync.sh will retry on first run"
}

# ── 11. Run initial sync ────────────────────────────────────────────
echo ""
echo ">>> Running initial sync..."
"$SCRIPT_DIR/sync.sh" --tenant "$TENANT_ID" --verbose

# ── 12. Done ─────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Installation complete!"
echo ""
echo "  Manifest:  manifests/${TENANT_ID}.yaml"
echo "  Sync:      Every 5 min via pesuclaw-sync.timer"
echo "  Updates:   Daily at 4am via pesuclaw-update.timer"
echo "  Backup:    Daily at 3am via openclaw-backup.timer"
echo ""
echo "  Next steps:"
echo "  1. Add secrets to /etc/openclaw/env"
echo "  2. Start: systemctl start openclaw"
echo "  3. Logs:  journalctl -u openclaw -f"
echo ""
echo "  GitOps: push changes to manifests/${TENANT_ID}.yaml"
echo "  → sync.sh picks them up within 5 minutes"
echo "═══════════════════════════════════════════════════"
