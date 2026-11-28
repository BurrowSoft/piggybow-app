import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';
import 'package:piggybow/backup/backup_flow.dart';

/// Feature 21's way in and out of the phone: MainActivity's own document
/// picker (nothing copied, the size checked first, never more than the cap
/// read), and the real hooks, sealing and opening off the UI's isolate. On a
/// phone the picker is a tester row: a backup, and a 1 GB video (no crash,
/// "isn't a backup"), with the cache empty after.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(backupChannel);
  MethodCall? asked;
  Object? answer;

  setUp(() {
    asked = null;
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked = call;
          return answer;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  group('the picker (MainActivity)', () {
    test('asks for at most the cap, and gives the picked file\'s name and '
        'text', () async {
      answer = {
        'name': 'piggybow-backup-2026-09-30.piggybow',
        'bytes': bytesOf('{"format":"piggybow-backup"}'),
      };
      final picked = await pickBackupFile();
      expect(asked!.method, openBackupFileMethod);
      expect(asked!.arguments, {'maxBytes': backupMaxBytes});
      expect(picked!.name, 'piggybow-backup-2026-09-30.piggybow');
      expect(picked.text, '{"format":"piggybow-backup"}');
    });

    test('nothing picked: null, nothing said', () async {
      answer = null;
      expect(await pickBackupFile(), isNull);
    });

    // MainActivity says "too large" by the file's SIZE before reading, and
    // while reading when the size is unknown (null or -1): it never reads
    // more than the cap + 1 bytes. Either way, not a backup.
    for (final (what, picked) in <(String, Map<String, Object?>)>[
      ('larger by its size', {'name': 'video.mp4', 'tooLarge': true}),
      (
        'an unknown size, larger while reading',
        {'name': 'stream', 'tooLarge': true},
      ),
      ('unreadable', {'name': 'gone.piggybow', 'unreadable': true}),
      (
        'not text',
        {
          'name': 'photo.jpg',
          'bytes': Uint8List.fromList([0xff, 0xfe, 0xfd, 0x00]),
        },
      ),
      (
        'more bytes than the cap, whatever was said',
        {'name': 'big', 'bytes': Uint8List(backupMaxBytes + 1)},
      ),
    ]) {
      test('$what: not a backup', () async {
        answer = picked;
        await expectLater(pickBackupFile(), throwsA(isA<NotABackup>()));
      });
    }

    test('MainActivity: the same names, the size first, the cap while '
        'reading, nothing written anywhere', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/burrowsoft/piggybow/MainActivity.kt',
      ).readAsStringSync();
      expect(kotlin, contains('BACKUP_CHANNEL = "$backupChannel"'));
      expect(kotlin, contains('OPEN_BACKUP_FILE = "$openBackupFileMethod"'));
      expect(kotlin, contains('OpenableColumns.SIZE'));
      expect(kotlin, contains('if (known != null && known > limit)'));
      // An unknown size is never taken as small: the cap holds while reading.
      expect(
        kotlin,
        contains(
          'if (total > limit) return mapOf("name" to name, "tooLarge" to true)',
        ),
      );
      // Read into memory only: nothing is written, nothing goes to the cache.
      for (final never in ['cacheDir', 'FileOutputStream', 'copyTo(']) {
        expect(kotlin, isNot(contains(never)), reason: never);
      }
    });

    test('no plugin that copies a picked file: file_selector is gone', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('file_selector')),
      );
      expect(
        File('pubspec.lock').readAsStringSync(),
        isNot(contains('file_selector')),
      );
    });
  });

  group('the real hooks, off the UI\'s isolate', () {
    test('a round trip, and a wrong password won\'t open', () async {
      const hooks = BackupHooks();
      final file = await hooks.seal({'note': 'ข้าวมันไก่'}, 'correct horse');
      expect(await hooks.open(file, 'correct horse'), {'note': 'ข้าวมันไก่'});
      await expectLater(
        hooks.open(file, 'wrong horse'),
        throwsA(isA<BackupWontOpen>()),
      );
    });
  });
}
