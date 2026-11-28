import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/play_png.dart';

/// The store screenshots' PNG step (decision 34): an RGBA screenshot in, an
/// 8-bit RGB PNG out, same pixels, no alpha, no text chunks; and the check
/// that reads the written bytes.
void main() {
  /// A PNG chunk, as the tool writes them (its CRC from the tool's own).
  Uint8List chunk(String type, List<int> data) {
    final bytes = Uint8List(12 + data.length);
    final view = ByteData.sublistView(bytes)..setUint32(0, data.length);
    bytes.setRange(4, 8, type.codeUnits);
    bytes.setRange(8, 8 + data.length, data);
    view.setUint32(8 + data.length, crc32(bytes, 4, 8 + data.length));
    return bytes;
  }

  /// [pixels] (rows of [channels]-byte pixels) as a PNG of [colour] type,
  /// row y filtered with type y % 5, with a tEXt chunk, as a screenshot
  /// tool might write.
  Uint8List png(
    List<List<int>> pixels, {
    required int width,
    int channels = 4,
    int colour = 6,
    int depth = 8,
  }) {
    final height = pixels.length;
    final stride = width * channels;
    final raw = BytesBuilder();
    for (var y = 0; y < height; y++) {
      final type = y % 5;
      raw.addByte(type);
      for (var i = 0; i < stride; i++) {
        final x = pixels[y][i];
        final a = i >= channels ? pixels[y][i - channels] : 0;
        final b = y > 0 ? pixels[y - 1][i] : 0;
        final c = i >= channels && y > 0 ? pixels[y - 1][i - channels] : 0;
        final predicted = switch (type) {
          0 => 0,
          1 => a,
          2 => b,
          3 => (a + b) >> 1,
          _ => paeth(a, b, c),
        };
        raw.addByte((x - predicted) & 0xff);
      }
    }
    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, depth)
      ..setUint8(9, colour);
    return (BytesBuilder()
          ..add([137, 80, 78, 71, 13, 10, 26, 10])
          ..add(chunk('IHDR', header.buffer.asUint8List()))
          ..add(chunk('tEXt', 'Software\x00screencap'.codeUnits))
          ..add(chunk('IDAT', zlib.encode(raw.takeBytes())))
          ..add(chunk('IEND', const [])))
        .takeBytes();
  }

  /// Five rows (one per filter) of four RGBA pixels, varied enough that a
  /// wrong filter would show.
  const width = 4;
  final rgba = [
    for (var y = 0; y < 5; y++)
      [
        for (var x = 0; x < width; x++) ...[
          (17 * x + 31 * y) % 256,
          (200 - 13 * x + 7 * y) % 256,
          (91 * x * y + 5) % 256,
          255,
        ],
      ],
  ];

  test('RGBA in: RGB out, the same pixels, every row filter undone', () {
    final out = toRgb(png(rgba, width: width));
    expect(check(out, width: width, height: 5), isNull);
    final all = chunks(out);
    expect([for (final c in all) c.type], ['IHDR', 'IDAT', 'IEND']);
    final rows = zlib.decode(all[1].data);
    for (var y = 0; y < 5; y++) {
      final row = rows.sublist(y * (width * 3 + 1), (y + 1) * (width * 3 + 1));
      expect(row.first, 0, reason: 'row $y written unfiltered');
      final want = [
        for (var x = 0; x < width; x++) ...rgba[y].sublist(x * 4, x * 4 + 3),
      ];
      expect(row.sublist(1), want, reason: 'row $y');
    }
  });

  test('RGB in stays RGB, the text chunk gone', () {
    final rgb = [
      for (final row in rgba)
        [
          for (var x = 0; x < width; x++) ...row.sublist(x * 4, x * 4 + 3),
        ],
    ];
    final input = png(rgb, width: width, channels: 3, colour: 2);
    expect(check(input, width: width, height: 5), contains('tEXt'));
    expect(check(toRgb(input), width: width, height: 5), isNull);
  });

  test('the check refuses alpha, the wrong size and extra chunks', () {
    final rgbaPng = png(rgba, width: width);
    expect(check(rgbaPng, width: width, height: 5), contains('colour type 6'));
    final out = toRgb(rgbaPng);
    expect(check(out, width: 1080, height: 2160), contains('not 1080x2160'));
    expect(check(Uint8List(3), width: width, height: 5), 'not a PNG');
  });

  test('16-bit or a broken file: refused, never guessed at', () {
    expect(
      () => toRgb(png(rgba, width: width, depth: 16)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => toRgb(Uint8List.fromList('not a png'.codeUnits)),
      throwsA(isA<FormatException>()),
    );
  });

  test("the CRC is PNG's (IEND's is AE 42 60 82)", () {
    final iend = chunk('IEND', const []);
    expect(iend.sublist(8), [0xAE, 0x42, 0x60, 0x82]);
  });
}
