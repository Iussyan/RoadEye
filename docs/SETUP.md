# Development setup

## Target environment

Windows 10, Intel i3-8145U, 12 GB RAM, and Intel UHD graphics. Use C: for tools
and caches: its HDD has room, while D: has only about 17.1 GB free. Prefer a
physical Android device over an emulator on this machine. The first iOS test
device is an iPhone X running iOS 16.7.16.

## Install Flutter on Windows

1. Use the existing Flutter installation if `flutter --version` reports
   **3.47.6**. Otherwise download Flutter **3.47.6 stable** from the
   [official SDK archive](https://docs.flutter.dev/install/archive).
2. If downloading, extract to a user-writable folder on C:, such as `C:\dev\flutter`.
3. Add the installation's `bin` folder to your user PATH and reopen the terminal.
   Host package metadata currently points to `C:\Users\QCU\flutter`.
4. Run `flutter --version` and `flutter doctor -v`.
5. For local Android builds, install the Android SDK and a compatible JDK using
   the [Flutter Android setup guide](https://docs.flutter.dev/platform-integration/android/setup).
   Keep their downloads and caches on C:. Accept licenses with
   `flutter doctor --android-licenses`.

An Android SDK is not needed to edit Dart or run widget tests. Missing Xcode on
Windows is expected; compile iOS through GitHub Actions.

Optional session settings to keep caches on C: (create these folders first):

```powershell
$env:PUB_CACHE = 'C:\dev\pub-cache'
$env:GRADLE_USER_HOME = 'C:\dev\gradle-cache'
```

## Prepare and check the project

```powershell
Set-Location 'C:\Users\QCU\Documents\RoadEye'
flutter pub get
dart run tool/bootstrap.dart
dart format lib test tool
flutter analyze
flutter test
```

Bootstrap checks the exact Flutter version pinned in `pubspec.yaml`, creates
missing native projects in `.tooling/`, and moves only those new projects into
the repository. It sets the app display name to RoadEye and the iOS deployment
target to **16.0**. Existing native directories are left untouched. Retained
staging files are ignored by Git; do not delete them without user approval.

After generation, review and commit `android/`, `ios/`, `.metadata`, and
`pubspec.lock`. Keep the generated placeholder Flutter launcher icons for the
launch milestone; custom branding can follow later.

## Run or build Android

```powershell
flutter devices
flutter run -d <android-device-id>
flutter build apk --release
```

The APK is at `build/app/outputs/flutter-apk/app-release.apk`. The template's
release build uses a development signing key; configure private production
signing before any store release.

## GitHub Actions

Create a GitHub repository and upload the project files including `.github/`.
No remote repository or GitHub workflow has been created by this agent.

The workflow installs the pinned Flutter version from `pubspec.yaml`. Linux
runs formatting, analysis, and widget tests. macOS 15 builds iOS, verifies the
app's minimum OS against 16.7.16 and its executable's arm64 architecture, then
packages `Payload/Runner.app` into an IPA. Android builds use JDK 17 on Linux.
Artifacts expire after 14 days; download them promptly.

No Apple account credentials, signing certificate, or paid developer account
is required by this unsigned build workflow. AltStore handles personal signing
on the user's devices. This pipeline does not publish to a store.

If generation fails with a template-change message, inspect the pinned Flutter
template and update `tool/bootstrap.dart`; do not overwrite existing native
projects. If CI formatting changes files, review the source artifact and commit
those changes. Once the initial source is formatted, consider enforcing
`dart format --output=none --set-exit-if-changed lib test tool` in CI.
