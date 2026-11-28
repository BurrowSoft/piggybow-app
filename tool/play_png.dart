// Store screenshots (decision 34): every PNG in a folder rewritten as an
// 8-bit RGB PNG with no alpha and no text chunks, then checked from its own
// bytes. Play refuses some alpha originals, and nothing but pixels goes to
// the store.
//
//   dart run tool/play_png.dart <dir> [width height]   (default 1080 2160)
import 'dart:io';
import 'dart:typed_data';

const _signature = [137, 80, 78, 71, 13, 10, 26, 10];

/// Play's limit for a screenshot file.
const maxBytes = 8 * 1024 * 1024;

void main(List<String> args) {
  if (args.length != 1 && args.length != 3) {
    stderr.writeln('usage: dart run tool/play_png.dart <dir> [width height]');
    exit(2);
  }
  final dir = Directory(args[0]);
  final width = args.length == 3 ? int.parse(args[1]) : 1080;
  final height = args.length == 3 ? int.parse(args[2]) : 2160;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('play_png: no PNG in ${dir.path}');
    exit(1);
  }
  var failed = false;
  for (final file in files) {
    String? problem;
    try {
      file.writeAsBytesSync(toRgb(file.readAsBytesSync()));
      problem = check(file.readAsBytesSync(), width: width, height: height);
    } on FormatException catch (e) {
      problem = e.message;
    }
    if (problem != null) {
      failed = true;
      stderr.writeln('play_png: ${file.path}: $problem');
    } else {
      stdout.writeln(
        'play_png: ${file.path}: 8-bit RGB, ${width}x$height, '
        '${file.lengthSync()} bytes',
      );
    }
  }
  if (failed) exit(1);
}

/// One chunk of a PNG: its type and its data.
typedef Chunk = ({String type, Uint8List data});

/// The chunks of [png], in order, up to IEND.
List<Chunk> chunks(Uint8List png) {
  if (png.length < 8) throw const FormatException('not a PNG');
  for (var i = 0; i < 8; i++) {
    if (png[i] != _signature[i]) throw const FormatException('not a PNG');
  }
  final view = ByteData.sublistView(png);
  final found = <Chunk>[];
  var at = 8;
  while (at + 12 <= png.length) {
    final length = view.getUint32(at);
    final type = String.fromCharCodes(png.sublist(at + 4, at + 8));
    if (at + 12 + length > png.length) {
      throw FormatException('chunk $type runs past the end');
    }
    final crc = view.getUint32(at + 8 + length);
    if (crc32(png, at + 4, at + 8 + length) != crc) {
      throw FormatException('chunk $type has a bad CRC');
    }
    found.add((
      type: type,
      data: Uint8List.sublistView(png, at + 8, at + 8 + length),
    ));
    at += 12 + length;
    if (type == 'IEND') break;
  }
  return found;
}

/// [png] as an 8-bit RGB PNG: the same pixels with the alpha dropped, and
/// only IHDR, IDAT and IEND. A screenshot is opaque; a pixel that isn't is
/// refused, never flattened onto a guessed colour.
Uint8List toRgb(Uint8List png) {
  final all = chunks(png);
  final ihdr = all
      .firstWhere(
        (c) => c.type == 'IHDR',
        orElse: () => throw const FormatException('no IHDR'),
      )
      .data;
  final header = ByteData.sublistView(ihdr);
  final width = header.getUint32(0);
  final height = header.getUint32(4);
  final depth = ihdr[8];
  final colour = ihdr[9];
  if (depth != 8) throw FormatException('bit depth $depth, not 8');
  if (ihdr[12] != 0) throw const FormatException('interlaced');
  final channels = switch (colour) {
    2 => 3,
    6 => 4,
    _ => throw FormatException('colour type $colour, not RGB or RGBA'),
  };
  final compressed = BytesBuilder(copy: false);
  for (final c in all) {
    if (c.type == 'IDAT') compressed.add(c.data);
  }
  final raw = Uint8List.fromList(zlib.decode(compressed.takeBytes()));
  final stride = width * channels;
  if (raw.length != height * (stride + 1)) {
    throw FormatException(
      'image data is ${raw.length} bytes, not ${height * (stride + 1)}',
    );
  }
  final pixels = _unfilter(raw, width: width, height: height, bpp: channels);
  // RGB rows, each with row filter 0.
  final rows = Uint8List(height * (width * 3 + 1));
  var o = 0;
  for (var y = 0; y < height; y++) {
    rows[o++] = 0;
    for (var x = 0; x < width; x++) {
      final p = y * stride + x * channels;
      if (channels == 4 && pixels[p + 3] != 255) {
        throw FormatException(
          'pixel ($x, $y) has alpha ${pixels[p + 3]}, not opaque',
        );
      }
      rows[o++] = pixels[p];
      rows[o++] = pixels[p + 1];
      rows[o++] = pixels[p + 2];
    }
  }
  final newHeader = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return (BytesBuilder(copy: false)
        ..add(_signature)
        ..add(_chunk('IHDR', newHeader.buffer.asUint8List()))
        ..add(
          _chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(rows))),
        )
        ..add(_chunk('IEND', Uint8List(0))))
      .takeBytes();
}

