# Security Policy

Breeze is a client that holds credentials for controlling physical devices, so security reports are welcome.

## Reporting a vulnerability

**Please report privately — do not open a public issue.**

Use GitHub's private vulnerability reporting: the repo's **Security** tab → **Report a vulnerability** (or [open a draft advisory](https://github.com/monikapurpl3/breeze/security/advisories/new)). Include what the issue is, its impact, steps/PoC to reproduce, the app version, and your Android version/device.

Please allow a reasonable window to fix before public disclosure. No bounty (hobby project), but credit is gladly given. Server-side issues belong in [breeze-core](https://github.com/monikapurpl3/breeze-core/security).

## What the app does with secrets

- The access key and the per-device credential — an **Ed25519 private-key seed** (Breeze Core ≥ 3.0.0) or a bearer token (older servers) — are stored via `flutter_secure_storage` (Android Keystore-backed, encrypted at rest). The Ed25519 private key never leaves the device; the server holds only the public key.
- `android:allowBackup="false"` keeps them out of device/cloud backups.
- Requests go over HTTPS (cleartext is refused for non-private hosts, and Android blocks it by default). Under Ed25519 auth the device credential is **never transmitted** — each request is signed (method + path + timestamp + nonce + SHA3-512 body digest) so it can't be replayed or tampered with; the bearer fallback sends the token as before.
- The app never performs pairing **approval** — that's LAN-only and enforced by the server.

## Scope

In scope: credential handling/leakage, TLS/transport issues, anything that lets another app or party read the stored secrets or control units. Out of scope: issues requiring a rooted/compromised device, and server-side vulnerabilities (report those on breeze-core).
