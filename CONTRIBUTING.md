# Contributing to Breeze

Thanks for helping out! Breeze is the native **Android (Flutter)** client for a [Breeze Core](https://github.com/monikapurpl3/breeze-core) server.

## Dev setup

Requires the **Flutter SDK** (3.44+) and, to build/run on device, the **Android SDK** (API 36) + a JDK 17/21.

```bash
flutter pub get
flutter analyze          # must be clean
flutter test             # unit tests
flutter run              # on a connected device/emulator
```

You'll need a running Breeze Core server (real or a local dev instance) to log in and test against.

## Before you open a PR

- `flutter analyze` is **clean** (CI enforces it).
- `flutter test` passes.
- If you changed UI, sanity-check light **and** dark, and Material You dynamic colour on Android 12+.
- Keep changes focused and describe what/why.

## Conventions (please match these)

- **All network calls go through `lib/src/api_client.dart`** — the single client that attaches the API key + device token and enforces HTTPS. Don't call `http` directly elsewhere.
- **Secrets** (key, device token) live only in `flutter_secure_storage` — never in plain prefs, logs, or the widget tree.
- **Colours come from the Material You scheme** (`lib/src/theme.dart`) — no hard-coded brand colours; use `scheme.*` / `harmonizeWith`.
- Preserve the server wire contract in `lib/src/models.dart` (snake_case JSON).
- No new heavyweight dependencies without discussion; keep it building without a bundler/extra tooling.

## Signing

Release signing reads `android/key.properties` (git-ignored). Without it, release builds fall back to debug signing — fine for local testing. Never commit `key.properties` or a keystore.

## Security

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md).

## License

By contributing you agree your contributions are licensed under **AGPL-3.0** ([LICENSE](LICENSE)).