/// Why [png] isn't what the store gets, or null when it is: under 8 MB,
/// IHDR first, [width] × [height], bit depth 8, colour type 2 (RGB, no
/// alpha), and no chunk but IHDR, IDAT and IEND (so no text or metadata).
String? check(Uint8List png, {required int width, required int height}) {
  if (png.length >= maxBytes) return '${png.length} bytes, not under 8 MB';
  final List<Chunk> all;
  try {
    all = chunks(png);
  } on FormatException catch (e) {
    return e.message;
  }
  if (all.isEmpty || all.first.type != 'IHDR') return 'IHDR is not first';
  if (all.last.type != 'IEND') return 'no IEND';
  final ihdr = all.first.data;
  final header = ByteData.sublistView(ihdr);
  final w = header.getUint32(0);
  final h = header.getUint32(4);
  if (w != width || h != height) return '${w}x$h, not ${width}x$height';
  if (ihdr[8] != 8) return 'bit depth ${ihdr[8]}, not 8';
  if (ihdr[9] != 2) return 'colour type ${ihdr[9]}, not 2 (RGB)';
  final extra = {for (final c in all) c.type}
    ..removeAll(['IHDR', 'IDAT', 'IEND']);
  if (extra.isNotEmpty) return 'extra chunks: ${extra.join(', ')}';
  return null;
}

/// The pixels of [raw]'s rows, each undone from its row filter (PNG's five:
/// none, sub, up, average, Paeth).
Uint8List _unfilter(
  Uint8List raw, {
  required int width,
  required int height,
  required int bpp,
}) {
  final stride = width * bpp;
  final out = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    final type = raw[y * (stride + 1)];
    final src = y * (stride + 1) + 1;
    final dst = y * stride;
    for (var i = 0; i < stride; i++) {
      final x = raw[src + i];
      final a = i >= bpp ? out[dst + i - bpp] : 0;
      final b = y > 0 ? out[dst - stride + i] : 0;
      final c = i >= bpp && y > 0 ? out[dst - stride + i - bpp] : 0;
      final value = switch (type) {
        0 => x,
        1 => x + a,
        2 => x + b,
        3 => x + ((a + b) >> 1),
        4 => x + paeth(a, b, c),
        _ => throw FormatException('row filter $type'),
      };
      out[dst + i] = value & 0xff;
    }
  }
  return out;
}

/// PNG's Paeth predictor.
int paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

Uint8List _chunk(String type, Uint8List data) {
  final bytes = Uint8List(12 + data.length);
  final view = ByteData.sublistView(bytes)..setUint32(0, data.length);
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, 8 + data.length, data);
  view.setUint32(8 + data.length, crc32(bytes, 4, 8 + data.length));
  return bytes;
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// The CRC-32 PNG puts after each chunk, over [bytes] from [start] to [end].
int crc32(Uint8List bytes, int start, int end) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < end; i++) {
    c = _crcTable[(c ^ bytes[i]) & 0xff] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
