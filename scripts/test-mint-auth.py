#!/usr/bin/env python3

import subprocess
import json
import os
import yaml
from nostr_sdk import Keys, PublicKey, Kind, EventBuilder, Tag, Filter, Client, Timestamp

# --- Configuration ---
# --- Configuration ---
# Read VPS_IP and MINT_DOMAIN from group_vars/all.yml
try:
    with open("group_vars/all.yml", 'r') as f:
        group_vars = yaml.safe_load(f)
    VPS_IP = group_vars['vps_ip']
    MINT_DOMAIN = group_vars['mint_domain']
except FileNotFoundError:
    print("Error: group_vars/all.yml not found.")
    exit(1)
except KeyError as e:
    print(f"Error: Missing key in group_vars/all.yml: {e}")
    exit(1)

MINT_AMOUNT = 21 # satoshis

# --- Generate Nostr Key Pair ---
print("Generating new Nostr key pair...")
keys = Keys.generate()
private_key = keys.secret_key().to_hex()
public_key = keys.public_key()
npub = public_key.to_bech32()

print(f"Generated Private Key: {private_key}")
print(f"Generated Public Key: {public_key.to_hex()}")
print(f"Generated npub: {npub}")

# --- Deploy Mint ---
print(f"Deploying mint for npub: {npub}...")
deploy_command = ["./scripts/deploy-mint.sh", VPS_IP, npub]

try:
    deploy_result = subprocess.run(deploy_command, check=True, capture_output=True, text=True)
    print("Mint deployment output:")
    print(deploy_result.stdout)
    if deploy_result.stderr:
        print("Mint deployment errors:")
        print(deploy_result.stderr)
except subprocess.CalledProcessError as e:
    print(f"Error deploying mint: {e}")
    print(f"Stdout: {e.stdout}")
    print(f"Stderr: {e.stderr}")
    exit(1)

# --- Construct Mint URL ---
mint_subdomain = npub[5:17]
mint_url = f"https://{mint_subdomain}.{MINT_DOMAIN}"

print(f"Mint URL: {mint_url}")

# --- Mint e-cash using cashu CLI ---
print(f"Attempting to mint {MINT_AMOUNT} satoshis from {mint_url}...")

# Get an invoice for minting
invoice_command = ["cashu", "invoice", str(MINT_AMOUNT), "--mint", mint_url, "--nostr-private-key", private_key]

try:
    invoice_result = subprocess.run(invoice_command, check=True, capture_output=True, text=True)
    print("Cashu invoice output:")
    print(invoice_result.stdout)
    invoice_data = json.loads(invoice_result.stdout)
    invoice = invoice_data["invoice"]
    hash_id = invoice_data["hash"]
except subprocess.CalledProcessError as e:
    print(f"Error getting invoice: {e}")
    print(f"Stdout: {e.stdout}")
    print(f"Stderr: {e.stderr}")
    exit(1)
except json.JSONDecodeError:
    print(f"Error: Could not parse JSON from invoice command output: {invoice_result.stdout}")
    exit(1)

print(f"Generated Invoice: {invoice}")
print(f"Invoice Hash: {hash_id}")

# Simulate payment (since we are using fakewallet)
# In a real scenario, you would pay this invoice via a Lightning wallet.
print("Simulating invoice payment...")
# For fakewallet, we don't actually need to pay, just proceed to mint.

# Mint e-cash with the paid invoice
mint_command = ["cashu", "mint", str(MINT_AMOUNT), "--hash", hash_id, "--mint", mint_url, "--nostr-private-key", private_key]

try:
    mint_result = subprocess.run(mint_command, check=True, capture_output=True, text=True)
    print("Cashu mint output:")
    print(mint_result.stdout)
    if mint_result.stderr:
        print("Cashu mint errors:")
        print(mint_result.stderr)
except subprocess.CalledProcessError as e:
    print(f"Error minting e-cash: {e}")
    print(f"Stdout: {e.stdout}")
    print(f"Stderr: {e.stderr}")
    exit(1)

print("E-cash minting process completed.")
