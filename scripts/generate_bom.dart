// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pub_semver/src/version.dart';

import 'bom_analysis.dart';

const packagesDir = 'packages';
const versionsFile = 'VERSIONS.md';
const versionsJsonFile = 'scripts/versions.json';
const androidVersionFile =
    '$packagesDir/firebase_core/firebase_core/android/gradle.properties';
const iosVersionFile =
    '$packagesDir/firebase_core/firebase_core/ios/firebase_sdk_version.rb';
const webVersionFile =
    '$packagesDir/firebase_core/firebase_core_web/lib/src/firebase_sdk_version.dart';
const windowsVersionFile =
    '$packagesDir/firebase_core/firebase_core/windows/CMakeLists.txt';

const jsonEncoder = JsonEncoder.withIndent('  ');

void main(List<String> arguments) async {
  final suggestedVersion = await getBoMNextVersion();
  if (suggestedVersion == null) {
    print('No changes detected');
    return;
  }
  stdout.write('New BoM version number ($suggestedVersion): ');
  final readData = stdin.readLineSync()?.trim() ?? '';
  String version = readData.isEmpty ? suggestedVersion : readData;
  String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // Fetch native versions
  String androidSdkVersion = await getSdkVersion(
    androidVersionFile,
    'FirebaseSDKVersion=(.+)',
  );

  String iosSdkVersion = await getSdkVersion(
    iosVersionFile,
    r"def firebase_sdk_version!\(\)\s*'(.+)'",
  );

  String webSdkVersion = await getSdkVersion(
    webVersionFile,
    "const String supportedFirebaseJsSdkVersion = '(.+)'",
  );

  String windowsSdkVersion = await getSdkVersion(
    windowsVersionFile,
    r'set\(FIREBASE_SDK_VERSION "(.+)"\)',
  );

  // Read current versions JSON file
  File currentVersionsJson = File(versionsJsonFile);
  Map<String, dynamic> currentVersions =
      jsonDecode(currentVersionsJson.readAsStringSync());

  // Create JSON data
  Map<String, Map<String, Object>> jsonData = <String, Map<String, Object>>{
    version: {
      'date': date,
      'firebase_sdk': {
        'android': androidSdkVersion,
        'ios': iosSdkVersion,
        'web': webSdkVersion,
        'windows': windowsSdkVersion,
      },
      'packages': (await getPackagesUsingMelos()).map((key, value) {
        return MapEntry(key, value.toString());
      }),
    },
  };

  // Write JSON to file
  File versionsJson = File(versionsJsonFile);
  versionsJson.writeAsStringSync(
    jsonEncoder.convert({
      ...jsonData,
      ...currentVersions,
    }),
    flush: true,
  );

  print('JSON version data has been successfully written to $versionsJsonFile');

  // Append static text part to beginning of the document
  await appendStaticText(
    version,
    date,
    androidSdkVersion,
    iosSdkVersion,
    webSdkVersion,
    windowsSdkVersion,
  );

  print('Version $version has been generated successfully!');

  // Commit the files and create an annotated tag and a commit
  Process.runSync('git', ['add', versionsFile, versionsJsonFile]);
  Process.runSync(
    'git',
    ['tag', '-a', 'BoM-v$version', '-m', 'BoM Version $version'],
  );
  Process.runSync('git', ['commit', '-m', 'chore: BoM Version $version']);
}

Future<String> getSdkVersion(
  String versionFile,
  String pattern,
) async {
  RegExp regex = RegExp(pattern);
  String fileContents = await File(versionFile).readAsString();
  Match? match = regex.firstMatch(fileContents);
  return match?.group(1)?.trim() ?? 'Version not found';
}

Future<Map<String, Version>> getPackagesUsingMelos() async {
  final workspace = await getMelosWorkspace();

  final currentPackageNameAndVersionsMap = workspace.filteredPackages.values
      .map((package) => {package.name: package.version})
      .reduce((value, element) => value..addAll(element));

  return currentPackageNameAndVersionsMap;
}

Future<void> appendStaticText(
  String? version,
  String date,
  String androidSdkVersion,
  String iosSdkVersion,
  String webSdkVersion,
  String windowsSdkVersion,
) async {
  File currentContent = File(versionsFile);
  String content = currentContent.readAsStringSync();

  // Removing previous header
  String pattern =
      '# FlutterFire Compatible Versions\r?\n\r?\nThis document is listing all the compatible versions of the FlutterFire plugins. This document is updated whenever a new version of the FlutterFire plugins is released.\r?\n\r?\n# Versions';
  content = content.replaceAll(RegExp(pattern), '');

  // Opening the file in append mode
  IOSink sink = File(versionsFile).openWrite();

  // Writing static text and version information
  sink.writeln('# FlutterFire Compatible Versions');
  sink.writeln();
  sink.writeln(
    'This document is listing all the compatible versions of the FlutterFire plugins. This document is updated whenever a new version of the FlutterFire plugins is released.',
  );
  sink.writeln();
  sink.writeln('# Versions');
  sink.writeln();
  sink.writeln(
    '## [Flutter BoM $version ($date)](https://github.com/firebase/flutterfire/blob/master/CHANGELOG.md#$date)',
  );
  sink.writeln();
  sink.writeln('<!--- When ready can be included');
  sink.writeln('Install this version using FlutterFire CLI');
  sink.writeln();
  sink.writeln('```bash');
  sink.writeln('flutterfire install $version');
  sink.writeln('```');
  sink.writeln('-->');
  sink.writeln();
  sink.writeln('### Included Native Firebase SDK Versions');
  sink.writeln('| Firebase SDK | Version | Link |');
  sink.writeln('|--------------|---------|------|');
  sink.writeln(
    '| Android SDK | $androidSdkVersion | [Release Notes](https://firebase.google.com/support/release-notes/android) |',
  );
  sink.writeln(
    '| iOS SDK | $iosSdkVersion | [Release Notes](https://firebase.google.com/support/release-notes/ios) |',
  );
  sink.writeln(
    '| Web SDK | $webSdkVersion | [Release Notes](https://firebase.google.com/support/release-notes/js) |',
  );
  sink.writeln(
    '| Windows SDK | $windowsSdkVersion | [Release Notes](https://firebase.google.com/support/release-notes/cpp-relnotes) |',
  );
  sink.writeln();
  sink.writeln('### FlutterFire Plugin Versions');
  sink.writeln('| Plugin | Version |');
  sink.writeln('|--------|---------|');

  final packages = await getPackagesUsingMelos();

  // Adding rows for each package
  for (final package in packages.entries) {
    sink.writeln(
      '| [${package.key}](https://pub.dev/packages/${package.key}/versions/${package.value}) | ${package.value} |',
    );
  }

  // Write the rest of the content
  sink.write(content);

  // Closing the sink to flush all data to the file
  await sink.flush();
  await sink.close();
}
