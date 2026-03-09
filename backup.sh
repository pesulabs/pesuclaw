#!/usr/bin/env bash
# PesuClaw Daily Backup
# Backs up OpenClaw state to GCS.
#
# Usage: ./backup.sh --tenant <tenant-id>
# Runs daily via systemd timer (openclaw-backup.timer)
#
# What gets backed up:
#   - openclaw.json (config)
#   - workspace/ (AGENTS.md, SOUL.md, etc.)
#   - credentials/ (channel auth state)
#   - agents/*/sessions/ (conversation history)
#   - agents/*/agent/auth-profiles.json (model auth)
#
# Retention: 30 days (GCS lifecycle policy on bucket)

set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/openclaw/.openclaw}"
GCS_BUCKET="sugato-489514-backups"
TENANT_ID=""
DATE=$(date +%Y-%m-%d-%H%M)

while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant) TENANT_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$TENANT_ID" ]]; then
  echo "Error: --tenant is required"
  exit 1
fi

BACKUP_DIR="/tmp/openclaw-backup-${TENANT_ID}-${DATE}"
GCS_PATH="gs://${GCS_BUCKET}/openclaw/${TENANT_ID}/${DATE}"

echo "[$(date)] Starting backup for tenant: $TENANT_ID"

# Create temp backup directory
mkdir -p "$BACKUP_DIR"

# Copy state files (exclude large caches, logs, sandbox containers)
rsync -a --relative \
  --include="openclaw.json" \
  --include="workspace/***" \
  --include="credentials/***" \
  --include="agents/***" \
  --include="skills/***" \
  --exclude="*.log" \
  --exclude="*.tmp" \
  --exclude=".terragrunt-cache" \
  "$OPENCLAW_HOME/" "$BACKUP_DIR/"

# Create tarball
TARBALL="/tmp/openclaw-${TENANT_ID}-${DATE}.tar.gz"
tar -czf "$TARBALL" -C "$BACKUP_DIR" .

# Upload to GCS
gsutil -q cp "$TARBALL" "${GCS_PATH}.tar.gz"

# Cleanup
rm -rf "$BACKUP_DIR" "$TARBALL"

SIZE=$(gsutil du -s "${GCS_PATH}.tar.gz" 2>/dev/null | awk '{print $1}')
echo "[$(date)] Backup complete: ${GCS_PATH}.tar.gz (${SIZE} bytes)"
