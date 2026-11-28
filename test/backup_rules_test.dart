import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/journal/journal_store.dart';

/// The phone's own backup (decisions 17, 21 and 72): the journal and the
/// app's settings, only in a backup encrypted on the phone, and never the
/// PIN, the caches or the export files.
void main() {
  const res = 'android/app/src/main/res';

  /// The app's settings, as shared_preferences keeps them on Android.
  const prefs = 'FlutterSharedPreferences.xml';
  const both = [
    'include file ${JournalStore.fileName}',
    'include sharedpref $prefs',
  ];

  String read(String path) => File(path).readAsStringSync();

  /// The value of [name] among an element's [attributes], or null.
  String? attribute(String attributes, String name) =>
      RegExp('$name="([^"]*)"').firstMatch(attributes)?[1];

  final element = RegExp(r'<(include|exclude)\b([^>]*)/>');

  /// Each include and exclude rule in [xml], in order, as "include file
  /// journal.db", with its requireFlags after them when it has some.
  List<String> rules(String xml) {
    final found = <String>[];
    for (final m in element.allMatches(xml)) {
      final parts = [
        m[1],
        attribute(m[2]!, 'domain'),
        attribute(m[2]!, 'path'),
        attribute(m[2]!, 'requireFlags'),
      ];
      found.add(parts.whereType<String>().join(' '));
    }
    return found;
  }

  /// The part of [xml] in its [tag] element, the opening tag included.
  String section(String xml, String tag) {
    final start = xml.indexOf('<$tag');
    final end = xml.indexOf('</$tag>');
    expect(start, isNonNegative, reason: tag);
    expect(end, greaterThan(start), reason: tag);
    return xml.substring(start, end);
  }

  test('the manifest turns the backup on, with both rule files', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:allowBackup="true"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('Android 12+: both, to the cloud only when encrypted', () {
    final xml = read('$res/xml/data_extraction_rules.xml');
    final cloud = section(xml, 'cloud-backup');
    expect(cloud, contains('disableIfNoEncryptionCapabilities="true"'));
    expect(rules(cloud), both);
    expect(rules(section(xml, 'device-transfer')), both);
  });

  test('Android 9 to 11: both, only in an encrypted backup', () {
    final xml = read('$res/xml-v28/backup_rules.xml');
    expect(rules(xml), [for (final r in both) '$r clientSideEncryption']);
  });

  test('Android 8 and below: nothing at all', () {
    // A file with no rules would mean everything: every domain is left out.
    final xml = read('$res/xml/backup_rules.xml');
    const domains = [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ];
    expect(rules(xml), [for (final d in domains) 'exclude $d .']);
  });

  test('the settings stay in the file the rules name', () {
    // SharedPreferencesAsync and SharedPreferencesWithCache keep settings in
    // a DataStore file instead, which no rule includes: the backup would
    // silently lose them.
    final datastore = RegExp(r'SharedPreferences(Async|WithCache)\b');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        if (datastore.hasMatch(f.readAsStringSync())) offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test("iOS: the PIN stays in this iPhone's keychain", () {
    expect(
      KeystoreSecretStore.storage.iOptions.accessibility,
      KeychainAccessibility.unlocked_this_device,
    );
  });
}
