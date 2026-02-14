#!/usr/bin/env bash
# =============================================================================
# list-mints.sh - List all deployed TollGate mints on the VPS
# =============================================================================
# Compatible with: Ubuntu 20.04+, Debian 11+
set -euo pipefail

for cmd in ansible; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is not installed."
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "============================================"
echo " Deployed TollGate Mints"
echo "============================================"

ansible tollgate-vps -m shell -a '
if [ -f /opt/tollgate/mints/registry.csv ]; then
    printf "%-14s %-45s %s\n" "SUBDOMAIN" "NPUB" "DEPLOYED"
    printf "%-14s %-45s %s\n" "---------" "----" "--------"
    while IFS=, read -r npub subdomain fqdn created; do
        short_npub="$(echo "$npub" | cut -c1-20)..."
        printf "%-14s %-45s %s\n" "$subdomain" "$short_npub" "$created"
    done < /opt/tollgate/mints/registry.csv
else
    echo "No mints deployed yet."
fi
' --become 2>/dev/null | tail -n +2
