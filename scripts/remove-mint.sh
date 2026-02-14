#!/usr/bin/env bash
# =============================================================================
# remove-mint.sh - Remove a TollGate mint
# =============================================================================
#
# Usage:
#   ./scripts/remove-mint.sh <vps-ip> <subdomain>
#   ./scripts/remove-mint.sh -p <ssh-password> <vps-ip> <subdomain>
#
# SSH auth (pick one):
#   -p <password>          Pass SSH password directly
#   TG_SSH_PASS=<password> Set via environment variable
#   (neither)              Prompts interactively
#
# Example:
#   ./scripts/remove-mint.sh 203.0.113.10 a3b7c9d2e4f1
#
set -euo pipefail

if ! command -v ansible >/dev/null 2>&1; then
    echo "Error: 'ansible' is not installed."
    echo "Install with: pip install ansible"
    exit 1
fi

# --- Parse SSH password flag ---
SSH_PASS="${TG_SSH_PASS:-}"
if [ "${1:-}" = "-p" ]; then
    SSH_PASS="${2:?Error: -p requires a password argument}"
    shift 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 2 ]; then
    echo "Usage: $0 [-p <ssh-password>] <vps-ip> <subdomain>"
    echo ""
    echo "  Use list-mints.sh to see deployed mints and their subdomains."
    exit 1
fi

VPS_IP="$1"
SUBDOMAIN="$2"
CONTAINER="mint-${SUBDOMAIN}"
DATA_DIR="/opt/tollgate/mints/${SUBDOMAIN}"

echo "============================================"
echo " Removing TollGate Mint"
echo "============================================"
echo " VPS       : $VPS_IP"
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

# SSH auth
EXTRA_VARS="-e vps_ip=${VPS_IP}"
SSH_ARGS=""
if [ -n "$SSH_PASS" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "Error: 'sshpass' is required for password-based SSH."
        echo "Install with: brew install hudochenkov/sshpass/sshpass (macOS)"
        echo "              apt install sshpass (Ubuntu/Debian)"
        exit 1
    fi
    EXTRA_VARS="$EXTRA_VARS -e ansible_ssh_pass=$SSH_PASS"
else
    SSH_ARGS="--ask-pass"
fi

cd "$PROJECT_DIR"

ansible tollgate-vps $EXTRA_VARS $SSH_ARGS -m shell -a "
    cd ${DATA_DIR} && docker compose down --volumes 2>/dev/null || true
    docker rm -f ${CONTAINER} 2>/dev/null || true
    rm -rf ${DATA_DIR}
    sed -i '/${SUBDOMAIN}/d' /opt/tollgate/mints/registry.csv 2>/dev/null || true
    echo 'Mint ${SUBDOMAIN} removed.'
" --become

echo ""
echo "Done. Mint $SUBDOMAIN has been removed."
