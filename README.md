# Breeze

A native **Flutter (Android)** client for a
[**Breeze Core**](https://github.com/monikapurpl3/breeze-core) server —
self-hosted control for Midea air conditioners. Branding is deliberately
generic: on first launch it asks for a server address and access key and
reveals nothing about the backend.

> **Needs a Breeze Core server on your network** (see that repo to set one
> up). Control, pairing, and diagnostics work against any server version.
> **Breeze Core ≥ 3.0.0** unlocks the full experience — Ed25519 request
> signing, network scan-to-add, and per-command beep — and older servers
> still work (the app falls back to bearer-token auth and manual add). The
> Programs screen needs the server's scheduler feature.

**Contents:** [Screens](#screens) · [The control screen](#the-control-screen)
· [More features](#more-features) · [Security](#security) ·
[Getting started](#getting-started) · [Project layout](#project-layout) ·
[License](#license)

---

## Screens

<!-- Screenshots live in docs/img/. Drop them in and use the table below.
| Control screen | Scan to add | Programs |
|:--:|:--:|:--:|
| ![Control screen](docs/img/control.png) | ![Scan to add](docs/img/scan.png) | ![Programs](docs/img/programs.png) |
-->

![Uploading merged-image-1784808972415.png…]()


---

## The control screen

**One unit per screen — swipe left/right to switch.** Each unit fills the
screen (no scrolling), tinted to the active mode:

- **Temperature** — a big readout with a **stepped slider** (0.5° steps) and
  **− / +** buttons on each side for single steps.
- **Indoor bar** — a slim bar beside the indoor reading, coloured by the
  current mode.
- **Mode** — a colourful segmented picker: auto · cool · dry · heat · fan.
- **Fan** — a Low→High slider that **detaches to Auto**.
- **Flap** — an on/off switch plus a free-gliding slider: up-down · both ·
  left-right.
- **Eco / Turbo** — large, colourful switches. **Power** — front and centre.

Every change is **optimistic with haptic feedback** (it reflects instantly,
then reconciles with the server), and the screen **never flickers** while
refreshing (state merges in place; a tiny indicator shows only while *you*
trigger a command). On Breeze Core ≥ 3.0.0 it receives **live updates over
SSE** — the server pushes changes (including ones made by a schedule or
another client) so the phone stops polling; against older servers, or if the
stream drops, it falls back to a 5 s poll. An **offline banner** appears with
backed-off polling when the server is unreachable.

---

## More features

| Area | What it does |
|---|---|
| **Add units** | **Scan the network** for units (≥ 3.0.0 finds them by their open AC ports — tap to add) **or add by LAN IP**; **rename** and **remove** too. |
| **Home-screen widgets** | A resizable widget per unit (temperature, mode, power) with **power / temp − / temp +** buttons that work **without opening the app**, plus periodic background refresh. |
| **Programs** | Favourites (saved scenes), schedules (day/time), and a **temperature-curve** builder with a live preview — all stored and run **server-side**, so they fire even with the phone off. |
| **Diagnostics** | In-app reachability, scheduler status, and per-unit state / latency / enum checks. |
| **Settings** | Change server, re-pair, °C/°F, light/dark/system theme, and a **beep-on-control** toggle (≥ 3.0.0). |
| **Theming** | **Material You** dynamic colour from the wallpaper (Android 12+); light/dark follows the system, or force one. |

**Home-screen widgets, in detail:** each button tap runs a headless
background task using your stored credentials and refreshes the widget; tap
the widget body to open the app; a placement dialog picks which unit a widget
controls.

**Pairing:** enter the server URL + access key, get a one-time code, an admin
approves it on the LAN. On Breeze Core ≥ 3.0.0 the app generates an Ed25519
keypair and registers only its public key; against older servers it falls
back to a bearer token; either way it re-pairs automatically on a `401`.

---

## Security

- **Ed25519 request signing (≥ 3.0.0).** The private key is generated on the
  device and **never leaves it** (a seed in `flutter_secure_storage`, Android
  Keystore-backed); the server holds only the public key. Every request is
  signed over method + path + timestamp + single-use nonce + **SHA3-512 body
  digest** — no replay, no tampering, and a server leak exposes nothing
  forgeable. A device on the old scheme upgrades itself in place on first
  launch against a 3.0 server.
- **Bearer fallback** for pre-3.0 servers (also Keystore-backed). A `401`
  drops the credential and re-pairs; a `426` triggers the in-place upgrade.
- `allowBackup=false` keeps credentials out of device/cloud backups.
- HTTPS enforced for non-private hosts (Android blocks cleartext by default).
- Admin approval is **LAN-only** (enforced by the server); the app never
  performs approval.

---

## Getting started

**Requirements:** Flutter 3.44+, the Android SDK (API 36 for this Flutter
version) + JDK 17/21, and an Android device/emulator on Android 7.0 (API 24)+.

**1. Build:**

```bash
flutter pub get
flutter build apk --release     # → build/app/outputs/flutter-apk/app-release.apk
```

**2. Install:**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk   # USB debugging on
```

…or copy the `.apk` to the phone and open it (allow *install unknown apps*).

**3. First launch:** enter your server (e.g. `https://breeze.example.com`),
the access key, and a device name — then have an admin approve the code on
the LAN. Nothing is baked in; switch servers or re-pair any time from
**Settings**.

<details>
<summary><b>Signing your own release builds</b></summary>

Release signing is read from `android/key.properties` (git-ignored). Without
it, the release build falls back to debug signing (fine for local testing).

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

App icons regenerate with `dart run flutter_launcher_icons` from `assets/icon/`.
</details>

---

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

GNU Affero General Public License v3.0 ([AGPL-3.0](LICENSE)) — same as the
[Breeze Core](https://github.com/monikapurpl3/breeze-core) server. All
dependencies are permissive (Flutter / `http` / `flutter_secure_storage`
BSD-3, `dynamic_color` Apache-2.0), which AGPL-3.0 permits.
