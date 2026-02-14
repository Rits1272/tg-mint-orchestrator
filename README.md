# TollGate Cashu Mint Infrastructure

Ansible playbook for deploying per-operator [CDK](https://github.com/cashubtc/cdk) Cashu mints on a VPS for [TollGate](https://tollgate.me). Each TollGate operator gets their own mint tied to their Nostr npub, accessible at a unique subdomain.

## Architecture

```
                         *.mints.tollgate.me
                                │
                          ┌─────┴─────┐
                          │  Traefik  │  Wildcard TLS
                          │  :80/:443 │  Let's Encrypt
                          └─────┬─────┘
                  ┌─────────────┼─────────────┐
                  │             │             │
          ┌───────┴──┐  ┌──────┴───┐  ┌──────┴───┐
          │ mint-abc │  │ mint-def │  │ mint-ghi │
          │ cdk-mintd│  │ cdk-mintd│  │ cdk-mintd│
          │ :8085    │  │ :8085    │  │ :8085    │
          └──────────┘  └──────────┘  └──────────┘
           abc.mints.    def.mints.    ghi.mints.
           tollgate.me   tollgate.me   tollgate.me

          Each container has its own SQLite DB and
          is tied to an operator's npub.
```

## Prerequisites

- A VPS running **Ubuntu 20.04+** or **Debian 11+** (x86_64 or arm64) with root SSH access
- A domain with wildcard DNS configured:
  - `*.mints.tollgate.me` → `<VPS_IP>`
- DNS provider API credentials (for Let's Encrypt wildcard certs)
- Ansible 2.14+ on your local machine:
  ```bash
  pip install ansible
  ansible-galaxy collection install community.docker community.general
  ```

## Quick Start (Testing - No Domain Required)

The default config uses **sslip.io** for free wildcard DNS — no domain purchase or DNS config needed.

### 1. Configure

Edit `group_vars/all.yml` — just set your VPS IP:

```yaml
vps_ip: "203.0.113.10"      # Your VPS IP
tls_enabled: false           # Already the default
```

That's it. sslip.io automatically resolves `*.mints.203.0.113.10.sslip.io` → `203.0.113.10`.

### 2. Install Ansible (on your local machine)

```bash
pip install ansible
ansible-galaxy collection install community.docker community.general
```

### 3. Setup VPS (once)

```bash
ansible-playbook playbook.yml --tags setup -e vps_ip=203.0.113.10
```

This installs Docker, starts Traefik (HTTP only), and configures the firewall.

### 4. Deploy a mint

```bash
./scripts/deploy-mint.sh npub1a3b7c9d2e4f1g8h0j2k4l6m8n0p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2
```

### 5. Test it

```bash
# The mint URL will be printed at the end of the deploy. Example:
curl http://a3b7c9d2e4f1.mints.203.0.113.10.sslip.io/v1/info
```

You should get back JSON with the mint's info, keysets, and supported NUTs.

---

## Production Setup (With Domain + TLS)

When you're ready to go live with a real domain:

### 1. Configure

Edit `group_vars/all.yml`:

```yaml
vps_ip: "203.0.113.10"
tls_enabled: true                        # Enable HTTPS
mint_domain: "mints.tollgate.me"         # Your domain
acme_email: "admin@tollgate.me"          # Let's Encrypt email
acme_dns_provider: "cloudflare"          # Your DNS provider
acme_env_vars:
  CF_API_EMAIL: "you@example.com"
  CF_DNS_API_TOKEN: "your-token-here"
```

### 2. Set up wildcard DNS

Add one DNS record: `*.mints.tollgate.me` → `203.0.113.10`

### 3. Setup VPS (re-run to enable TLS)

```bash
ansible-playbook playbook.yml --tags setup -e vps_ip=203.0.113.10
```

### 4. Deploy mints

```bash
./scripts/deploy-mint.sh npub1a3b7c9d2e4f1g8h0j2k4l6m8n0p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2
```

Mint will be at `https://a3b7c9d2e4f1.mints.tollgate.me`.

## Commands

| Command | Description |
|---------|-------------|
| `./scripts/deploy-mint.sh <npub>` | Deploy a new mint for an operator |
| `./scripts/list-mints.sh` | List all deployed mints |
| `./scripts/remove-mint.sh <subdomain>` | Remove a mint and its data |

## How Subdomains Work

Each operator's npub is mapped to a short subdomain automatically:

```
npub1a3b7c9d2e4f1... → a3b7c9d2e4f1.mints.tollgate.me
      ^^^^^^^^^^^^^
      chars 6-17
```

TollGate clients can derive the mint URL from an operator's npub without any lookup — they just take the same 12-character slice.

You can also assign human-readable subdomains with the second argument to `deploy-mint.sh`.

## Configuration Reference

### Lightning Backend

Controlled by `cdk_mintd_ln_backend` in `group_vars/all.yml`:

| Value | Use Case |
|-------|----------|
| `fakewallet` | Testing / development. Quotes auto-fill, no real sats. |
| `ldk-node` | Production. Embedded LN node per mint. |
| `cln` | Production. Requires external Core Lightning. |
| `lnd` | Production. Requires external LND. |
| `lnbits` | Production. Requires LNbits instance. |

To switch a deployed mint to a real Lightning backend, update the env vars in its `docker-compose.yml` at `/opt/tollgate/mints/<subdomain>/docker-compose.yml` and restart with `docker compose up -d`.

### File Layout on VPS

```
/opt/tollgate/
├── traefik/
│   ├── traefik.yml           # Traefik static config
│   ├── docker-compose.yml    # Traefik container
│   └── acme/
│       └── acme.json         # TLS certificates
└── mints/
    ├── registry.csv          # All deployed mints
    ├── a3b7c9d2e4f1/         # Per-mint directory
    │   ├── docker-compose.yml
    │   ├── operator.env      # npub, subdomain, created
    │   └── cdk-mintd.db      # SQLite database (auto-created)
    └── f8e7d6c5b4a3/
        └── ...
```

## Moving to Production

When ready to move beyond fakewallet:

1. **LDK-node** is the simplest path — it's an embedded Lightning node that doesn't need external infrastructure. Set `cdk_mintd_ln_backend: "ldk-node"` and add LDK-specific env vars (network, esplora URL, etc.) to the mint docker-compose template.

2. **Shared Lightning node** — run one CLN/LND instance on the VPS and point all mints at it. More resource-efficient but less isolated.

3. **Kubernetes** — when you're running 50+ mints, consider migrating from Docker Compose to K8s. The container images and env vars stay the same; you'd just replace the docker-compose templates with Helm charts or K8s manifests.

## Troubleshooting

**Playbook fails on OS check:**
- Only Ubuntu 20.04+ and Debian 11+ are supported
- The playbook auto-detects the distro and uses the correct Docker repo (docker.com/linux/ubuntu vs docker.com/linux/debian)

**Firewall:**
- On Ubuntu, the playbook uses UFW (the standard Ubuntu firewall)
- On Debian, it falls back to raw iptables with `iptables-persistent` to save rules across reboots

**Mint not reachable after deploy:**
- Check wildcard DNS: `dig a3b7c9d2e4f1.mints.tollgate.me` should return your VPS IP
- Check Traefik logs: `docker logs traefik`
- Check mint logs: `docker logs mint-a3b7c9d2e4f1`

**TLS certificate errors:**
- Traefik needs time to issue the wildcard cert on first run
- Verify your DNS provider API credentials in `group_vars/all.yml`
- Check ACME state: `cat /opt/tollgate/traefik/acme/acme.json | python3 -m json.tool`

**Mint container won't start:**
- Check if port conflicts exist: `docker ps`
- Inspect: `docker inspect mint-<subdomain>`
