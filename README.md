# RoadEye

For standalone Python webcam/video detection with the existing model, see
[Python real-time detector](docs/PYTHON_DETECTOR.md).

Flutter prototype for detecting road damage on Android and iOS. The first
milestone is an app that installs and opens on an **iPhone X, iOS 16.7.16**.

The app includes live camera detection, photo inspection, and a saved-snapshot
gallery using the bundled YOLOv8 Small RDD TFLite model. Live inference runs in a
background isolate so the preview does not wait for each prediction. See
[in-app detection and validation](docs/APP_DETECTION.md) for usage and limitations.

## Start here

- [Windows setup and building](docs/SETUP.md)
- [Installing on the iPhone](docs/IPHONE_INSTALL.md)
- [Agent handoff and current validation status](docs/HANDOFF.md)
- [Contributor rules](AGENTS.md)

## Quick start

Use Flutter **3.47.6** and put its `bin` directory on PATH. From this folder:

```powershell
flutter pub get
dart run tool/bootstrap.dart
dart format lib test tool
flutter analyze
flutter test
flutter devices
flutter run -d <android-device-id>
```

The native `android/` and `ios/` projects are generated from official Flutter
templates by the bootstrap script. It preserves existing native projects,
application source, and `AGENTS.md`. iOS builds run on macOS, not Windows.

## Release artifacts

Upload this repository to GitHub, then run **Actions → Mobile release → Run
workflow**. Pushes to `main` or `master` also run the workflow. Pull requests run
formatting, analysis, and tests only.

After checks pass, the workflow builds an unsigned iOS release app, packages
`RoadEye-unsigned.ipa`, and builds an Android release APK. The IPA is intended
for signing and installation with AltStore Classic, not App Store distribution.
Download the iOS artifact ZIP and extract the IPA before importing it into
AltStore. The ZIP also includes a native project snapshot and dependency lock.

The `RoadEye-source-*` artifact contains formatted Dart source and
`pubspec.lock`. After the first successful run, review and commit the formatted
files, lockfile, `.metadata`, and native projects to make subsequent builds
reproducible. Do not copy generated caches or machine-specific configuration.

## Layout

```text
lib/main.dart                       App entry point
lib/app.dart                        Theme and root widget
lib/features/launch/launch_screen.dart  Launch screen and interaction
test/launch_screen_test.dart         Interaction and small-screen checks
tool/bootstrap.dart                 Native project generation
.github/workflows/mobile-release.yml  Checks and release builds
docs/                               Setup, installation, and handoff
```

Use Flutter 3.47.6. See the handoff for the latest validation results; desktop
unit/widget checks do not establish native inference or iPhone performance.
