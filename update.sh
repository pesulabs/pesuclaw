#!/usr/bin/env bash
# PesuClaw Manual Update — convenience wrapper around sync.sh
# Use this for immediate reconciliation instead of waiting for the 5-min timer.
#
# Usage: ./update.sh [--verbose]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TENANT_ID=$(cat /etc/openclaw/tenant-id 2>/dev/null || echo "")
if [[ -z "$TENANT_ID" ]]; then
  echo "Error: /etc/openclaw/tenant-id not found. Run install.sh first."
  exit 1
fi

exec "$SCRIPT_DIR/sync.sh" --tenant "$TENANT_ID" --verbose "$@"
