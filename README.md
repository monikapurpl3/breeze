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

**Contents:** [Screens](#screens) · [Why not the vendor app?](#why-not-the-vendor-app)
· [The control screen](#the-control-screen) · [More features](#more-features) ·
[Android Auto](#android-auto) · [Security](#security) ·
[Getting started](#getting-started) · [Project layout](#project-layout) ·
[License](#license)

---

## Screens

<p align="center">
  <img src="https://i.imgur.com/LyieDjQ.png" alt="Breeze — the control screen, network scan-to-add, and the Programs editor" width="900">
</p>

---

## Why not the vendor app?

*NetHome Plus* talks to your air conditioner by going out to the internet,
through Midea's cloud, and back down to a unit that's in the same room as you.
Breeze talks to a server on your own network, which talks to the unit. That one
difference is most of the list:

- **It works when the internet doesn't.** Router still up? So is your AC.
- **No account.** No sign-up, no e-mail, no password to share around the
  household — pairing is a one-time code an admin approves on the LAN, and each
  phone gets its own credential that can be revoked on its own.
- **Two permissions, total:** internet and vibrate. No location, no contacts,
  no ads, no analytics, no upsell, nothing to opt out of.
- **It's simpler.** One unit per screen, everything on it, swipe for the next
  one. No menus to dig through, no dashboard to configure.
- **It reacts immediately** — every control is optimistic with haptic feedback,
  and the server *pushes* state over SSE, so the screen is right without
  waiting on a poll or a cloud round-trip.
- **Control without opening it at all:** home-screen widgets (power, temp ±,
  and a colour-coded on/off badge) and an [Android Auto](#android-auto) screen
  that's one big power button.
- **Schedules that don't need your phone.** Favourites, schedules, and
  temperature curves live on the server and fire with the phone off.
- **It's quiet.** Beep is off unless you turn it on — set the temperature at
  3 a.m. without a chirp.
- **Material You**, light/dark, °C/°F, and a real diagnostics screen when
  something misbehaves.

**What you give up:**

- It **needs a [Breeze Core](https://github.com/monikapurpl3/breeze-core)
  server** on your network — a Pi, NAS, or old laptop is plenty, but somebody
  has to run it.
- **Android only.** Other platforms get the server's web panel.
- **Away from home you need a VPN** (or a reverse proxy you've secured) —
  nothing is exposed to the internet for you.
- **Pairing takes an admin on the LAN.** That's the point, and it's still a
  step the cloud app doesn't have.
- **If the server is down, the app can't do anything.** Your remote still can.
- The units must reach Wi-Fi through the vendor app once, first — Breeze can't
  onboard a factory-fresh unit.

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
- **Flap** — one big pill split in two: **vertical flap** and **horizontal
  flap**, each toggled on its own (neither, either, or both).
- **Eco / Turbo** — large, colourful switches.
- **Power** — a big switch in the header: **faintly red when off, faintly green
  when on**, so the unit's state is never in doubt.

Every change is **optimistic with haptic feedback** (it reflects instantly,
then reconciles with the server), and the screen **never flickers** while
refreshing (state merges in place; a tiny indicator shows only while *you*
trigger a command). On Breeze Core ≥ 3.0.0 it receives **live updates over
SSE** — the server pushes changes (including ones made by a schedule or
another client) so the phone stops polling; against older servers, or if the
stream drops, it falls back to a 5 s poll. An **offline banner** appears with
backed-off polling when the server is unreachable. The app **reopens on the
unit you last viewed** (it remembers by unit, so it survives adding, removing,
or reordering units).

---

## More features

| Area | What it does |
|---|---|
| **Add units** | **Scan the network** for units (≥ 3.0.0 finds them by their open AC ports — tap to add) **or add by LAN IP**; **rename** and **remove** too. |
| **Home-screen widgets** | A resizable widget per unit showing temperature, mode and a bold **ON / OFF / OFFLINE** badge — the whole widget is **colourful while the unit runs and colourless when it's off**. **Power / temp − / temp +** buttons work **without opening the app**, plus periodic background refresh. |
| **Programs** | Favourites (saved scenes), schedules (day/time), and a **temperature-curve** builder with a live preview — all stored and run **server-side**, so they fire even with the phone off. |
| **Diagnostics** | A full battery mirroring the server's `diag`: connectivity + **server build/features** (and the app's own version), **authentication & security posture** (rejects missing/wrong keys, reports token-gating), **this device's credential** (auth version + expiry warnings), config secret-sanitisation, input-validation (unknown unit → 404, out-of-range → 422), batch state, a **live-stream check**, and per-unit state / latency / **hardware capabilities**. |
| **Multiple servers** | Save as many Breeze Core servers as you like and **switch between them instantly** — each keeps its own credential in the keystore, so returning to one you've used before needs no re-pairing (which would mean getting an admin onto *that* server's LAN). Rename or forget them individually. |
| **Nerd screen** | Tap the version in Settings seven times: the app's version and dependency versions, the round-trip latency, how the server sees this client, and — from `GET /api/system` — the server's OS, init system, CPU/arch, every component version, install date, uptime, units with their capabilities, and every enrolled device. One tap copies the lot. Needs Breeze Core ≥ 3.0.5; older servers get *womp womp update your server*. |
| **Settings** | Servers, re-pair, °C/°F, light/dark/system theme, a **beep-on-control** toggle (≥ 3.0.0), and the open-source licences. |
| **Android Auto** | One unit per screen, one **huge power button** — see [below](#android-auto). |
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

## Android Auto

A deliberately tiny car surface, built with the **Android for Cars App
Library** (native Kotlin, in the same APK): **one AC per screen, and nothing on
it but a huge power button**, with the unit's name in the header above it.
Big **▲ / ▼** actions step between units, wrapping around. Everything else —
temperature, mode, fan, programs — stays on the phone, on purpose: you should
be able to hit this without reading it.

The button is colour-coded (**green running, red stopped**) and labelled
**ON** / **OFF**, or *Not reachable* if the unit is offline. Taps respond
immediately — the state flips optimistically while the command flies, and
reconciles when the real state lands.

**How it authenticates:** it doesn't, itself. The car screen reads the same
cached unit list/state the home-screen widgets use, and fires the same headless
background callback to control a unit — so it reuses the phone's Ed25519
signing and Keystore-held credentials rather than shipping a second API client
and a copy of the crypto into the car process. Consequence: **open the phone
app once** after installing, so there's something cached to show.

**Installing it (why it isn't just "there"):** Android Auto only loads template
apps in a handful of categories, and everything outside navigation/media needs
Google review to be distributed through Play.

**The gotcha that cost a whole evening:** the service declares two categories —
`androidx.car.app.category.IOT` (the semantically correct home for "control a
device at my house", and what Google's IoT guide pairs with the `GridTemplate`
used here) and `POI`. Through 2.2.0 it declared them as **two separate
`<intent-filter>` blocks**, and the app never appeared in the car launcher, on a
phone with developer mode *and* unknown sources enabled. Two filters resolve
perfectly well in `PackageManager` — both category queries return the service —
but the host reads the categories off the first `ResolveInfo` it gets and sees
only one of them. **One filter carrying both categories** (2.2.1) and Auto
picked it up immediately. If you're writing a car app and it's invisible with no
error anywhere, check that first.

POI is a stretch semantically and would be rejected in Play review; for a
self-hosted APK it's the pragmatic answer. If this ever goes to Play, drop POI
and ship the car surface for Automotive OS only.

For a self-hosted APK you also enable it yourself:

1. In **Android Auto** settings on the phone, tap *Version* ~10× to unlock
   **Developer settings**.
2. In the ⋮ menu → **Developer settings**, enable **Unknown sources**.
3. Reconnect to the car (or the [Desktop Head Unit](https://developer.android.com/training/cars/testing/dhu)) —
   Breeze shows up in the launcher, and Auto posts a "new app" notification the
   first time it sees it.

Release builds accept any host (`HostValidator.ALLOW_ALL_HOSTS_VALIDATOR`).
Validating against the library's sample allowlist is right for a Play app and
wrong for a sideloaded one: the Desktop Head Unit isn't a signed host, so it
makes the car surface untestable, and a mismatch fails silently with nothing in
the log. What a rogue host gets here is the ability to toggle an air
conditioner.

Because the host renders the templates, it — not the app — decides exact sizes
and where the ▲/▼ actions sit; "huge" means the largest primitive the library
offers (a single-item grid).

**Verified** against the Desktop Head Unit on Android Auto 17.3: discovered,
listed, bound, screen rendered. If it ever misbehaves, the car classes log
under the tag `BreezeCar` — `adb logcat -s BreezeCar` shows the service being
created, the session opening, and each template build with its unit count.

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
    └── widgets/                 temp_control, fan_control, flap_control, power_switch, big_toggle, mode_selector, curve_painter, climate_settings_editor

android/app/src/main/
├── kotlin/app/breeze/breeze/   BreezeUnitWidgetProvider + UnitConfigActivity (App Widget)
│   └── car/                    Android Auto: BreezeCarAppService, PowerScreen, CarUnitStore
└── res/                        layout/breeze_widget*, xml/{breeze_widget_info,automotive_app_desc}, widget + car drawables, colours
```

## License

GNU Affero General Public License v3.0 ([AGPL-3.0](LICENSE)) — same as the
[Breeze Core](https://github.com/monikapurpl3/breeze-core) server. All
dependencies are permissive (Flutter / `http` / `flutter_secure_storage`
BSD-3, `dynamic_color` Apache-2.0), which AGPL-3.0 permits.
