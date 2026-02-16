# TollGate Cashu Mint Orchestrator

Ansible playbook for deploying per-operator [CDK](https://github.com/cashubtc/cdk) Cashu mints on a VPS for [TollGate](https://tollgate.me). Each TollGate operator gets their own mint tied to their Nostr npub, accessible at a unique subdomain.

## Architecture

```
                         *.mints.tollgate.me
                                │
                          ┌─────┴─────┐
                          │  Traefik  │  Wildcard TLS
                          │  :80/:443 │  Let's Encrypt
                          └─────┬─────┘
          ┌─────────┬──────────┼──────────────┐
          │         │          │              │
   ┌──────┴───┐ ┌──┴───┐ ┌───┴────┐  ┌──────┴───┐
   │ keycloak │ │ pg   │ │mint-abc│  │ mint-def │
   │ OIDC     │ │ auth │ │cdk-mintd  │ cdk-mintd│
   │ (opt.)   │ │(opt.)│ │ :8085  │  │ :8085    │
   └──────────┘ └──────┘ └────────┘  └──────────┘
    auth.mints.  (int.)   abc.mints.   def.mints.

          Keycloak + PostgreSQL are deployed when
          auth_enabled: true (NUT-21/22 blind auth).
          Each mint has its own SQLite DB and is
          tied to an operator's npub.
```

## Prerequisites

**On your local machine:**

- Python 3.8+
- Ansible 2.14+
- `sshpass` (only if using password-based SSH)

**Target VPS:**

- Ubuntu 20.04+ or Debian 11+ (x86_64 or arm64)
- Root SSH access (key-based or password)
- Ports 22, 80, and 443 open at the hosting provider level
- Minimum 1GB RAM (2GB+ recommended if `auth_enabled: true`)

**For production (optional):**

- A domain with wildcard DNS (e.g., `*.mints.tollgate.me` → VPS IP)
- DNS provider API credentials for Let's Encrypt wildcard TLS certificates

## Install Dependencies

```bash
# Install Ansible
pip install ansible

# Install required Ansible collections
ansible-galaxy collection install community.docker community.general

# macOS only: install sshpass if using password-based SSH
brew install hudochenkov/sshpass/sshpass
```

## Quick Start (Test Mode — No Domain Required)

The default config uses [sslip.io](https://sslip.io) for free wildcard DNS — no domain purchase or DNS setup needed. Mints are served over HTTP.

### 1. Configure your VPS IP

Edit `group_vars/all.yml`:

```yaml
vps_ip: "<YOUR_VPS_IP>"
tls_enabled: false           # Already the default
```

### 2. Setup the VPS (run once)

```bash
./scripts/setup-vps.sh <YOUR_VPS_IP>
```

This installs Docker, starts Traefik, and configures the firewall. You'll be prompted for the SSH password.

To pass the password non-interactively:

```bash
./scripts/setup-vps.sh -p <SSH_PASSWORD> <YOUR_VPS_IP>
# or
TG_SSH_PASS=<SSH_PASSWORD> ./scripts/setup-vps.sh <YOUR_VPS_IP>
```

### 3. Deploy a mint

```bash
./scripts/deploy-mint.sh <YOUR_VPS_IP> <OPERATOR_NPUB>
```

### 4. Test it

```bash
# The mint URL is printed at the end of the deploy output. Example:
curl http://<SUBDOMAIN>.mints.<YOUR_VPS_IP>.sslip.io/v1/info
```

You should get back JSON with the mint's info, keysets, and supported NUTs.

---

## Production Setup (Domain + HTTPS)

### 1. Configure

Edit `group_vars/all.yml`:

```yaml
vps_ip: "<YOUR_VPS_IP>"
tls_enabled: true
mint_domain: "<YOUR_DOMAIN>"              # e.g. "mints.tollgate.me"
acme_email: "<YOUR_EMAIL>"
acme_dns_provider: "<DNS_PROVIDER>"       # e.g. "cloudflare"
acme_env_vars:
  CF_API_EMAIL: "<CLOUDFLARE_EMAIL>"
  CF_DNS_API_TOKEN: "<CLOUDFLARE_TOKEN>"
```

See [Traefik ACME providers](https://doc.traefik.io/traefik/https/acme/#providers) for the full list of supported DNS providers and their required environment variables.

### 2. Set up wildcard DNS

Add a DNS record at your registrar:

```
*.<YOUR_DOMAIN>  →  <YOUR_VPS_IP>  (A record)
```

### 3. Setup VPS

```bash
./scripts/setup-vps.sh <YOUR_VPS_IP>
```

### 4. Deploy mints

```bash
./scripts/deploy-mint.sh <YOUR_VPS_IP> <OPERATOR_NPUB>
```

The mint will be at `https://<SUBDOMAIN>.<YOUR_DOMAIN>`.

---

## Authenticated Minting (NUT-21/22)

By default, mints are open — anyone can mint tokens. To restrict minting to only the operator (the npub owner), enable blind authentication ([NUT-21](https://cashubtc.github.io/nuts/21/)/[NUT-22](https://cashubtc.github.io/nuts/22/)).

### How it works

The operator pre-mints ecash tokens from their mint, then distributes them to users (e.g., WiFi customers). Users can freely swap and redeem tokens without authentication — only the initial minting is restricted.

When enabled:
- A **Keycloak** OIDC server and **PostgreSQL** database are deployed during VPS setup
- Each mint deployment creates a Keycloak user (username = operator's npub) with a random password
- CDK is configured to require blind auth for `mint` and `get_mint_quote` endpoints
- All other endpoints (`swap`, `melt`, `restore`, etc.) remain open
- Auth credentials are printed at the end of deployment and saved to `operator.env`

### Protected vs Open Endpoints

| Endpoint | Auth | Description |
|----------|------|-------------|
| `get_mint_quote` | Blind auth | Only operator can request mint quotes |
| `mint` | Blind auth | Only operator can mint new tokens |
| `swap` | Open | Anyone with tokens can swap |
| `melt` | Open | Anyone with tokens can redeem to Lightning |
| `get_melt_quote` | Open | Anyone can request melt quotes |
| `restore` | Open | Wallet recovery remains accessible |

### Enable Authentication

Edit `group_vars/all.yml`:

```yaml
auth_enabled: true

# Change these in production!
keycloak_admin_password: "<KEYCLOAK_ADMIN_PASSWORD>"
auth_postgres_password: "<POSTGRES_PASSWORD>"
```

> **Note:** In production mode (`tls_enabled: true`), the playbook will refuse to run if passwords are still set to `changeme-in-production`. For test mode, default passwords are allowed.

Then run (or re-run) setup:

```bash
./scripts/setup-vps.sh <YOUR_VPS_IP>
```

Deploy mints as usual — auth credentials will be shown in the output:

```bash
./scripts/deploy-mint.sh <YOUR_VPS_IP> <OPERATOR_NPUB>
```

The operator uses these credentials in their Cashu wallet to authenticate before minting.

### Keycloak Modes

| Mode | Keycloak | When |
|------|----------|------|
| Test (`tls_enabled: false`) | `start-dev` | Development, HTTP, relaxed hostname checks |
| Production (`tls_enabled: true`) | `start` (optimized) | HTTPS, strict hostname, caching enabled |

### Auth Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `auth_enabled` | `false` | Enable NUT-21/22 blind authentication |
| `keycloak_image` | `quay.io/keycloak/keycloak:26.0` | Keycloak Docker image |
| `keycloak_admin_user` | `admin` | Keycloak admin username |
| `keycloak_admin_password` | `changeme-in-production` | Keycloak admin password |
| `auth_postgres_image` | `postgres:16-alpine` | PostgreSQL Docker image |
| `auth_postgres_user` | `tollgate` | PostgreSQL username |
| `auth_postgres_password` | `changeme-in-production` | PostgreSQL password |
| `auth_data_dir` | `/opt/tollgate/auth` | Auth services data directory |
| `cdk_auth_max_bat` | `50` | Max blind auth tokens per wallet |

---

## SSH Authentication

All scripts support three methods for SSH auth:

| Method | Example |
|--------|---------|
| Interactive prompt | `./scripts/deploy-mint.sh <VPS_IP> <NPUB>` |
| `-p` flag | `./scripts/deploy-mint.sh -p <PASSWORD> <VPS_IP> <NPUB>` |
| Environment variable | `TG_SSH_PASS=<PASSWORD> ./scripts/deploy-mint.sh <VPS_IP> <NPUB>` |

For production, SSH key-based auth is recommended. Uncomment and configure `ansible_ssh_private_key_file` in `inventory/hosts.yml`:

```yaml
all:
  hosts:
    tollgate-vps:
      ansible_host: "{{ vps_ip }}"
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/tollgate
```

Generate a key if needed:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/tollgate
ssh-copy-id -i ~/.ssh/tollgate root@<YOUR_VPS_IP>
```

## Commands

| Command | Description |
|---------|-------------|
| `./scripts/setup-vps.sh <vps-ip>` | Provision VPS with Docker, Traefik, firewall, and auth (run once) |
| `./scripts/deploy-mint.sh <vps-ip> <npub>` | Deploy a new mint for an operator |
| `./scripts/list-mints.sh <vps-ip>` | List all deployed mints |
| `./scripts/remove-mint.sh <vps-ip> <subdomain>` | Remove a mint and clean up auth resources |
| `./scripts/teardown.sh <vps-ip>` | Reset VPS — removes all mints, auth, Traefik, and data |

## How Subdomains Work

Each operator's npub is mapped to a short subdomain automatically:

```
npub1a3b7c9d2e4f1... → a3b7c9d2e4f1.mints.tollgate.me
      ^^^^^^^^^^^^^
      chars 6-17
```

TollGate clients can derive the mint URL from an operator's npub without any lookup — they just take the same 12-character slice.

You can also assign a custom subdomain:

```bash
./scripts/deploy-mint.sh <YOUR_VPS_IP> <OPERATOR_NPUB> my-custom-name
```

## Configuration Reference

All configuration lives in `group_vars/all.yml`.

| Variable | Default | Description |
|----------|---------|-------------|
| `vps_ip` | — | VPS IP address (required) |
| `tls_enabled` | `false` | `false` = HTTP + sslip.io, `true` = HTTPS + custom domain |
| `mint_domain` | `mints.tollgate.me` | Base domain (production only) |
| `acme_email` | `admin@tollgate.me` | Let's Encrypt contact email |
| `acme_dns_provider` | `cloudflare` | DNS provider for ACME challenge |
| `acme_env_vars` | — | Provider-specific API credentials |
| `traefik_version` | `v3.6` | Traefik Docker image tag |
| `cdk_mintd_image` | `cashubtc/mintd:0.14.3` | CDK mint Docker image |
| `cdk_mintd_ln_backend` | `fakewallet` | Lightning backend (see below) |
| `cdk_mintd_database` | `sqlite` | Database engine for mint data |
| `docker_network_name` | `tollgate-net` | Shared Docker network name |

### Lightning Backend

Controlled by `cdk_mintd_ln_backend`:

| Value | Use Case |
|-------|----------|
| `fakewallet` | Testing / development. Quotes auto-fill, no real sats. |
| `ldk-node` | Production. Embedded LN node per mint. |
| `cln` | Production. Requires external Core Lightning node. |
| `lnd` | Production. Requires external LND node. |
| `lnbits` | Production. Requires external LNbits instance. |

To switch a deployed mint's backend, edit its `docker-compose.yml` at `/opt/tollgate/mints/<subdomain>/docker-compose.yml` on the VPS and restart:

```bash
cd /opt/tollgate/mints/<subdomain> && docker compose up -d
```

## VPS File Layout

```
/opt/tollgate/
├── traefik/
│   ├── traefik.yml           # Traefik static config
│   ├── docker-compose.yml    # Traefik container
│   └── acme/
│       └── acme.json         # TLS certificates
├── auth/                     # Only when auth_enabled: true
│   ├── docker-compose.yml    # Keycloak + PostgreSQL
│   ├── admin.env             # Auth admin credentials (mode 0600)
│   ├── realm-import/
│   │   └── realm-tollgate.json  # OIDC realm config
│   └── postgres-data/        # PostgreSQL data
└── mints/
    ├── registry.csv          # All deployed mints
    ├── a3b7c9d2e4f1/         # Per-mint directory
    │   ├── docker-compose.yml
    │   ├── operator.env      # npub, mnemonic, auth credentials (mode 0600)
    │   └── cdk-mintd.db      # SQLite database (auto-created)
    └── f8e7d6c5b4a3/
        └── ...
```

## Troubleshooting

**"sshpass is required" error:**

Install sshpass for password-based SSH:
```bash
# macOS
brew install hudochenkov/sshpass/sshpass
# Ubuntu/Debian
apt install sshpass
```

**Mint health check fails:**

SSH into the VPS and check container logs:
```bash
docker logs mint-<subdomain>
```

**Keycloak not starting (auth_enabled: true):**

Check Keycloak logs:
```bash
docker logs keycloak
```

Common issues:
- PostgreSQL not ready yet — Keycloak depends on a healthy postgres container, give it a minute
- Port 8080 conflict — Keycloak binds to `127.0.0.1:8080`, check nothing else uses it

**Port 80 already in use:**

The Traefik role automatically stops non-Traefik containers using port 80 during setup. If the issue persists, check for system services:
```bash
ss -tlnp | grep :80
```

**TLS certificate not provisioning:**

Verify your DNS provider credentials in `group_vars/all.yml` and ensure the wildcard DNS record is correctly configured:
```bash
dig +short '*.<YOUR_DOMAIN>'
```

**"Default passwords detected" error:**

In production mode (`tls_enabled: true`), the playbook rejects the default `changeme-in-production` passwords. Set real passwords:
```bash
ansible-playbook playbook.yml --tags setup \
  -e keycloak_admin_password="<REAL_PASSWORD>" \
  -e auth_postgres_password="<REAL_PASSWORD>"
```

**Auth cleanup on mint removal:**

When removing a mint (`remove-mint.sh`), the script automatically:
1. Deletes the Keycloak user for the operator
2. Drops the per-mint auth PostgreSQL database
3. Removes the mint container and data

If auth services aren't running, auth cleanup is silently skipped.
