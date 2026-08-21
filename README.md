<div align="center">

# Breeze

**Your air conditioner, on your phone, without the cloud.**

A native Flutter (Android) client for a
[**Breeze Core**](https://github.com/monikapurpl3/breeze-core) server —
self-hosted control for Midea air conditioners, over your own LAN.

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/monikapurpl3/breeze?label=release)](https://github.com/monikapurpl3/breeze/releases/latest)
[![APK](https://img.shields.io/badge/APK-bolero-6aa84f)](https://bolero.salataputarica.hr.eu.org/android/)
[![Documentation](https://img.shields.io/badge/docs-wiki-8e7cc3)](https://github.com/monikapurpl3/breeze/wiki)

</div>

<p align="center">
  <img src="https://i.imgur.com/LyieDjQ.png" alt="Breeze — the control screen, network scan-to-add, and the Programs editor" width="900">
</p>

## Why

The vendor app sends "make it 23°" to a datacentre and back, to reach a unit in
the same room as you. Breeze asks a server on your own network instead.

- **One unit per screen, swipe to switch.** Each unit fills the screen, tinted to
  its mode. No menus, no dashboard to configure.
- **It reacts immediately** — optimistic controls with haptics, and the server
  *pushes* state over SSE, so the screen is right without waiting on a poll.
- **Control it without opening it** — home-screen widgets with real buttons, and an
  Android Auto screen that is one huge power button.
- **Schedules that don't need your phone.** Favourites, schedules and temperature
  curves run on the server and fire with the phone off.
- **Two permissions, total:** internet and vibrate. No account, no analytics, no
  ads, nothing to opt out of.
- **It's quiet.** Beep is off unless you turn it on.
- **Material You**, light/dark, °C/°F, and a real diagnostics screen when something
  misbehaves.

## Install

Grab the APK from the
[latest release](https://github.com/monikapurpl3/breeze/releases/latest) or from
[bolero](https://bolero.salataputarica.hr.eu.org/android/):

```bash
adb install -r Breeze-2.2.6.apk
```

…or copy it to the phone and open it. Android 7.0+.

On first launch: enter the server address, its access key, and a device name — then
an **admin approves the pairing code on the LAN**. That last step is the one people
don't expect, and it's the point: each phone gets its own revocable credential
instead of a shared password.

> **It needs a [Breeze Core](https://github.com/monikapurpl3/breeze-core) server**
> on your network — a Pi, NAS or old laptop is plenty. Control, pairing and
> diagnostics work against any server version; **≥ 3.0.0** adds Ed25519 signing,
> live updates, scan-to-add and per-command beep.

## Documentation

Everything lives in the **[wiki](https://github.com/monikapurpl3/breeze/wiki)**:

|  |  |
|---|---|
| [Installing it](https://github.com/monikapurpl3/breeze/wiki/Installing-Breeze) · [Version history](https://github.com/monikapurpl3/breeze/wiki/Version-history) | getting started, and what changed when |
| [The control screen](https://github.com/monikapurpl3/breeze/wiki/The-control-screen) · [Programs](https://github.com/monikapurpl3/breeze/wiki/Programs) | using it day to day |
| [Home-screen widgets](https://github.com/monikapurpl3/breeze/wiki/Home-screen-widgets) · [Android Auto](https://github.com/monikapurpl3/breeze/wiki/Android-Auto) | controlling it without opening it |
| [Diagnostics and the Nerd screen](https://github.com/monikapurpl3/breeze/wiki/Diagnostics-and-the-Nerd-screen) · [Multiple servers](https://github.com/monikapurpl3/breeze/wiki/Multiple-servers) | when something's off, and running more than one server |
| [Security](https://github.com/monikapurpl3/breeze/wiki/Security) | how credentials are held, and how a 401 is handled |
| [Architecture](https://github.com/monikapurpl3/breeze/wiki/Architecture) · [Building and releasing](https://github.com/monikapurpl3/breeze/wiki/Building-and-releasing) | working on it |
| [iOS port (plan)](https://github.com/monikapurpl3/breeze/wiki/iOS-port-plan) | what an iOS build would take |

## Honest limits

It needs a server somebody runs. **Android only** — other platforms get the
server's web panel. Away from home you need a VPN or a proxy you've secured.
Pairing takes an admin on the LAN. If the server is down, the app can't do
anything (your remote still can). And the units must reach Wi-Fi through the
vendor app once, first — Breeze can't onboard a factory-fresh unit.

The full comparison, drawbacks included:
[Compared to NetHome Plus](https://github.com/monikapurpl3/breeze/wiki/Compared-to-NetHome-Plus).

## Build it yourself

```bash
flutter pub get
flutter build apk --release     # → build/app/outputs/flutter-apk/app-release.apk
```

Flutter 3.44+, Android SDK (API 36), JDK 17/21. Release signing, icons and CI:
[Building and releasing](https://github.com/monikapurpl3/breeze/wiki/Building-and-releasing).

## License

[AGPL-3.0](LICENSE), same as the server. Every dependency is permissive — BSD-3
(Flutter, `http`, `shared_preferences`, `flutter_secure_storage`,
`package_info_plus`, `home_widget`), MIT (`cupertino_icons`, `workmanager`,
`pointycastle`) and Apache-2.0 (`dynamic_color`, `cryptography`, and the AndroidX
Car App Library behind Android Auto) — which AGPL-3.0 permits. The full texts are
in the app under **Settings → Licences**. Found a vulnerability?
[SECURITY.md](SECURITY.md) — privately, please.
