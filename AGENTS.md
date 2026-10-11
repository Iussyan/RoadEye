# Repository Guidelines

## Project Scope
RoadEye is a Flutter road-damage detection prototype for Android and iOS. The first milestone is a minimal release app that opens on an iPhone X running iOS 16.7.16. Add camera access and model inference after installation and launch are verified. Train the initial YOLO11n model in Colab using prepared RDD2022 data.

## Project Structure & Module Organization
The workspace has not yet been scaffolded. Use the following layout when creating the Flutter project:
- `lib/`: Dart application code; keep `main.dart` focused on startup.
- `test/`: unit and widget tests, matching source modules.
- `integration_test/`: device-level tests when required.
- `assets/`: bundled images and exported inference models; register assets in `pubspec.yaml`.
- `android/` and `ios/`: native platform configuration.
- `.github/workflows/`: GitHub Actions build workflows.

Keep training datasets and generated build outputs out of version control.

## Build, Test, and Development Commands
Run these commands from the repository root after Flutter scaffolding exists:
- `flutter pub get`: resolve dependencies.
- `dart format .`: format Dart source files.
- `flutter analyze`: run static analysis.
- `flutter test`: run unit and widget tests.
- `flutter run -d <device-id>`: launch on an available supported device.
- `flutter build apk --release`: build an Android release APK.
- `flutter build ios --release --no-codesign`: build the iOS app on a macOS runner for subsequent IPA packaging and AltStore signing.

Windows cannot compile the iOS app; use GitHub Actions macOS builds.

## Coding Style & Naming Conventions
Use Dart formatting with two-space indentation. Name files `lower_snake_case.dart`, classes `UpperCamelCase`, and members `lowerCamelCase`. Prefer small widgets and explicit types at module boundaries. Use Flutter lint rules when the project is scaffolded.

## Testing Guidelines
Use `flutter_test` for unit and widget tests, with filenames ending in `_test.dart`. Cover meaningful behavior and bug fixes. No numerical coverage target is established. For milestone one, verify installation, launch, and reopening after a phone restart on the actual iPhone.

## Commit & Pull Request Guidelines
No Git history was available to establish existing conventions. Use concise imperative messages, such as `Add minimal RoadEye launch screen`. PRs should describe behavior changes, link relevant issues, record validation, and include screenshots for visible UI changes.

## Agent Safety & Configuration
Before deleting any existing file or directory, list the exact paths and reason, then wait for explicit user approval. Obtain approval before destructive Git commands or discarding existing work. Keep credentials, signing secrets, and personal data out of source control.
