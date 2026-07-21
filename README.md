# Breeze

A native **Flutter (Android)** client for a [**Breeze Core**](https://github.com/monikapurpl3/breeze-core) server — self-hosted control for Midea air conditioners. Branding is deliberately generic: on first launch it asks for a server address and access key and reveals nothing about the backend.

> Requires a running **Breeze Core** server on your network — see that repo to set one up. Control, pairing, and diagnostics work against any version; **Breeze Core ≥ 3.0.0** unlocks the full experience — Ed25519 request signing, network scan-to-add, and per-command beep. Older servers still work (the app falls back to bearer-token auth and manual add), and the Programs screen needs the server's scheduler feature.

---

## Features

- **Units — one per screen, swipe between them.** Each unit fills the screen (no scrolling) with big, modern, colourful controls: a large temperature readout with a **stepped slider and − / + buttons** (0.5° steps), an **indoor-temperature bar** tinted to the active mode, a **fan slider** that runs low→high and **detaches to Auto**, a **flap** on/off toggle plus a free-gliding slider (up-down · both · left-right), **large eco / turbo switches**, a colourful mode picker (auto/cool/dry/heat/fan), and power. Controls are **optimistic with haptic feedback** — a tap reflects instantly and reconciles on the server reply — and the screen **never flickers** while refreshing (state merges in place; a small indicator shows only while *you* trigger a command). Polls every 5 s (one batched request on Breeze Core ≥ 2.4.0). An **offline banner** appears and polling backs off when the server is unreachable.
- **Manage units** — **scan the network** for units (Breeze Core ≥ 3.0.0 finds them by their open AC ports and you tap to add) **or add by LAN IP**; **rename** and **remove** too. *(Add/rename require Breeze Core ≥ 2.2.0; remove ≥ 2.4.0; scan ≥ 3.0.0.)*
- **Home-screen widgets** — place a resizable widget per unit showing its temperature, mode, and power, with **power / temp − / temp +** buttons that control the unit **without opening the app** (each tap runs a headless background task using your stored credentials, then refreshes the widget). Widgets also **auto-refresh periodically** in the background. Tap the body to open Breeze; a placement dialog picks which unit each widget controls. Material You themed on Android 12+.
- **Pairing** — a device-grant handshake: enter the server URL + access key, get a one-time code, an admin approves it on the LAN. On Breeze Core ≥ 3.0.0 the app generates an **Ed25519 keypair** and registers only its public key (see Security); against older servers it falls back to a bearer token. Either way it re-pairs automatically on a `401`.
- **Programs** — favourites (saved scenes), schedules (day/time triggers), and a **time-temperature curve** builder with a live preview chart. Stored and executed **server-side**, so they run even when the phone is off.
- **Diagnostics** — in-app reachability, scheduler status, and per-unit state/latency/enum checks.
- **Settings** — change server, re-pair this device, **display options** (°C/°F, and a light / dark / system theme override), a **beep-on-control** toggle (make the unit chirp when it accepts a command; Breeze Core ≥ 3.0.0), and about.
- **Material You** — fully dynamic colour from the system wallpaper (Android 12+); light/dark follows the system by default, or force one in Settings. Seeded fallback on older devices.

## Security

- **Ed25519 request signing (Breeze Core ≥ 3.0.0).** The device generates an Ed25519 keypair at pairing; the **private key never leaves the phone** (stored as a seed in `flutter_secure_storage`, Android Keystore-backed) and the server only ever holds the public key. Every control request is signed over its method, path, timestamp, a single-use nonce, and a **SHA3-512 digest of the body** — so requests can't be replayed or tampered with, and a server-side leak exposes nothing forgeable. A device on the older bearer scheme upgrades itself in place on first launch against a 3.0 server.
- **Bearer fallback.** Against pre-3.0 servers the app uses the original per-device bearer token (also Keystore-backed). The access key rides on every request; a `401` drops the credential and re-pairs; a `426` triggers the in-place upgrade.
- `allowBackup=false` keeps credentials out of device/cloud backups.
- HTTPS is enforced for non-private hosts (and Android blocks cleartext by default).
- Admin approval is LAN-only (enforced by the server); the app never performs approval.

## Requirements

- **Flutter 3.44+** and the **Android SDK** (API 36 for this Flutter version) + a JDK 17/21.
- An Android device/emulator on Android 7.0 (API 24) or newer.

## Build

```bash
flutter pub get
flutter build apk --release     # → build/app/outputs/flutter-apk/app-release.apk
```

**Release signing** is read from `android/key.properties` (git-ignored). Create a keystore and that file to sign your own builds:

```bash
keytool -genkeypair -v -keystore ~/keys/breeze-release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias breeze
cat > android/key.properties <<EOF
storePassword=…
keyPassword=…
keyAlias=breeze
storeFile=/absolute/path/to/breeze-release.jks
EOF
```
Without `key.properties`, the release build falls back to debug signing (fine for local testing). App icons regenerate with `dart run flutter_launcher_icons` from `assets/icon/`.

## Install

```bash
# phone connected via USB with USB debugging on:
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
Or copy the `.apk` to the phone and open it (allow "install unknown apps"). On first launch enter your server (e.g. `https://breeze.example.com`), the access key, and a device name, then have an admin approve the code on the LAN.

## Configuration

Nothing is baked in — the server URL and key are entered at runtime and stored encrypted. Switch servers or re-pair any time from **Settings**.

## Project layout

```
lib/
├── main.dart                    Material You theming + stage router
└── src/
    ├── models.dart              wire models (units, control incl. beep, programs)
    ├── api_client.dart          HTTP layer (TLS enforcement, timeouts, typed errors, request signing)
    ├── device_signer.dart       Ed25519 keypair + SHA3-512 request signing (v2 auth)
    ├── secure_store.dart        encrypted credential storage (key, Ed25519 seed / bearer token)
    ├── app_controller.dart      app state + pairing / in-place v1→v2 upgrade
    ├── app_scope.dart           InheritedNotifier exposing the controller
    ├── home_widget_service.dart home-screen widget sync + headless control callback
    ├── theme.dart / util.dart   Material You accents, time helpers
    ├── screens/                 onboarding, pairing, home (swipe pager), unit_page, diagnostics, programs, program_edit, settings
    └── widgets/                 temp_control, fan_control, flap_control, big_toggle, mode_selector, curve_painter, climate_settings_editor

android/app/src/main/
├── kotlin/app/breeze/breeze/   BreezeUnitWidgetProvider + UnitConfigActivity (App Widget)
└── res/                        layout/breeze_widget*, xml/breeze_widget_info, widget drawables + colours
```

## License

GNU Affero General Public License v3.0 ([AGPL-3.0](LICENSE)) — same as the [Breeze Core](https://github.com/monikapurpl3/breeze-core) server. All dependencies are permissive (Flutter/`http`/`flutter_secure_storage` BSD-3, `dynamic_color` Apache-2.0), which AGPL-3.0 permits.
