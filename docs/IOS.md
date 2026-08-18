[← Breeze](../README.md)

# Plan: an iOS build of Breeze, and how to ship yourself one

**Status: plan only. Nothing here is implemented — there is no `ios/` directory
in this repository yet.**

Two audiences, and they want different things:

- **[Part A](#part-a--the-plan)** is for whoever does the porting work: what
  already crosses over for free, what needs iOS-specific code, what genuinely
  cannot come along, and in what order.
- **[Part B](#part-b--build-and-ship-it-yourself)** is for an Apple-ecosystem
  user who wants Breeze on their own iPhone once Part A is done. If you have a
  Mac and a cable, that section is all you need.

---

## The constraint that shapes everything

**iOS apps can only be built, signed and submitted on macOS**, because Xcode and
`codesign` are macOS-only. There is no way around this — no Flutter flag, no
Docker image, no cross-compiler. Breeze is developed on Windows.

So "we ship an iOS app" is not on the table in the way it is for Android, where
one command on the dev box produces a signed APK anyone can install. What *is*
on the table:

| Approach | Who needs a Mac | What the user gets |
|---|---|---|
| **iOS-ready codebase + documented recipe** | the *user*, once | they build and install it themselves (Part B) |
| **CI build on GitHub's macOS runners** | nobody | proof it compiles, plus an unsigned `.app` artifact |
| **Signed `.ipa` / TestFlight** | the *maintainer*, ongoing | tap-to-install — needs a Mac **and** $99/yr |

The recommendation is the first two. They cost no hardware and no subscription,
and they turn "impossible" into "an afternoon for anyone with a Mac". A signed
build is a decision to revisit only if enough people ask.

---

# Part A — the plan

## A1. What already ports for free

This is better than expected, and worth establishing before the work list,
because it means the port is mostly *configuration* rather than rewriting.

**The UI is mostly custom-painted.** The temperature dial, fan control, flap,
mode and power controls, and the indoor/outdoor climate bar are drawn with
`CustomPainter`, not composed from Material widgets. Custom painting is
platform-neutral — it renders identically on iOS with no changes.

**Every dependency supports iOS**, though three come with caveats (§A3):

| Package | iOS | Note |
|---|---|---|
| `http`, `shared_preferences`, `package_info_plus` | ✅ | no work |
| `cryptography` (Ed25519), `pointycastle` (SHA3-512) | ✅ | pure Dart — same code path |
| `cupertino_icons` | ✅ | already a dependency, currently unused |
| `flutter_secure_storage` | ⚠️ | works via Keychain, but the *semantics* differ — §A2.2 |
| `dynamic_color` | ⚠️ | returns `null` on iOS by design — §A2.1 |
| `home_widget` | ❌ | needs a Swift WidgetKit extension — §A3.1 |
| `workmanager` | ❌ | iOS background execution is not comparable — §A3.2 |

**Material You already has a working fallback.** `lib/main.dart` does
`lightDynamic ?? ColorScheme.fromSeed(seedColor: _fallbackSeed)`. On iOS both
dynamic schemes come back `null`, so it takes the seeded branch — which is the
*same branch Android 11 and earlier already take*, so it is exercised code, not
new code. The app will build and run and look correct.

**There is no platform branching anywhere in `lib/`.** `grep` for `Platform.is`
and `defaultTargetPlatform` returns nothing. That is good news — no Android
assumptions are baked into the Dart layer — but it also means the first
platform-aware code will be new, so decide where it belongs before scattering it
(recommendation: one `lib/src/platform.dart`, not `Platform.isIOS` sprinkled
through widgets).

## A2. What needs iOS-specific work

### A2.1 The look: Material 3 on an iPhone is a *decision*, not a bug

Because the fallback works, the app runs on iOS looking like a Material 3 app —
seeded palette, Material ripples, Android-style navigation. It functions
perfectly and looks faintly foreign.

**Decided: platform-adaptive polish.** Keep Material widgets and the custom
controls; adapt the handful of things that feel wrong on iOS. (The alternatives
considered and rejected: shipping it as plain Material, which is zero work and
can be revisited if the polish slips; and a full Cupertino variant, rejected
because it roughly doubles the UI surface to maintain for a cosmetic gain on
screen areas that are already custom-drawn.)

The adaptations, all of which belong behind one platform check rather than
scattered through widgets:
- Native swipe-back (`CupertinoPageRoute` instead of `MaterialPageRoute`)
- `BouncingScrollPhysics` rather than the Android glow/clamp
- iOS haptics via `HapticFeedback` (Android's vibration pattern feels wrong)
- `CupertinoSwitch` and `CupertinoActivityIndicator` where a bare Material
  switch/spinner reads as out of place
- Drop ripple splashes on iOS (`splashFactory: NoSplash`) — iOS uses opacity
- A fixed, deliberate seed colour, since there is no wallpaper to sample

### A2.2 Keychain semantics — the sharp one

`flutter_secure_storage` currently passes **no options** (no `IOSOptions`, no
`AndroidOptions`). On iOS the defaults matter more than on Android, for two
reasons that interact badly with this app's auth model:

**Keychain items survive app deletion.** On Android, uninstalling clears the
Ed25519 private key. On iOS it does *not* — delete Breeze, reinstall it, and the
old private key is still there. If that key was revoked server-side in the
meantime, the fresh install starts life authenticating with a dead key and gets
`401` forever, looking exactly like a broken install.

This is not hypothetical: there is a postmortem in this project about the app
deleting its Ed25519 key on *any* 401 and locking the household out. iOS creates
the mirror-image failure — a key that refuses to die.

Plan:
- Set `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device_only)`.
  `..._this_device_only` keeps the key out of iCloud Keychain and encrypted
  backups, so it cannot be restored onto a different device — which is the right
  security property for a device-bound credential *and* avoids a restored backup
  resurrecting a revoked key on new hardware.
- Detect resurrection explicitly. `shared_preferences` **is** cleared on
  uninstall while the Keychain is not, so a marker in prefs plus a key in the
  Keychain is a reliable "reinstalled over a stale credential" signal. On
  detecting it, discard the key and re-enrol rather than looping on 401.

**Decided: a reinstall drops the credential and re-enrols.** The resurrection
check above is therefore not a corner case but the mechanism — prefs-missing plus
key-present means "reinstalled", and the key is discarded rather than tried.

The trade-off, stated so it is not a surprise later: reinstalling costs one LAN
approval by an admin. That is friction the household has objected to before — it
is why the token TTL was pushed to 3650 days. The difference is that a TTL expiry
hits everyone on a schedule, whereas a reinstall is rare and deliberate. Keeping
the pairing was the alternative, and was rejected because it would let a revoked
device regain access simply by reinstalling, which makes revocation decorative.

**Note for later:** the Secure Enclave cannot hold Ed25519 keys — it only does
P-256. So the key lives in the Keychain as bytes, exactly as on Android. If
hardware-backed keys are ever wanted, that means a P-256 auth profile on the
server (an "auth v3"), which is a much larger conversation and explicitly out of
scope here.

### A2.3 App Transport Security and the Local Network prompt

Two separate iOS gates, both of which will silently break the app if missed:

**ATS blocks cleartext HTTP.** Breeze Core is plain HTTP on the LAN by default.
Happily, `ApiClient.normalizeUrl` already forces `https://` for public hosts and
permits `http://` only for loopback and RFC1918 addresses — which maps exactly
onto Apple's `NSAllowsLocalNetworking`. So the `Info.plist` needs:

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
```

That permits cleartext to local hostnames and private IPs while keeping ATS
enforced for everything else. Do **not** use `NSAllowsArbitraryLoads` — it
disables ATS globally, weakens the app, and invites App Review questions.

**Local Network permission is a runtime prompt.** Since iOS 14, any connection to
a local address requires user consent, and the app must declare why:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Breeze talks to your air conditioners and to Breeze Core on your
local network. Nothing leaves your home.</string>
```

Consequences worth designing for, because they have no Android equivalent:
- The prompt appears on the **first LAN connection attempt**, which will be
  mid-enrolment. Trigger it somewhere explicable (the scan screen) rather than
  letting it ambush the user during pairing.
- If the user declines, connections fail in ways that look like network errors.
  There is no API to query the permission state, so the diagnostics screen should
  name this possibility explicitly instead of reporting "unreachable".
- The **LAN port-scan discovery** feature is precisely what this gate exists to
  restrain. Expect it to work, but expect the prompt, and expect scanning to be
  slower than on Android.
- If Bonjour/mDNS discovery is ever added, that needs `NSBonjourServices` listing
  each service type, and multicast needs a *separate* entitlement Apple grants by
  request. Port scanning avoids both — an argument for keeping it.

## A3. What cannot come along

Stating these plainly is the point; each is a real feature Android users have.

### A3.1 The home screen widget — needs Swift, not just `home_widget`
The Android widget is a full `AppWidgetProvider` in Kotlin with its own
drawables, layouts and a config activity. `home_widget` supports iOS, but on iOS
the widget *itself* must be a **WidgetKit extension written in Swift**, sharing
data through an App Group. The Dart side (`home_widget_service.dart`) largely
carries over; the widget UI does not — it is a from-scratch SwiftUI rewrite, and
it cannot be built or previewed without a Mac.

Recommendation: **out of scope for v1.** Ship the app first.

### A3.2 Background refresh — not comparable
`workmanager` on Android runs a periodic task on a schedule. iOS has
`BGAppRefreshTask`: opportunistic, no guaranteed interval, throttled by usage
patterns, and suspended entirely for apps the user rarely opens. A widget that
must be fresh cannot rely on it.

Recommendation: on iOS, refresh on foreground and treat background updates as a
bonus. Do not promise a live widget.

### A3.3 Android Auto → there is no CarPlay equivalent
CarPlay entitlements are granted only for specific app categories — audio,
navigation, EV charging, parking, food ordering, driving-task apps. **Home
climate control is not one of them**, and Apple does not grant entitlements
outside those categories. This is a policy wall, not a technical one.

**Decided: App Intents / Siri Shortcuts are the iOS counterpart, and they are in
scope for the port** rather than being a consolation prize. "Hey Siri, set the
living room to 22" works from the car, the watch, the Lock Screen and the
Shortcuts app, with no entitlement and no driving-specific UI to maintain — and
it runs on-device, so it does not compromise the no-cloud premise. See
[VOICE.md in breeze-core](https://github.com/monikapurpl3/breeze-core/blob/main/docs/VOICE.md)
for why the Alexa and Google routes are excluded and what a local bridge would
involve.

### A3.4 Smaller absences
- **Quick Settings tile** — no equivalent; App Intents and Control Center widgets
  (iOS 18+) are the nearest thing.
- **Sideloading an APK** — the whole distribution model differs; see Part B.

## A4. Phasing, and what can be verified without a Mac

| Phase | Work | Verifiable on Windows? |
|---|---|---|
| 0 | `flutter create --platforms=ios .` to generate the runner; set bundle id, display name, deployment target (iOS 13+), icons | `flutter analyze`, `flutter test` ✅ — but not a build |
| 1 | `Info.plist`: ATS local networking, Local Network usage string, orientations | no — needs a compile |
| 2 | `IOSOptions` on secure storage + the reinstall-resurrection check (§A2.2) | logic is testable ✅ |
| 3 | `lib/src/platform.dart` + adaptive polish (§A2.1 option 2) | widget tests ✅, look no |
| 4 | CI: GitHub Actions `macos-latest`, `flutter build ios --no-codesign`, upload artifact | ✅ this *is* the verification |
| 5 | App Intents / Siri Shortcuts for the common actions — power, setpoint, mode, per unit (§A3.3) | intent definitions ✅, Siri no |
| 6 | Part B docs + README/bolero updates | ✅ |
| later | WidgetKit extension (§A3.1) | no |

**Phase 4 is the one that changes the situation.** GitHub's macOS runners are
free for public repositories, so a workflow that runs `flutter build ios
--no-codesign` on every tag gives compile-level proof and a downloadable
artifact, with no Mac and no developer account. That is the difference between
"iOS support, allegedly" and "iOS support, demonstrated". Do it before writing
any adaptive UI, so the port is proven to build before it is polished.

Golden-image tests are a caveat: font rasterisation differs between platforms, so
goldens generated on Windows may not match a macOS runner. Either keep goldens
platform-tagged or exclude them from the iOS job.

---

# Part B — build and ship it yourself

**For Apple-ecosystem users.** You do not need to be a developer, but you do need
a Mac. Total time: about half an hour, most of it downloads.

## What you need

- A **Mac** (Apple Silicon or Intel) running a recent macOS
- **Xcode** from the App Store — large, budget the download
- **Flutter** — <https://docs.flutter.dev/get-started/install/macos>
- An **Apple ID**. A free one is enough. A paid Developer Program membership
  ($99/yr) changes only how long the app lasts and how you distribute it
- Your iPhone and a **cable** for the first install

## Which tier do you want?

| Tier | Cost | App lasts | Notes |
|---|---|---|---|
| **Free Apple ID** | free | **7 days** | re-run the build weekly; up to 3 apps |
| **Paid, direct install** | $99/yr | 1 year | rebuild annually |
| **Paid, TestFlight** | $99/yr | 90 days/build | installs over the air, share with family; needs beta review |

**The project itself will not distribute an iOS build** — there is no paid Apple
Developer account and no plan for one, so there will be no TestFlight link and no
App Store listing. That is a deliberate decision, recorded so nobody waits for
something that is not coming.

The tiers above still apply to *you*: if you already have a paid account, nothing
stops you using TestFlight to get Breeze onto your own family's phones. For most
households the **free tier** is the right answer — one command a week.

## Build it

```bash
git clone https://github.com/monikapurpl3/breeze.git
cd breeze
flutter pub get
flutter doctor                 # resolve anything it flags before continuing
open ios/Runner.xcworkspace     # note: .xcworkspace, not .xcodeproj
```

In Xcode, once:

1. Select the **Runner** project → **Signing & Capabilities**
2. Tick **Automatically manage signing**
3. **Team** → add your Apple ID and select it
4. Change the **Bundle Identifier** to something unique to you — e.g.
   `com.yourname.breeze`. The default will collide with someone else's and
   signing will fail with an unhelpful message.
5. Plug in your iPhone, select it as the run target, press **▶**

On the phone, first run only: **Settings → General → VPN & Device Management →**
your Apple ID **→ Trust**. iOS will not run a self-signed app until you do, and
the failure looks like the app simply refusing to open.

Prefer the terminal:

```bash
flutter devices                        # find your phone's id
flutter run --release -d <device-id>   # or: flutter build ipa
```

## First launch

1. Breeze will ask for **Local Network** permission. **Allow it** — the app
   cannot reach your air conditioners or Breeze Core without it, and iOS gives no
   second prompt. If you tap Deny, fix it in Settings → Breeze → Local Network.
2. Enter your Breeze Core address (`http://192.168.x.x:8420`) and API key.
3. Approve the pairing **on the LAN**, per the Breeze Core docs — the pairing
   handshake is deliberately admin-approved and local-only.

## When the 7 days are up (free tier)

The app stops launching. Nothing is lost — reconnect the phone and press ▶
again, or `flutter run --release`. Your pairing and settings survive, because
they live in the iOS Keychain, which is not cleared by a reinstall.

## Sharing it with family (paid tier)

```bash
flutter build ipa
```

Then upload `build/ios/ipa/*.ipa` via **Xcode → Organizer** or **Transporter**,
and add testers in **App Store Connect → TestFlight**. Expect a short beta review
on the first build. TestFlight builds expire after 90 days.

## Differences from the Android app, on purpose

- **No CarPlay.** Apple grants CarPlay entitlements only to specific categories
  and home climate control is not among them. Siri Shortcuts are the intended
  substitute (see §A3.3).
- **No home screen widget**, initially — it requires a separate WidgetKit
  extension. Tracked, not forgotten.
- **No Material You colours.** iOS has no wallpaper-derived palette, so Breeze
  uses a fixed palette. Light/dark still follows the system.

## If something goes wrong

- **"Untrusted Developer"** → the Trust step above.
- **"Unable to install" / signing errors** → your bundle identifier is not
  unique. Change it (step 4).
- **The app opens but cannot find the server** → almost always Local Network
  permission. Check Settings → Breeze. Then confirm the phone is on the same
  subnet as Breeze Core and that you used `http://` with the port.
- **Everything returns 401** → the pairing needs approving on the LAN, or the
  credential was revoked server-side. See the Breeze Core troubleshooting doc,
  which explains which 401s are worth retrying and which are not.

Report anything else at <https://github.com/monikapurpl3/breeze/issues> — an iOS
build report is genuinely useful, since the maintainer cannot test on Apple
hardware.

---

## Decisions taken (2026-08-18)

Recorded here so the plan reads as settled rather than as a menu, and so the
reasoning survives longer than the conversation.

1. **Look: platform-adaptive polish** (§A2.1). Material widgets and the
   custom-painted controls stay; swipe-back, scroll physics, haptics, switches,
   splashes and the seed colour adapt. Plain Material was the cheap alternative
   and remains the fallback if the polish slips; a full Cupertino tree was
   rejected as double maintenance for a cosmetic gain.
2. **A reinstall drops the credential and re-enrols** (§A2.2). The
   prefs-cleared-but-Keychain-survives asymmetry is the detection mechanism.
   Costs one LAN approval on the rare occasion someone reinstalls; keeping the
   pairing was rejected because it would let a revoked device regain access by
   reinstalling, making revocation decorative.
3. **No paid Apple Developer account** (Part B). Users build it themselves on the
   free tier, and the docs say plainly that no TestFlight link is coming.
   Revisit only if enough people ask.
4. **Voice: App Intents / Siri Shortcuts, in scope for the port** (§A3.3). Local,
   no account, no entitlement, and it doubles as the CarPlay substitute. The
   heavier bridge options — HomeKit via HAP, or Matter for all four ecosystems at
   once — are written up in
   [breeze-core docs/VOICE.md](https://github.com/monikapurpl3/breeze-core/blob/main/docs/VOICE.md)
   and deliberately **not** committed to yet.

Still genuinely open, and worth deciding before Part A phase 1 rather than during
it: **which bundle identifier** the project standardises on. The Android
application id is `app.breeze.breeze`, which is fine for self-built installs but
is not a domain anyone here controls — irrelevant for free-tier sideloading,
relevant the moment an App Store listing is ever considered.
