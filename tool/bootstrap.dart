// Generates official Flutter native projects without replacing app source.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  try {
    await bootstrap();
  } on Object catch (error) {
    stderr.writeln('Bootstrap failed: $error');
    exitCode = 1;
  }
}

Future<void> bootstrap() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  final expectedVersion = RegExp(
    r"^  flutter: '([^']+)'$",
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (expectedVersion == null) {
    throw StateError('Pin the Flutter version in pubspec.yaml first.');
  }

  final versionResult = await runFlutter(root, ['--version', '--machine']);
  final version =
      jsonDecode(versionResult.stdout as String) as Map<String, dynamic>;
  if (version['frameworkVersion'] != expectedVersion) {
    throw StateError(
      'Use Flutter $expectedVersion; found ${version['frameworkVersion']}.',
    );
  }

  final missing = [
    'android',
    'ios',
  ].where((name) => !Directory('${root.path}/$name').existsSync()).toList();
  if (missing.isEmpty) {
    stdout.writeln('Native projects already exist; no files changed.');
    return;
  }

  final tooling = Directory('${root.path}/.tooling')..createSync();
  final staging = tooling.createTempSync('native-scaffold-');
  stdout.writeln(
    'Generating ${missing.join(', ')} with Flutter $expectedVersion.',
  );
  final result = await runFlutter(root, [
    'create',
    '--project-name',
    'roadeye',
    '--org',
    'com.roadeye',
    '--platforms',
    missing.join(','),
    '--no-pub',
    staging.path,
  ]);
  stdout.write(result.stdout);

  if (missing.contains('ios')) {
    final iosPath = '${staging.path}/ios';
    replaceRequired(
      File('$iosPath/Runner/Info.plist'),
      RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
      (match) =>
          '${match[1]}RoadEye${match[2]}\n\t<key>NSCameraUsageDescription</key>\n\t<string>RoadEye requires camera access to detect road damage in real-time.</string>',
    );
    replaceRequired(
      File('$iosPath/Runner.xcodeproj/project.pbxproj'),
      RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;'),
      (_) => 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;',
    );
    final podfile = File('$iosPath/Podfile');
    if (podfile.existsSync()) {
      replaceRequired(
        podfile,
        RegExp(r"^\s*#?\s*platform :ios, '[^']+'", multiLine: true),
        (_) => "platform :ios, '16.0'",
      );
    }
  }
  if (missing.contains('android')) {
    replaceRequired(
      File('${staging.path}/android/app/src/main/AndroidManifest.xml'),
      RegExp(r'<application'),
      (_) =>
          '<uses-permission android:name="android.permission.CAMERA" />\n    <uses-feature android:name="android.hardware.camera" android:required="false" />\n    <application',
    );
    replaceRequired(
      File('${staging.path}/android/app/src/main/AndroidManifest.xml'),
      RegExp(r'android:label="[^"]+"'),
      (_) => 'android:label="RoadEye"',
    );
    final gradleProps = File('${staging.path}/android/gradle.properties');
    if (gradleProps.existsSync()) {
      gradleProps.writeAsStringSync(
        '${gradleProps.readAsStringSync()}\nkotlin.jvm.target.validation.mode=warning\n',
      );
    }
  }

  // Move only new native directories within the repository. Existing projects
  // and app source are never overwritten; staging files remain for inspection.
  for (final name in missing) {
    final destination = '${root.path}/$name';
    if (FileSystemEntity.typeSync(destination) !=
        FileSystemEntityType.notFound) {
      throw StateError('$destination appeared during generation; stopping.');
    }
    Directory('${staging.path}/$name').renameSync(destination);
  }
  final metadata = File('${root.path}/.metadata');
  if (!metadata.existsSync()) {
    File('${staging.path}/.metadata').copySync(metadata.path);
  }
  stdout.writeln('Native projects ready. App source and AGENTS.md preserved.');
}

Future<ProcessResult> runFlutter(Directory root, List<String> args) async {
  final result = await Process.run(
    'flutter',
    args,
    workingDirectory: root.path,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'flutter',
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

void replaceRequired(
  File file,
  RegExp pattern,
  String Function(Match) replacement,
) {
  final content = file.readAsStringSync();
  if (!pattern.hasMatch(content)) {
    throw StateError('Flutter template changed: check ${file.path}.');
  }
  file.writeAsStringSync(content.replaceAllMapped(pattern, replacement));
}
