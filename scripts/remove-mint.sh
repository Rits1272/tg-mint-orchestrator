#!/usr/bin/env bash
# =============================================================================
# remove-mint.sh - Remove a TollGate mint
# =============================================================================
# Compatible with: Ubuntu 20.04+, Debian 11+
#
# Usage:
#   ./scripts/remove-mint.sh <subdomain>
#
# Example:
#   ./scripts/remove-mint.sh a3b7c9d2e4f1
#
set -euo pipefail

for cmd in ansible; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is not installed."
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <subdomain>"
    echo ""
    echo "  Use list-mints.sh to see deployed mints and their subdomains."
    exit 1
fi

SUBDOMAIN="$1"
CONTAINER="mint-${SUBDOMAIN}"
DATA_DIR="/opt/tollgate/mints/${SUBDOMAIN}"

echo "============================================"
echo " Removing TollGate Mint"
echo "============================================"
echo " Subdomain : $SUBDOMAIN"
echo " Container : $CONTAINER"
echo " Data dir  : $DATA_DIR"
echo "============================================"
echo ""
printf "Are you sure? This will stop the mint and remove its data. [y/N] "
read -r confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

cd "$PROJECT_DIR"

ansible tollgate-vps -m shell -a "
    cd ${DATA_DIR} && docker compose down --volumes 2>/dev/null || true
    docker rm -f ${CONTAINER} 2>/dev/null || true
    rm -rf ${DATA_DIR}
    sed -i '/${SUBDOMAIN}/d' /opt/tollgate/mints/registry.csv 2>/dev/null || true
    echo 'Mint ${SUBDOMAIN} removed.'
" --become

echo ""
echo "Done. Mint $SUBDOMAIN has been removed."
