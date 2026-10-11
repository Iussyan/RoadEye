# RoadEye — Project Analysis

> **Last updated:** 2026-10-12  
> **Analyst:** Antigravity agent (initial deep-read pass)  
> **Purpose:** Persistent context document for agents and contributors. Update after significant changes.

---

## 1. Project Identity

| Field | Value |
|---|---|
| App name | `roadeye` (package) / **RoadEye** (display) |
| Version | `0.1.0+1` |
| Framework | Flutter **3.47.6** stable (pinned) |
| Dart SDK | `>=3.8.0 <4.0.0` (resolved: Dart 3.13.5 from host lock) |
| Platform | Android + iOS |
| Target device | iPhone X, iOS 16.7.16 |
| Bundle ID | `com.roadeye` |
| iOS min target | 16.0 (set by bootstrap) |

---

## 2. Purpose & Scope

RoadEye is a **road-damage detection mobile app** built with Flutter. The end goal is to run a YOLO11n model on live camera frames to identify road damage. The project is currently at **Milestone 1** — a minimal launch screen that proves the app installs and opens on the target iPhone.

**What exists now:**
- Offline launch screen with a branded UI
- "Check app" button that switches status text (proves interactivity)
- Full CI/CD pipeline (GitHub Actions)
- Bootstrap tooling to generate native projects on any OS
- Installation guide for AltStore on Windows → iPhone

**What does NOT exist yet:**
- Camera access or permissions
- YOLO/ML model or inference pipeline
- Any native plugin dependencies
- Custom launcher icons (placeholder Flutter icons)
- A confirmed GitHub remote or completed CI run
- A verified iPhone installation

---

## 3. Repository File Map

```
RoadEye/
├── lib/
│   ├── main.dart                          # Entry point → runApp(RoadEyeApp())
│   ├── app.dart                           # MaterialApp, theme, seed color #234E45
│   └── features/
│       └── launch/
│           └── launch_screen.dart         # Only screen; StatefulWidget; _checkPassed bool
├── test/
│   └── launch_screen_test.dart            # 3 widget tests (launch, repeated tap, small screens)
├── tool/
│   └── bootstrap.dart                     # Native project generator (safe, idempotent)
├── docs/
│   ├── HANDOFF.md                         # Agent handoff + validation table (keep updated)
│   ├── SETUP.md                           # Windows dev setup steps
│   └── IPHONE_INSTALL.md                  # AltStore installation + milestone checklist
├── .github/
│   └── workflows/
│       └── mobile-release.yml             # CI: checks → ios build → android build
├── pubspec.yaml                           # Minimal deps; Flutter pinned to 3.47.6
├── pubspec.lock                           # Resolved by host Flutter; committed
├── analysis_options.yaml                  # Extends flutter_lints; excludes build/ and web/
├── AGENTS.md                              # Agent rules (do NOT modify without user approval)
├── README.md                              # Quick-start and layout map
└── .gitignore                             # Excludes caches, signing secrets, datasets, IPAs
```

> **Note:** `android/` and `ios/` native directories do **not exist yet** in source. They are generated on-demand by `tool/bootstrap.dart`.

---

## 4. Architecture

### App Layer
The app is a single-screen Flutter application with no routing, no state management library, and no external runtime dependencies.

```
main() → RoadEyeApp (StatelessWidget, MaterialApp)
           └── LaunchScreen (StatefulWidget)
                 └── _LaunchScreenState
                       ├── bool _checkPassed
                       └── FilledButton → setState(_checkPassed = true)
```

### Theme
- Material 3 (`useMaterial3: true`)
- Seed color: `#234E45` (deep forest green)
- Scaffold background: `#F5F6F2` (off-white)
- Dark card: `#163D35` with `#D7EF9A` lime-green accent

### Accessibility
- Status text wrapped in `Semantics(liveRegion: true)` → screen-reader announcement on state change
- `ValueKey('app-check-status')` on the status text for testability

---

## 5. Dependencies

### Runtime
| Package | Source | Notes |
|---|---|---|
| `flutter` | SDK | Only runtime dep |

### Dev
| Package | Version | Purpose |
|---|---|---|
| `flutter_test` | SDK | Widget testing |
| `flutter_lints` | `^6.0.0` (resolved: 6.0.0) | Lint rules |

**No third-party runtime packages.** The app is intentionally minimal for Milestone 1.

---

## 6. Bootstrap Script (`tool/bootstrap.dart`)

Key behaviors:
- **Version gate:** Reads the pinned Flutter version from `pubspec.yaml`. Fails if the active SDK version doesn't match exactly.
- **Idempotent:** If `android/` and `ios/` already exist, it exits cleanly with no changes.
- **Safe staging:** Generates native projects in `.tooling/native-scaffold-<tmp>/`, then moves only missing directories into the repo root.
- **iOS customizations applied:**
  - `CFBundleDisplayName` → `RoadEye` in `Info.plist`
  - `IPHONEOS_DEPLOYMENT_TARGET` → `16.0` in `project.pbxproj`
  - `MinimumOSVersion` → `16.0` in `AppFrameworkInfo.plist`
  - `platform :ios, '16.0'` in `Podfile`
- **Android customizations applied:**
  - `android:label` → `"RoadEye"` in `AndroidManifest.xml`
- Uses `replaceRequired()` — throws `StateError` if the expected pattern is missing (guards against Flutter template changes).

---

## 7. CI/CD Pipeline (`.github/workflows/mobile-release.yml`)

### Triggers
- `workflow_dispatch` (manual)
- Push to `main` or `master`
- Pull requests to `main` or `master`

### Jobs

