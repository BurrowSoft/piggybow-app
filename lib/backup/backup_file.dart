// Feature 21, the backup file (version 1): a person's journal, sealed with a
// password they choose, to move phones or keep a copy, with no account and no
// server. Free, like every other way out of the app.
//
// The file is one small JSON envelope:
//   {"format":"piggybow-backup","version":1,
//    "kdf":{"name":"argon2id","memoryKiB":…,"iterations":…,"parallelism":…,
//           "salt":"<base64>"},
//    "cipher":{"name":"aes-256-gcm","nonce":"<base64>"},
//    "payload":"<base64 ciphertext + 16-byte tag>"}
// Argon2id(password in NFC, salt) gives the AES-256-GCM key. The header (all
// of it but the payload, in this fixed order, no spaces) is the GCM's
// associated data, so changing any of it fails exactly as a wrong password
// does. The payload is gzip(JSON) of whatever is sealed; nothing about the
// journal is in the clear. A fresh random salt and nonce per file.
//
// Opening checks the format, the version and the KDF's bounds before any key
// is made, so a crafted file can't make the phone work for minutes.

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

const backupFormat = 'piggybow-backup';

/// The envelope's version this build writes and the newest it reads.
const backupVersion = 1;

/// A larger file isn't a Piggybow backup.
const backupMaxBytes = 50 * 1024 * 1024;

/// Argon2id's cost, carried in each file so later versions can raise it.
class BackupKdf {
  const BackupKdf({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// What version 1 writes: OWASP's Argon2id minimum (19 MiB, 2 passes, 1
  /// lane), until it is timed on phones.
  static const v1 = BackupKdf(memoryKiB: 19456, iterations: 2, parallelism: 1);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// What a file may ask for. Argon2 needs 8 KiB per lane at least; more
  /// than 256 MiB or 10 passes isn't something Piggybow ever writes.
  bool get withinBounds =>
      parallelism >= 1 &&
      parallelism <= 4 &&
      memoryKiB >= 8 * parallelism &&
      memoryKiB <= 256 * 1024 &&
      iterations >= 1 &&
      iterations <= 10;
}

/// Why a file didn't open.
sealed class BackupException implements Exception {
  const BackupException();
}

/// The password doesn't open it, or the file was changed: AES-GCM can't tell
/// the two apart, and neither does the app.
final class BackupWontOpen extends BackupException {
  const BackupWontOpen();
}

/// Not a Piggybow backup (or one no build ever writes).
final class NotABackup extends BackupException {
  const NotABackup();
}

/// Made by a newer Piggybow: the app needs updating first.
final class BackupTooNew extends BackupException {
  const BackupTooNew();
}

/// Where the salt and the nonce come from; tests pass fixed ones.
typedef RandomBytes = List<int> Function(int length);

final _random = Random.secure();

List<int> _secureBytes(int length) => [
  for (var i = 0; i < length; i++) _random.nextInt(256),
];

final _aes = AesGcm.with256bits();

Map<String, Object?> _header(BackupKdf kdf, List<int> salt, List<int> nonce) =>
    {
      'format': backupFormat,
      'version': backupVersion,
      'kdf': {
        'name': 'argon2id',
        'memoryKiB': kdf.memoryKiB,
        'iterations': kdf.iterations,
        'parallelism': kdf.parallelism,
        'salt': base64.encode(salt),
      },
      'cipher': {'name': 'aes-256-gcm', 'nonce': base64.encode(nonce)},
    };

List<int> _aad(Map<String, Object?> header) => utf8.encode(jsonEncode(header));

/// The password in Unicode NFC, so "é" typed on any phone is the same bytes.
Future<SecretKey> _key(String password, List<int> salt, BackupKdf kdf) =>
    Argon2id(
      parallelism: kdf.parallelism,
      memory: kdf.memoryKiB,
      iterations: kdf.iterations,
      hashLength: 32,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode(unorm.nfc(password))),
      nonce: salt,
    );

/// [data] (anything JSON can hold) as a backup file's text.
Future<String> sealBackup(
  Object? data,
  String password, {
  BackupKdf kdf = BackupKdf.v1,
  RandomBytes randomBytes = _secureBytes,
}) async {
  final salt = randomBytes(16);
  final nonce = randomBytes(12);
  final header = _header(kdf, salt, nonce);
  final box = await _aes.encrypt(
    gzip.encode(utf8.encode(jsonEncode(data))),
    secretKey: await _key(password, salt, kdf),
    nonce: nonce,
    aad: _aad(header),
  );
  return jsonEncode({
    ...header,
    'payload': base64.encode([...box.cipherText, ...box.mac.bytes]),
  });
}

List<int> _bytes(Object? value) {
  if (value is! String) throw const NotABackup();
  try {
    return base64.decode(value);
  } on FormatException {
    throw const NotABackup();
  }
}

/// What [file] holds, with [password]; throws a [BackupException] otherwise.
Future<Object?> openBackup(String file, String password) async {
  if (file.length > backupMaxBytes) throw const NotABackup();
  final Object? decoded;
  try {
    decoded = jsonDecode(file);
  } on FormatException {
    throw const NotABackup();
  }
  if (decoded is! Map<String, Object?>) throw const NotABackup();
  if (decoded['format'] != backupFormat) throw const NotABackup();
  final version = decoded['version'];
  if (version is! int || version < 1) throw const NotABackup();
  if (version > backupVersion) throw const BackupTooNew();

  final kdfField = decoded['kdf'];
  final cipherField = decoded['cipher'];
  if (kdfField is! Map<String, Object?> ||
      cipherField is! Map<String, Object?>) {
    throw const NotABackup();
  }
  if (kdfField['name'] != 'argon2id' || cipherField['name'] != 'aes-256-gcm') {
    throw const NotABackup();
  }
  final memory = kdfField['memoryKiB'];
  final iterations = kdfField['iterations'];
  final parallelism = kdfField['parallelism'];
  if (memory is! int || iterations is! int || parallelism is! int) {
    throw const NotABackup();
  }
  final kdf = BackupKdf(
    memoryKiB: memory,
    iterations: iterations,
    parallelism: parallelism,
  );
  if (!kdf.withinBounds) throw const NotABackup();
  final salt = _bytes(kdfField['salt']);
  final nonce = _bytes(cipherField['nonce']);
  final sealed = _bytes(decoded['payload']);
  if (salt.length < 16 || salt.length > 64) throw const NotABackup();
  if (nonce.length != 12 || sealed.length < 16) throw const NotABackup();

  final List<int> clear;
  try {
    clear = await _aes.decrypt(
      SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      ),
      secretKey: await _key(password, salt, kdf),
      aad: _aad(_header(kdf, salt, nonce)),
    );
  } on SecretBoxAuthenticationError {
    throw const BackupWontOpen();
  }
  try {
    return jsonDecode(utf8.decode(gzip.decode(clear)));
  } on FormatException {
    throw const NotABackup();
  }
}
