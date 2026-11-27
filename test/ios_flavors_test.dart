import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS flavors must stay in step with the Android productFlavors (same ids,
/// same names) and with codemagic.yaml. There is no Mac here, so these file
/// checks are what keeps a broken iOS project from waiting for a cloud build.
void main() {
  const flavors = ['dev', 'staging', 'prod'];
  const modes = ['Debug', 'Release', 'Profile'];

  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final codemagic = File('codemagic.yaml').readAsStringSync();

  String androidId(String flavor) {
    final base = RegExp(r'applicationId = "([^"]+)"')
        .firstMatch(gradle)!
        .group(1)!;
    final block = RegExp('create\\("$flavor"\\) \\{([^}]*)\\}')
        .firstMatch(gradle)!
        .group(1)!;
    final suffix = RegExp(r'applicationIdSuffix = "([^"]+)"')
        .firstMatch(block)
        ?.group(1);
    return base + (suffix ?? '');
  }

  String androidName(String flavor) {
    final block = RegExp('create\\("$flavor"\\) \\{([^}]*)\\}')
        .firstMatch(gradle)!
        .group(1)!;
    return RegExp(r'resValue\("string", "app_name", "([^"]+)"\)')
        .firstMatch(block)!
        .group(1)!;
  }

  String setting(String xcconfig, String key) =>
      RegExp('^$key = (.+)\$', multiLine: true).firstMatch(xcconfig)!.group(1)!;

  test('the flavors are exactly dev, staging and prod, on both platforms', () {
    expect(
      RegExp(r'create\("(\w+)"\) \{\s*dimension = "env"')
          .allMatches(gradle)
          .map((m) => m.group(1)),
      flavors,
    );
    final schemes = Directory('ios/Runner.xcodeproj/xcshareddata/xcschemes')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();
    expect(schemes, ['Runner.xcscheme', for (final f in flavors) '$f.xcscheme']..sort());
  });

  for (final flavor in flavors) {
    test('$flavor: scheme, configurations and xcconfigs match Android', () {
      final scheme = File(
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/$flavor.xcscheme',
      ).readAsStringSync();
      final used = RegExp(r'buildConfiguration = "([^"]+)"')
          .allMatches(scheme)
          .map((m) => m.group(1))
          .toSet();
      expect(used, {'Debug-$flavor', 'Release-$flavor', 'Profile-$flavor'});
      // Flutter needs the SPM pre-action in every scheme it builds.
      expect(scheme, contains('xcode_backend.sh&quot; prepare'));

      for (final mode in modes) {
        final cfg = '$mode-$flavor';
        // Project, Runner and RunnerTests each have the configuration.
        expect('name = "$cfg";'.allMatches(pbx).length, 3, reason: cfg);
        expect(
          RegExp(
            'baseConfigurationReference = [0-9A-F]{24} /\\* $cfg\\.xcconfig \\*/;',
          ).allMatches(pbx).length,
          1,
          reason: '$cfg: the Runner target uses its own xcconfig',
        );
        final xc = File('ios/Flutter/$cfg.xcconfig').readAsStringSync();
        final pods = '${mode.toLowerCase()}-$flavor';
        expect(xc, contains('Pods-Runner.$pods.xcconfig"'));
        expect(xc, contains('#include "Generated.xcconfig"'));
        expect(setting(xc, 'PRODUCT_BUNDLE_IDENTIFIER'), androidId(flavor));
        expect(setting(xc, 'APP_DISPLAY_NAME'), androidName(flavor));
        expect(setting(xc, 'DEVELOPMENT_TEAM'), 'MWHGM7ZHML');
      }
    });
  }

  test('only unflavored configs set the app bundle id in the project', () {
    // A target setting would silently override the flavor xcconfig.
    final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(pbx)
        .map((m) => m.group(1))
        .toList();
    expect(ids.where((id) => id == 'com.burrowsoft.piggybow').length, 3);
    expect(
      ids.where((id) => id != 'com.burrowsoft.piggybow'),
      everyElement('com.burrowsoft.piggybow.RunnerTests'),
    );
  });

  test('iPhone only: every config, no iPad', () {
    final families = RegExp(r'TARGETED_DEVICE_FAMILY = ([^;]+);')
        .allMatches(pbx)
        .map((m) => m.group(1))
        .toList();
    expect(families, isNotEmpty);
    expect(families, everyElement('1'));
  });

  test('one app icon, no capabilities: no alternate icons, empty entitlements', () {
    expect(pbx, isNot(contains('ALTERNATE_APPICON')));
    expect(
      Directory('ios/Runner/Assets.xcassets')
          .listSync()
          .map((f) => f.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .where((n) => n.endsWith('.appiconset')),
      ['AppIcon.appiconset'],
    );
    final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements, contains('<dict/>'));
  });

  test('Info.plist: flavor display name, no non-exempt encryption', () {
    expect(
      plist,
      contains(
        '<key>CFBundleDisplayName</key>\n\t<string>\$(APP_DISPLAY_NAME)</string>',
      ),
    );
    expect(
      plist,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
  });

  test('Info.plist asks for Face ID only: no photos, camera, microphone or speech', () {
    final usage = RegExp(r'<key>(NS\w+UsageDescription)</key>')
        .allMatches(plist)
        .map((m) => m.group(1))
        .toList();
    expect(usage, ['NSFaceIDUsageDescription']);
  });

  test('reminders: the notification delegate is set (the plugin\'s iOS setup)', () {
    expect(
      File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      contains('UNUserNotificationCenter.current().delegate = self'),
    );
  });

  group('the languages iOS declares', () {
    // Only what the app offers: the App Store lists these. v0.1 is English
    // only; a language joins this list when it ships.
    const regions = ['en'];

    List<String> strings(String block) => RegExp(r'<string>([^<]+)</string>')
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toList();

    test('Info.plist and the project agree; no other lproj', () {
      final declared = RegExp(
        r'<key>CFBundleLocalizations</key>\s*<array>([\s\S]*?)</array>',
      ).firstMatch(plist)!.group(1)!;
      expect(strings(declared), regions);
      final known = RegExp(r'knownRegions = \(([^)]*)\);')
          .firstMatch(pbx)!
          .group(1)!;
      expect(
        known.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
        ['en', 'Base'],
      );
      final lprojs = Directory('ios/Runner')
          .listSync()
          .map((f) => f.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .where((n) => n.endsWith('.lproj'))
          .toList()
        ..sort();
      expect(lprojs, ['Base.lproj', 'en.lproj']);
    });

    test('each has the Face ID sentence, in the app bundle', () {
      for (final r in regions) {
        final text = File(
          'ios/Runner/$r.lproj/InfoPlist.strings',
        ).readAsStringSync();
        expect(text, contains('"NSFaceIDUsageDescription" = "'), reason: r);
        expect(text, contains('Face ID'), reason: r);
        expect(pbx, contains('path = $r.lproj/InfoPlist.strings;'), reason: r);
      }
      expect(pbx, contains('InfoPlist.strings in Resources */,'));
    });

    test('iPhone: portrait only', () {
      final iphone = RegExp(
        r'<key>UISupportedInterfaceOrientations</key>\s*<array>([\s\S]*?)</array>',
      ).firstMatch(plist)!.group(1)!;
      expect(strings(iphone), ['UIInterfaceOrientationPortrait']);
    });
  });

  test('the privacy manifest: crash reports only, never linked or tracking', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    // v0.1 keeps everything on the phone. Only a build with a Sentry DSN
    // sends crash reports and diagnostics, not linked to the person.
    const label = {'CrashData': false, 'OtherDiagnosticData': false};
    final entries = RegExp(
      r'<dict>\s*<key>NSPrivacyCollectedDataType</key>\s*'
      r'<string>NSPrivacyCollectedDataType(\w+)</string>([\s\S]*?)</dict>',
    ).allMatches(manifest).toList();
    expect([for (final e in entries) e.group(1)!]..sort(), label.keys.toList()..sort());
    for (final e in entries) {
      final type = e.group(1)!;
      final body = e.group(2)!;
      final linked = RegExp(
        r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<(true|false)/>',
      ).firstMatch(body)?.group(1);
      expect(linked, '${label[type]}', reason: '$type linked');
      expect(
        body,
        matches(RegExp(r'<key>NSPrivacyCollectedDataTypeTracking</key>\s*<false/>')),
        reason: '$type tracking',
      );
      final purposes = RegExp(r'<string>(NSPrivacyCollectedDataTypePurpose\w+)</string>');
      expect(
        [for (final p in purposes.allMatches(body)) p.group(1)],
        ['NSPrivacyCollectedDataTypePurposeAppFunctionality'],
        reason: '$type purposes',
      );
    }
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(project, contains('PrivacyInfo.xcprivacy in Resources */,'));
  });

  test('codemagic.yaml: manual only, no review submission, right ids', () {
    expect(codemagic, isNot(contains('triggering:')));
    // Pinned, never 'latest'.
    expect('xcode: "26.6"'.allMatches(codemagic).length, 2);
    expect(codemagic, isNot(contains('xcode: latest')));
    expect(codemagic, isNot(contains(RegExp(r'submit_to_\w+: true'))));
    expect(
      RegExp(r'app_store_connect: piggybow_asc').allMatches(codemagic).length,
      2,
    );

    String workflow(String name) =>
        RegExp('\\n  $name:\\n([\\s\\S]*?)(?=\\n  [\\w-]+:\\n|\$)')
            .firstMatch(codemagic)!
            .group(1)!;
    for (final (name, flavor) in [
      ('ios-staging', 'staging'),
      ('ios-release', 'prod'),
    ]) {
      final w = workflow(name);
      expect(w, contains('bundle_identifier: ${androidId(flavor)}\n'));
      expect(w, contains('--flavor $flavor '));
      expect(w, contains('--dart-define-from-file=env/$flavor.json'));
      // The store version is pubspec's version name, never a hard-coded one;
      // an empty one fails the build.
      expect(w, contains("BUILD_NAME=\$(sed -n 's/^version: *"));
      expect(w, contains('test -n "\$BUILD_NAME" ||'));
      expect(w, contains('--build-name="\$BUILD_NAME"'));
      expect(w, contains('max_build_duration: 60'), reason: name);
    }

    final workflows = Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync());
    final ciFlutter = {
      for (final w in workflows)
        ...RegExp(r'flutter-version: (\S+)')
            .allMatches(w)
            .map((m) => m.group(1)),
    };
    final cmFlutter = RegExp(r'flutter: (\S+)')
        .allMatches(codemagic)
        .map((m) => m.group(1))
        .toSet();
    expect(cmFlutter, ciFlutter, reason: 'one Flutter version everywhere');
  });
}
