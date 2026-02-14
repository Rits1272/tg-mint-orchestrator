#!/usr/bin/env bash
# =============================================================================
# deploy-mint.sh - Deploy a TollGate Cashu mint for an operator
# =============================================================================
# Compatible with: Ubuntu 20.04+, Debian 11+
#
# Usage:
#   ./scripts/deploy-mint.sh <npub>
#   ./scripts/deploy-mint.sh <npub> [custom-subdomain]
#
# Examples:
#   ./scripts/deploy-mint.sh npub1a3b7c9d2e4f1g8h0j2k4l6m8n0p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2
#   ./scripts/deploy-mint.sh npub1a3b7c9d2e4f1g8h0j2k4l6m8n0p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2 alice
#
set -euo pipefail

# --- Verify dependencies ---
for cmd in ansible-playbook; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is not installed."
        echo "Install with: pip install ansible"
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <npub> [custom-subdomain]"
    echo ""
    echo "  npub              Nostr public key of the TollGate operator"
    echo "  custom-subdomain  Optional: custom subdomain prefix (default: derived from npub)"
    exit 1
fi

NPUB="$1"

# Validate npub format (npub1 + 58 bech32 chars)
if ! echo "$NPUB" | grep -qE '^npub1[a-z0-9]{58}$'; then
    echo "Error: Invalid npub format."
    echo "Expected: npub1 followed by 58 lowercase alphanumeric characters"
    echo "Got:      $NPUB"
    exit 1
fi

# Derive subdomain preview
SUBDOMAIN="${2:-$(echo "$NPUB" | cut -c6-17)}"

echo "============================================"
echo " TollGate Mint Deployment"
echo "============================================"
echo " Operator : $NPUB"
echo " Subdomain: $SUBDOMAIN"
echo "============================================"
echo ""

EXTRA_VARS="-e npub=$NPUB"
if [ $# -ge 2 ]; then
    EXTRA_VARS="$EXTRA_VARS -e mint_subdomain=$2"
fi

cd "$PROJECT_DIR"
ansible-playbook playbook.yml --tags mint $EXTRA_VARS