```
checks (ubuntu-latest, 20 min)
  → flutter pub get
  → dart format lib test tool
  → flutter analyze
  → flutter test
  → upload: RoadEye-source-<run> (lib/, test/, tool/, pubspec.lock) [14 days]

ios (macos-15, 40 min) [skipped on PRs]
  needs: checks
  → flutter pub get
  → dart run tool/bootstrap.dart
  → flutter build ios --release --no-codesign
  → verify MinimumOSVersion <= 16.7.16 (Python assert)
  → verify arm64 arch with lipo
  → package: Payload/Runner.app → RoadEye-unsigned.ipa
  → sha256 checksum
  → upload: RoadEye-iOS-<run> (IPA, sha256, pubspec.lock, .metadata, ios/, android/) [14 days]

android (ubuntu-latest, 30 min) [skipped on PRs]
  needs: checks
  → JDK 17 (temurin)
  → flutter pub get
  → dart run tool/bootstrap.dart
  → flutter build apk --release
  → upload: RoadEye-Android-<run> (app-release.apk) [14 days]
```

> **Important:** CI currently runs `dart format` (applies changes). After the first formatting commit, switch to `dart format --output=none --set-exit-if-changed` to enforce instead of auto-apply.

---

## 8. Tests

File: `test/launch_screen_test.dart`

| Test | What it checks |
|---|---|
| `launches and responds to repeated app checks` | Initial text present, button tap changes status, second tap doesn't throw |
| `supports 375×812 with large text` | iPhone X dimensions, 2× text scale, button works |
| `supports 320×568 with large text` | Small phone dimensions, 2× text scale, button works |

All 3 tests cover the Milestone 1 acceptance criteria.

---

## 9. Development Environment

| Item | Detail |
|---|---|
| Dev OS | Windows 10 |
| CPU | Intel i3-8145U |
| RAM | 12 GB |
| Storage | C: HDD (tools/caches here), D: SSD (17.1 GB free only) |
| Host Flutter path | `C:\Users\QCU\flutter` |
| iOS compilation | GitHub Actions macOS 15 runner only (not possible on Windows) |
| Android builds | Windows with Android SDK or Ubuntu CI |
| iPhone sideloading | AltStore Classic + AltServer on Windows |

### Key environment constraints
- `cd` commands may fail with "Access denied" in agent shells — always use **absolute paths**.
- Flutter SDK is not on PATH in agent sandboxes. Do not claim builds/tests passed unless run on the host or CI.
- Keep all tooling caches on C:. Set `PUB_CACHE=C:\dev\pub-cache` and `GRADLE_USER_HOME=C:\dev\gradle-cache` if needed.

---

## 10. Milestone Status

### Milestone 1 — Install and launch on iPhone X ❌ Not yet confirmed

| Check | Status |
|---|---|
| Static file checks (links, imports, pin, structure) | ✅ Passed |
| Dart formatting / analysis | ⏳ Not run (no SDK in agent sandbox) |
| Flutter widget tests | ⏳ Not run (no SDK in agent sandbox) |
| Android release build | ⏳ Not run |
| iOS release build / IPA packaging | ⏳ Not run |
| GitHub repository / workflow URL | ❌ Not configured |
| iPhone installation and restart | ❌ Not tested |

### Milestone 2 — Camera preview (future)
- Add `camera` package
- Request camera permissions (iOS `Info.plist`, Android `AndroidManifest.xml`)
- Display live camera preview

### Milestone 3 — YOLO inference (future)
- Train YOLO11n in Colab on RDD2022 dataset
- Export to a mobile-compatible format (TFLite or CoreML)
- Add inference pipeline in Flutter
- Document preprocessing, class mapping, and confidence thresholds

---

## 11. Ordered Next Actions

1. **Verify Flutter on host** — run `flutter --version` in a terminal. Confirm it reports `3.47.6`. SDK is at `C:\Users\QCU\flutter`.
2. **Run local checks:**
   ```powershell
   flutter pub get
   dart run tool/bootstrap.dart
   dart format lib test tool
   flutter analyze
   flutter test
   ```
3. **Commit generated files** — `android/`, `ios/`, `.metadata`, formatted Dart source, `pubspec.lock`.
4. **Create GitHub remote** — push repository, trigger **Actions → Mobile release → Run workflow**.
5. **Install IPA via AltStore** — follow `docs/IPHONE_INSTALL.md`. Complete milestone checklist.
6. **Record results in `docs/HANDOFF.md`** — fill in the validation table with real outcomes.
7. **After formatting commit** — change CI `dart format lib test tool` → `dart format --output=none --set-exit-if-changed lib test tool`.
8. **Milestone 2** — add camera package and permissions only after Milestone 1 is fully confirmed on device.

---

## 12. Key Rules for Agents

- **Never delete files/directories** without listing exact paths + reason and getting explicit user approval.
- **Never modify `AGENTS.md`** unless the user explicitly requests it.
- **Never claim tests or builds passed** unless they actually ran on the host or CI.
- **Always use absolute paths** when running commands (agent shell `cd` may fail).
- Keep credentials, signing secrets, and datasets **out of source control**.
- The `pubspec.lock` is committed and should be preserved.
- `.tooling/` staging directory is git-ignored; do not delete without user approval.
- Bootstrap is idempotent — safe to run multiple times.
- IPA files are git-ignored. They live in CI artifacts only.

---

## 13. Color & Style Reference

| Token | Hex | Usage |
|---|---|---|
| Seed / primary | `#234E45` | Theme seed, primary color generation |
| Dark card bg | `#163D35` | Info card background |
| Lime accent | `#D7EF9A` | Button bg, status text color |
| Card text | `#DFEBE5` | Body text on dark card |
| Scaffold bg | `#F5F6F2` | Page background |
