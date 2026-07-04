# Breeze

A native **Flutter (Android)** client for a [**Breeze Core**](https://github.com/monikapurpl3/breeze-core) server — self-hosted control for Midea air conditioners. Branding is deliberately generic: on first launch it asks for a server address and access key and reveals nothing about the backend.

> Requires a running **Breeze Core** server on your network — see that repo to set one up. Units, control, pairing, and diagnostics work against any version; the Programs screen needs the server's scheduler feature.

---

## Features

- **Units** — a live control card per unit: power, a temperature dial + stepper, mode (auto/cool/dry/heat/fan), fan speed, eco, turbo, and two independent flaps (↕ / ↔). Polls every 5 s; pull to refresh.
- **Pairing** — a device-grant handshake: enter the server URL + access key, get a one-time code, an admin approves it on the LAN, and the app stores a per-device token.
- **Programs** — favourites (saved scenes), schedules (day/time triggers), and a **time-temperature curve** builder with a live preview chart. Stored and executed **server-side**, so they run even when the phone is off.
- **Diagnostics** — in-app reachability, scheduler status, and per-unit state/latency/enum checks.
- **Settings** — change server, re-pair this device, about.
- **Material You** — fully dynamic colour from the system wallpaper (Android 12+), light/dark following the system, with a seeded fallback on older devices.

## Security

- Access key and per-device token are stored with `flutter_secure_storage` (Android Keystore-backed, encrypted at rest); `allowBackup=false` keeps them out of device/cloud backups.
- Every request carries both credentials through one client; a `401` drops the token and re-pairs.
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
    ├── models.dart              wire models (units, control, programs)
    ├── api_client.dart          HTTP layer (TLS enforcement, timeouts, typed errors)
    ├── secure_store.dart        encrypted credential storage
    ├── app_controller.dart      app state + pairing flow
    ├── app_scope.dart           InheritedNotifier exposing the controller
    ├── theme.dart / util.dart   Material You accents, time helpers
    ├── screens/                 onboarding, pairing, home, diagnostics, programs, program_edit, settings
    └── widgets/                 dial, unit_card, curve_painter, climate_settings_editor
```

## License

GNU Affero General Public License v3.0 ([AGPL-3.0](LICENSE)) — same as the [Breeze Core](https://github.com/monikapurpl3/breeze-core) server. All dependencies are permissive (Flutter/`http`/`flutter_secure_storage` BSD-3, `dynamic_color` Apache-2.0), which AGPL-3.0 permits.
