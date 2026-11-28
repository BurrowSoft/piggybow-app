import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';

/// Feature 21, the backup file's format (version 1): sealed with Argon2id and
/// AES-256-GCM, the header authenticated with the payload, nothing in the
/// clear. A wrong password or any change fails as "won't open"; a file that
/// isn't one, or asks for an absurd cost, fails before any key is made; a
/// newer one says so. Files made by version 1 open in every later build.
void main() {
  // Small enough for CI; the real cost is timed once below.
  const fast = BackupKdf(memoryKiB: 64, iterations: 1, parallelism: 1);

  /// The same "random" bytes every time, for files a test can rebuild.
  List<int> fixed(int length) => [for (var i = 0; i < length; i++) i * 7];

  final journal = <String, Object?>{
    'schema': 1,
    'entries': [
      {
        'id': 'e1',
        'type': 'spent',
        'amount_minor': 999999999999,
        'currency': 'THB',
        'local_date': '2026-10-01',
        'category': 'food',
        'feeling': 'worth_it',
        'note': 'ข้าวมันไก่ กับเพื่อน 🐷 and a very long note to see it whole',
      },
      {
        'id': 'e2',
        'type': 'saved',
        'amount_minor': 500,
        'currency': 'THB',
        'local_date': '2026-10-02',
        'goal_id': 'g1',
        'note': '',
      },
    ],
    'goals': [
      {'id': 'g1', 'name': 'จักรยาน', 'target_minor': 1000000},
    ],
  };

  Future<String> seal([Object? data, String password = 'correct horse']) =>
      sealBackup(data ?? journal, password, kdf: fast, randomBytes: fixed);

  /// The file with one field of its JSON changed.
  String edited(String file, void Function(Map<String, dynamic>) change) {
    final m = jsonDecode(file) as Map<String, dynamic>;
    change(m);
    return jsonEncode(m);
  }

  /// [b64] with one bit flipped in byte [at] (negative: from the end).
  String flipped(String b64, int at) {
    final bytes = base64.decode(b64);
    final i = at < 0 ? bytes.length + at : at;
    bytes[i] ^= 0x01;
    return base64.encode(bytes);
  }

  group('a round trip', () {
    test('the journal comes back exactly, with the right password', () async {
      expect(await openBackup(await seal(), 'correct horse'), journal);
    });

    test('nothing in the clear: no note, name, amount or count', () async {
      final file = await seal();
      for (final secret in ['ข้าวมันไก่', '🐷', 'จักรยาน', '999999999999', 'food']) {
        expect(file.contains(secret), isFalse, reason: secret);
      }
      expect((jsonDecode(file) as Map).keys.toSet(), {
        'format',
        'version',
        'kdf',
        'cipher',
        'payload',
      });
    });

    test('a fresh salt and nonce for every file', () async {
      final a = jsonDecode(
        await sealBackup(journal, 'pw', kdf: fast),
      ) as Map;
      final b = jsonDecode(
        await sealBackup(journal, 'pw', kdf: fast),
      ) as Map;
      expect((a['kdf'] as Map)['salt'], isNot((b['kdf'] as Map)['salt']));
      expect(
        (a['cipher'] as Map)['nonce'],
        isNot((b['cipher'] as Map)['nonce']),
      );
      expect(a['payload'], isNot(b['payload']));
    });

    test('a big journal: 10,000 entries, well under the size cap', () async {
      final big = {
        'schema': 1,
        'entries': [
          for (var i = 0; i < 10000; i++)
            {
              'id': 'entry-$i',
              'type': 'spent',
              'amount_minor': i * 37,
              'local_date': '2026-10-01',
              'note': 'note $i',
            },
        ],
      };
      final file = await seal(big);
      expect(file.length, lessThan(backupMaxBytes ~/ 10));
      expect(await openBackup(file, 'correct horse'), big);
    });
  });

  group('the password', () {
    test('a wrong one: won\'t open', () async {
      final file = await seal();
      for (final wrong in ['correct horse ', 'Correct horse', '', 'x']) {
        await expectLater(
          openBackup(file, wrong),
          throwsA(isA<BackupWontOpen>()),
          reason: '"$wrong"',
        );
      }
    });

    test('NFC and NFD are the same password', () async {
      final file = await seal(journal, 'caf\u00e9 ข้าว');
      expect(await openBackup(file, 'cafe\u0301 ข้าว'), journal);
    });
  });

  group('any change to the file: won\'t open', () {
    final changes = <String, void Function(Map<String, dynamic>)>{
      'memoryKiB': (m) => m['kdf']['memoryKiB'] = 72,
      'iterations': (m) => m['kdf']['iterations'] = 2,
      'parallelism': (m) => m['kdf']['parallelism'] = 2,
      'salt': (m) => m['kdf']['salt'] = flipped(m['kdf']['salt'] as String, 3),
      'nonce': (m) =>
          m['cipher']['nonce'] = flipped(m['cipher']['nonce'] as String, 0),
      'payload start': (m) =>
          m['payload'] = flipped(m['payload'] as String, 0),
      'payload middle': (m) {
        final b64 = m['payload'] as String;
        m['payload'] = flipped(b64, base64.decode(b64).length ~/ 2);
      },
      'the tag': (m) => m['payload'] = flipped(m['payload'] as String, -1),
      'cut short': (m) {
        final bytes = base64.decode(m['payload'] as String);
        m['payload'] = base64.encode(bytes.sublist(0, bytes.length - 1));
      },
      'made longer': (m) {
        final bytes = base64.decode(m['payload'] as String);
        m['payload'] = base64.encode([...bytes, 0]);
      },
    };
    for (final MapEntry(key: what, value: change) in changes.entries) {
      test(what, () async {
        await expectLater(
          openBackup(edited(await seal(), change), 'correct horse'),
          throwsA(isA<BackupWontOpen>()),
        );
      });
    }

    test('a field added to the header changes nothing it protects', () async {
      final file = edited(await seal(), (m) => m['note'] = 'hello');
      expect(await openBackup(file, 'correct horse'), journal);
    });
  });

  group('not a backup, or one from a newer Piggybow', () {
    test('not a backup file', () async {
      final file = await seal();
      for (final text in [
        '',
        'hello',
        '[]',
        '{}',
        '{"format":"piggybow-backup"}',
        edited(file, (m) => m['format'] = 'something-else'),
        edited(file, (m) => m['version'] = 0),
        edited(file, (m) => m['version'] = '1'),
        edited(file, (m) => m['kdf']['name'] = 'scrypt'),
        edited(file, (m) => m['cipher']['name'] = 'aes-128-gcm'),
        edited(file, (m) => m['payload'] = 'not base64!'),
        edited(file, (m) => m['payload'] = base64.encode([1, 2, 3])),
        edited(file, (m) => m['cipher']['nonce'] = base64.encode([1, 2])),
        edited(file, (m) => m['kdf']['salt'] = base64.encode([1, 2])),
        edited(file, (m) => m.remove('kdf')),
      ]) {
        await expectLater(
          openBackup(text, 'correct horse'),
          throwsA(isA<NotABackup>()),
          reason: text.length > 60 ? text.substring(0, 60) : text,
        );
      }
    });

    test('made by a newer Piggybow', () async {
      await expectLater(
        openBackup(edited(await seal(), (m) => m['version'] = 2), 'x'),
        throwsA(isA<BackupTooNew>()),
      );
    });

    test('an absurd cost is refused before any key is made', () async {
      final file = await seal();
      final watch = Stopwatch()..start();
      for (final change in <void Function(Map<String, dynamic>)>[
        (m) => m['kdf']['memoryKiB'] = 10 * 1024 * 1024,
        (m) => m['kdf']['iterations'] = 1000,
        (m) => m['kdf']['parallelism'] = 64,
        (m) => m['kdf']['memoryKiB'] = 4,
      ]) {
        await expectLater(
          openBackup(edited(file, change), 'correct horse'),
          throwsA(isA<NotABackup>()),
        );
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('larger than the cap: not a backup', () async {
      await expectLater(
        openBackup('x' * (backupMaxBytes + 1), 'x'),
        throwsA(isA<NotABackup>()),
      );
    });
  });

  test('version 1 files open in every later build (the fixture)', () async {
    final fixture = File('test/fixtures/backup/v1.piggybow');
    if (!fixture.existsSync()) {
      // Bootstrap, once: commit exactly what this prints.
      fail(
        'Commit as test/fixtures/backup/v1.piggybow:\n'
        '${await seal()}',
      );
    }
    expect(
      await openBackup(fixture.readAsStringSync().trim(), 'correct horse'),
      journal,
    );
  });

  test("version 1's cost, timed (informational)", () async {
    final watch = Stopwatch()..start();
    final file = await sealBackup(journal, 'correct horse');
    final sealed = watch.elapsedMilliseconds;
    expect(await openBackup(file, 'correct horse'), journal);
    // ignore: avoid_print
    print(
      'backup-kdf-timing: Argon2id ${BackupKdf.v1.memoryKiB} KiB, '
      't ${BackupKdf.v1.iterations}, p ${BackupKdf.v1.parallelism}: seal '
      '$sealed ms, open ${watch.elapsedMilliseconds - sealed} ms',
    );
  });
}
