# Cashu NUTs Summary for TollGate

This document summarizes the relevant Cashu NUTs (Nostr Unofficial Transfer protocols) for the TollGate project and provides an overview of how they relate to our goal of creating operator-only mints.

## NUT Summaries

### NUT-20: Signature on Mint Quote

NUT-20 provides a simple and effective way to restrict minting to a specific user. When a wallet requests a mint quote, it can provide a public key. The mint will then require a valid signature from the corresponding private key to process the minting operation, ensuring that only the owner of that key can mint new tokens.

### NUT-21: Clear Authentication

NUT-21 defines a more complex authentication scheme using an external OpenID Connect (OIDC) service. It allows mint operators to limit the use of their mint to registered users who have obtained a clear authentication token (CAT). This is a powerful but more complex solution that requires deploying and managing an OAuth server.

### NUT-22: Blind Authentication

NUT-22 builds on NUT-21 to provide a blind authentication scheme. Users first authenticate with the OIDC service to get a CAT, then use that CAT to obtain blind authentication tokens (BATs) from the mint. These BATs can then be used to access protected endpoints, providing a layer of privacy within the set of authenticated users.

## How the NUTs Relate to Our Goals

Our primary goal is to create a simple, easy-to-deploy mint for each TollGate operator, where only the operator (identified by their `npub`) can mint new "testnuts".

*   **NUT-20 is the ideal solution for this.** It provides a direct, signature-based authentication method that ties the minting process to the operator's Nostr key pair. This avoids the complexity of deploying and managing an OAuth server, making it a much more lightweight and suitable solution for our use case.

*   **NUT-21 and NUT-22 are overkill for our needs.** While they offer more advanced authentication and privacy features, the added complexity of an OAuth server is a significant barrier to entry for new operators. Our goal is simplicity and ease of deployment, which NUT-20 provides perfectly.

## Summary of Manual `cashu` Commands

Here are the manual `cashu` commands we used to test the minting process:

1.  **Set the mint URL as an environment variable:**
    ```bash
    export CASHU_MINT_URL=<YOUR_MINT_URL>
    ```

2.  **Get an invoice for minting:**
    ```bash
    NOSTR_PRIVATE_KEY=<YOUR_NOSTR_PRIVATE_KEY> cashu invoice 21
    ```
    This command returns a JSON object with an `invoice` and a `hash`.

3.  **Mint e-cash with the paid invoice:**
    ```bash
    NOSTR_PRIVATE_KEY=<YOUR_NOSTR_PRIVATE_KEY> cashu mint 21 --hash <INVOICE_HASH>
    ```
    This command uses the `hash` from the previous step to complete the minting process.

## Proposed Plan

Given that NUT-20 is the clear path forward, our next steps should be to:

1.  **Disable the complex OAuth-based authentication:** We'll set `auth_enabled: false` in `group_vars/all.yml` to remove the Keycloak and PostgreSQL services.
2.  **Implement NUT-20 in the mint:** We'll need to modify the mint's configuration to require a signature on mint quotes, as described in NUT-20. This will likely involve changes to the `cdk` configuration within the Ansible roles.
3.  **Update the test script:** We'll update `scripts/test-mint-auth.py` to use the NUT-20 flow for minting.
