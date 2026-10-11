# RoadEye agent handoff

Updated: **2026-10-12**. Read this file and `AGENTS.md` before continuing work.
Update this document after significant changes or before ending a work session.

## User objective and constraints

- Flutter app supporting Android and iOS.
- First milestone: a minimal **release** app installed through AltStore Classic
  that opens on an **iPhone X with iOS 16.7.16**.
- Windows 10 development PC: i3-8145U, 12 GB RAM, Intel UHD.
- C: HDD has space; D: SSD has only 17.1 GB free. Put tools/caches on C:.
- Training: Colab with prepared RDD2022 data. Initial model: YOLO11n.
- iOS compilation: GitHub Actions macOS runner; personal installation: AltStore.
- Ask explicitly before deleting existing files/directories or discarding work.
  Do not modify the existing `AGENTS.md` unless the user requests it.

## Implemented

- `pubspec.yaml`: app `roadeye`, version `0.1.0+1`, Flutter pinned to 3.47.6.
- `lib/`: offline launch screen, safe-area/scrolling layout, and a Check app
  button with a visible status change and accessibility announcement.
- `test/launch_screen_test.dart`: launch, repeated interaction, and layout at
  iPhone X dimensions and smaller dimensions with 200% text scaling.
- `tool/bootstrap.dart`: version-checked native generation using official
  Flutter templates. Creates missing Android/iOS projects, applies RoadEye
  display names and iOS 16.0 deployment target, preserves existing projects.
- `.github/workflows/mobile-release.yml`: formatting/analysis/tests, unsigned
  iOS release IPA packaging, OS/arm64 checks, Android release APK, and artifacts.
- `README.md`, `docs/SETUP.md`, and `docs/IPHONE_INSTALL.md`: development and
  installation instructions.
- `.gitignore`: caches, local configuration, signing secrets, and training data.

The UI honestly states that camera and detection arrive in the next milestone.
There are no inference packages, model assets, camera permissions, or credentials.
Generated launcher icons are placeholders until custom branding is requested.

## Validation and environment limitations

File read/write access in the project is working now. Earlier attempts to
change the shell's current directory returned Access denied; use absolute
paths when diagnosing this environment. Do not broaden permissions blindly.

Flutter and Dart are not available on PATH in this agent session. During file
review, `pubspec.lock` and `.dart_tool/package_config.json` appeared; their
generator metadata reports Flutter 3.47.6, Dart 3.13.5, and host SDK location
`C:\Users\QCU\flutter`. Direct access to that SDK returns Access denied. The
pin was aligned with that version; its official Flutter Git tag was verified.
A bounded HTTPS attempt to SDK storage also failed because outbound shell
networking is restricted. No SDK was downloaded or installed by this agent.
Do not claim Flutter analysis, formatting, widget tests, or builds have passed.

Static repository checks passed: 15 required files exist, local Markdown links
and Dart relative imports resolve, the Flutter pin and release workflow steps
are present, and `AGENTS.md` retains its original 2,817-byte size. These checks
do not parse or execute Dart or validate a release binary. The bootstrap's iOS
display-name and deployment-target patterns were reviewed against the official
[3.47.6 Info.plist template](https://raw.githubusercontent.com/flutter/flutter/3.47.6/packages/flutter_tools/templates/app/ios.tmpl/Runner/Info.plist.tmpl)
and [Xcode project template](https://raw.githubusercontent.com/flutter/flutter/3.47.6/packages/flutter_tools/templates/app/ios.tmpl/Runner.xcodeproj/project.pbxproj.tmpl).

Native `android/` and `ios/` directories have not been generated locally.
The host-generated `pubspec.lock` is preserved and should be validated with
`flutter pub get`. The bootstrap script runs automatically in both release
jobs, so a source-only initial checkout can be built without manually creating
an Xcode project. No GitHub remote, Actions run, IPA, APK, or iPhone installation
has been produced or verified yet. The first milestone remains unconfirmed.

## Next actions, in order

1. Make Flutter 3.47.6 executable in the sandbox (the host SDK path is above),
   or upload this repository to GitHub
   and run **Mobile release**. GitHub access is not configured in this session.
2. Run `flutter pub get`, `dart run tool/bootstrap.dart`, `dart format lib test
   tool`, `flutter analyze`, and `flutter test`; resolve actual failures.
3. Review and commit generated native projects, `.metadata`, formatted Dart
   source, and `pubspec.lock`. CI artifacts preserve these for the first run.
   Bootstrap leaves existing native projects untouched on later runs.
4. Confirm the release workflow creates an IPA and APK. Record the workflow
   URL and result below. CI currently formats its working copy; after the first
   formatting commit, change it to enforce formatting rather than apply it.
5. Have the user install the IPA through AltStore and complete the checklist in
   `docs/IPHONE_INSTALL.md`. Record results; only then mark milestone one done.
6. Next milestone: camera preview and permissions, then a single-image
   inference path. Choose/export a mobile-compatible YOLO11n artifact only
   after confirming the Flutter runtime and iPhone X compatibility. Keep
   training in Colab and document preprocessing, class mapping, and thresholds.

## Results to fill in

| Check | Current result |
| --- | --- |
| Local static file checks | Passed: files, links, imports, pin, workflow structure |
| Dart formatting / analysis | Not run: sandbox denies host SDK access |
| Flutter widget tests | Not run: sandbox denies host SDK access |
| Android release build | Not run |
| iOS release build / IPA packaging | Not run |
| GitHub repository / workflow URL | Not configured |
| iPhone installation and restart | Not tested |

Keep this table factual. Preserve completed work and report remaining blockers
instead of restarting the project or declaring device success from CI alone.
