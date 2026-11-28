import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/theme/theme.dart' show PiggybowPalette;

const res = 'android/app/src/main/res';
const xc = 'ios/Runner/Assets.xcassets';

/// A PNG's size and colour type, from its IHDR chunk.
({int width, int height, int bitDepth, int colourType}) pngInfo(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10], reason: '$path is a PNG');
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR', reason: path);
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20), bitDepth: bytes[24], colourType: bytes[25]);
}

/// Every fill and stroke colour a vector drawable uses.
Set<String> vectorColours(String path) => RegExp(r'android:(?:fill|stroke)Color="([^"]+)"')
    .allMatches(File(path).readAsStringSync())
    .map((m) => m[1]!)
    .toSet();

String hexOf(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// A vector drawable's <path>: the transform of the <group>s around it (x' = sx * x + tx,
/// y' = sy * y + ty, in viewport units) and the numbers in its path data.
typedef VectorPath = ({double sx, double sy, double tx, double ty, List<double> numbers});

List<VectorPath> vectorPaths(String path) {
  final xml = File(path).readAsStringSync();
  double value(String tag, String key, double fallback) {
    final m = RegExp('android:$key="([^"]*)"').firstMatch(tag);
    return m == null ? fallback : double.parse(m[1]!);
  }

  final stack = [(sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0)];
  final paths = <VectorPath>[];
  for (final m in RegExp(r'<(/?)(group|path)\b([^>]*?)/?>').allMatches(xml)) {
    final t = stack.last;
    final tag = m[3]!;
    if (m[2] == 'group') {
      if (m[1] == '/') {
        stack.removeLast();
      } else {
        stack.add((
          sx: t.sx * value(tag, 'scaleX', 1),
          sy: t.sy * value(tag, 'scaleY', 1),
          tx: t.tx + t.sx * value(tag, 'translateX', 0),
          ty: t.ty + t.sy * value(tag, 'translateY', 0),
        ));
      }
      continue;
    }
    final data = RegExp(r'android:pathData="([^"]*)"').firstMatch(tag)![1]!;
    paths.add((
      sx: t.sx,
      sy: t.sy,
      tx: t.tx,
      ty: t.ty,
      numbers: [for (final n in RegExp(r'-?\d*\.?\d+').allMatches(data)) double.parse(n[0]!)],
    ));
  }
  return paths;
}

/// A PNG's pixels as RGBA (8 bits per channel, RGB or RGBA, any row filter).
({int width, int height, List<int> Function(int x, int y) rgba}) decodePng(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  expect(bytes[24], 8, reason: '$path: 8 bits per channel');
  final channels = switch (bytes[25]) {
    6 => 4,
    2 => 3,
    final other => throw StateError('$path: colour type $other'),
  };
  final compressed = <int>[];
  for (var o = 8; o + 8 <= bytes.length; o += 12 + data.getUint32(o)) {
    if (String.fromCharCodes(bytes.sublist(o + 4, o + 8)) == 'IDAT') {
      compressed.addAll(bytes.sublist(o + 8, o + 8 + data.getUint32(o)));
    }
  }
  final raw = zlib.decode(compressed);
  final stride = width * channels;
  final pixels = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    final filter = raw[y * (stride + 1)];
    for (var x = 0; x < stride; x++) {
      final left = x >= channels ? pixels[y * stride + x - channels] : 0;
      final up = y > 0 ? pixels[(y - 1) * stride + x] : 0;
      final upLeft = x >= channels && y > 0 ? pixels[(y - 1) * stride + x - channels] : 0;
      final predicted = switch (filter) {
        0 => 0,
        1 => left,
        2 => up,
        3 => (left + up) >> 1,
        4 => paeth(left, up, upLeft),
        _ => throw StateError('$path: row filter $filter'),
      };
      pixels[y * stride + x] = (raw[y * (stride + 1) + 1 + x] + predicted) & 0xFF;
    }
  }
  return (
    width: width,
    height: height,
    rgba: (x, y) => [for (var c = 0; c < 4; c++) c < channels ? pixels[(y * width + x) * channels + c] : 255],
  );
}

int paeth(int a, int b, int c) {
  final pa = (b - c).abs();
  final pb = (a - c).abs();
  final pc = (a + b - 2 * c).abs();
  return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
}

/// A PNG's chunk types, in order.
List<String> pngChunkTypes(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var o = 8; o + 8 <= bytes.length; o += 12 + data.getUint32(o)) String.fromCharCodes(bytes.sublist(o + 4, o + 8)),
  ];
}

void main() {
  group('iOS app icon', () {
    final set = jsonDecode(File('$xc/AppIcon.appiconset/Contents.json').readAsStringSync()) as Map<String, dynamic>;
    final images = (set['images'] as List).cast<Map<String, dynamic>>();

    test('every image the set lists is there at its pixel size, RGB with no alpha channel', () {
      expect(images.length, 19);
      for (final image in images) {
        final points = double.parse((image['size'] as String).split('x').first);
        final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
        final px = (points * scale).round();
        final info = pngInfo('$xc/AppIcon.appiconset/${image['filename']}');
        expect((info.width, info.height), (px, px), reason: '${image['filename']}');
        expect(info.bitDepth, 8, reason: '${image['filename']}');
        expect(info.colourType, 2, reason: '${image['filename']}: RGB only; the App Store refuses an alpha channel');
      }
    });

    test('the set holds nothing else', () {
      final files = Directory('$xc/AppIcon.appiconset').listSync().map((f) => f.uri.pathSegments.last).toSet();
      expect(files, {'Contents.json', ...images.map((i) => i['filename'] as String)});
    });
  });

  group('Android launcher icon', () {
    test('the adaptive icon ties its three layers to the cream background', () {
      final adaptive = File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
      for (final ref in ['@color/ic_launcher_background', '@drawable/ic_launcher_foreground', '@drawable/ic_launcher_monochrome']) {
        expect(adaptive, contains(ref));
      }
      expect(File('$res/values/ic_launcher_background.xml').readAsStringSync(), contains('#FBF6F1'));
      for (final layer in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
        expect(File('$res/drawable/$layer.xml').readAsStringSync(), contains('android:viewportWidth="108"'), reason: layer);
      }
    });

    test('the themed layer is white only (Android uses its alpha and tints it)', () {
      expect(vectorColours('$res/drawable/ic_launcher_monochrome.xml'), {'#FFFFFFFF'});
    });

    test('legacy icons at every density', () {
      const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      sizes.forEach((density, px) {
        final info = pngInfo('$res/mipmap-$density/ic_launcher.png');
        expect((info.width, info.height), (px, px), reason: density);
      });
    });

    test('the notification icon keeps its name, is white only, and survives resource shrinking', () {
      expect(vectorColours('$res/drawable/ic_notification.xml'), {'#FFFFFFFF'});
      expect(File('$res/raw/keep.xml').readAsStringSync(), contains('@drawable/ic_notification'));
    });
  });

  group('splash', () {
    test("its background is the theme's own: cream, and ink in dark mode", () {
      final light = hexOf(PiggybowPalette.light.background.toARGB32());
      final dark = hexOf(PiggybowPalette.dark.background.toARGB32());
      expect((light, dark), ('#FBF6F1', '#2B2438'));
      expect(File('$res/values/colors.xml').readAsStringSync(), contains('<color name="splash_background">$light</color>'));
      expect(File('$res/values-night/colors.xml').readAsStringSync(), contains('<color name="splash_background">$dark</color>'));
    });

    test('before Android 12: the background colour with the calm pig centred', () {
      final launch = File('$res/drawable/launch_background.xml').readAsStringSync();
      expect(launch, contains('@color/splash_background'));
      expect(launch, contains('@drawable/splash_pig'));
      expect(File('$res/drawable-v21/launch_background.xml').existsSync(), isFalse, reason: 'minSdk 24: one launch background');
      for (final style in ['values/styles.xml', 'values-night/styles.xml']) {
        expect(File('$res/$style').readAsStringSync(), contains('@drawable/launch_background'), reason: style);
      }
    });

    test('Android 12+: light and dark launch themes use the colour and the pig icon', () {
      for (final style in ['values-v31/styles.xml', 'values-night-v31/styles.xml']) {
        final xml = File('$res/$style').readAsStringSync();
        expect(xml, contains('<item name="android:windowSplashScreenBackground">@color/splash_background</item>'), reason: style);
        expect(xml, contains('<item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>'), reason: style);
        expect(xml, contains('name="NormalTheme"'), reason: style);
      }
      expect(File('$res/drawable/splash_icon.xml').readAsStringSync(), contains('android:viewportWidth="288"'));
    });

    test('iOS: the LaunchBackground colour (cream, ink in dark mode) and the 160 pt pig', () {
      final storyboard = File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
      expect(storyboard, contains('<color key="backgroundColor" name="LaunchBackground"/>'));
      expect(storyboard, contains('<image name="LaunchImage" width="160" height="160"/>'));
      final colorset = jsonDecode(File('$xc/LaunchBackground.colorset/Contents.json').readAsStringSync()) as Map<String, dynamic>;
      final colours = [
        for (final c in (colorset['colors'] as List).cast<Map<String, dynamic>>())
          (
            dark: c.containsKey('appearances'),
            rgb: ['red', 'green', 'blue'].map((k) => ((c['color'] as Map)['components'] as Map)[k]).join(),
          ),
      ];
      expect(colours, [(dark: false, rgb: '0xFB0xF60xF1'), (dark: true, rgb: '0x2B0x240x38')]);
      const sizes = {'LaunchImage.png': 160, 'LaunchImage@2x.png': 320, 'LaunchImage@3x.png': 480};
      sizes.forEach((file, px) {
        final info = pngInfo('$xc/LaunchImage.imageset/$file');
        expect((info.width, info.height, info.colourType), (px, px, 6), reason: '$file: clear around the pig');
      });
    });
  });

  group('the ears', () {
    // In the pig's own units (0-200): the raised ear's outer edge spans x 30-68, on the left. The
    // flopped ear is drawn at x 14-66 in a group that mirrors it (translate(200 0) scale(-1 1)), so
    // it lands at x 134-186, on the right.
    bool startsAt(VectorPath p, double x, double y) => p.numbers.length > 1 && p.numbers[0] == x && p.numbers[1] == y;

    for (final drawable in ['ic_launcher_foreground', 'ic_launcher_monochrome', 'ic_notification', 'splash_pig', 'splash_icon']) {
      test('$drawable: one ear up on the left, the flopped one mirrored onto the right', () {
        final paths = vectorPaths('$res/drawable/$drawable.xml');
        final body = paths.singleWhere((p) => startsAt(p, 22, 142));
        // Where a path's points land, in the pig's units (its body's group is the pig's own).
        List<double> landing(VectorPath p, int axis) => [
              for (var i = axis; i < p.numbers.length; i += 2)
                axis == 0
                    ? (p.sx * p.numbers[i] + p.tx - body.tx) / body.sx
                    : (p.sy * p.numbers[i] + p.ty - body.ty) / body.sy,
            ];

        final raised = paths.singleWhere((p) => startsAt(p, 34, 96));
        expect(landing(raised, 0).reduce(min), closeTo(30, 1e-6));
        expect(landing(raised, 0).reduce(max), closeTo(68, 1e-6));

        final flopped = paths.singleWhere((p) => startsAt(p, 36, 98));
        expect(flopped.sx, closeTo(-body.sx, 1e-9), reason: 'mirrored left to right');
        expect(flopped.sy, closeTo(body.sy, 1e-9), reason: 'not upside down');
        expect(landing(flopped, 0).reduce(min), closeTo(134, 1e-6));
        expect(landing(flopped, 0).reduce(max), closeTo(186, 1e-6));
        expect(landing(flopped, 1).reduce(min), closeTo(58, 1e-6));
        expect(landing(flopped, 1).reduce(max), closeTo(98, 1e-6));
      });
    }

    test('the rendered icons draw the raised ear on the left and the flopped one on the right', () {
      const innerEar = [0xF3, 0xA3, 0xB9, 255];
      void expectNear(List<int> got, List<int> want, String reason) {
        for (var c = 0; c < 4; c++) {
          expect((got[c] - want[c]).abs(), lessThanOrEqualTo(3), reason: '$reason: $got, not $want');
        }
      }

      // The iOS launch image: the calm pig at 2.4 px per pig unit, clear around it.
      final launch = decodePng('$xc/LaunchImage.imageset/LaunchImage@3x.png');
      List<int> launchAt(double x, double y) => launch.rgba((x * 2.4).floor(), (y * 2.4).floor());
      expectNear(launchAt(168, 84), innerEar, 'launch image: the flopped ear, mirrored to the right');
      expectNear(launchAt(40, 66), innerEar, 'launch image: the raised ear, on the left');
      expect(launchAt(25, 85)[3], 0, reason: 'clear on the left, where the flopped ear is drawn before its mirror');

      // The App Store icon: the pig placed at (66, 92) at 1.9 icon units per pig unit, 2 px per icon unit.
      final store = decodePng('$xc/AppIcon.appiconset/Icon-App-1024x1024@1x.png');
      List<int> storeAt(double x, double y) => store.rgba(((66 + 1.9 * x) * 2).floor(), ((92 + 1.9 * y) * 2).floor());
      expectNear(storeAt(168, 84), innerEar, 'store icon: the flopped ear, mirrored to the right');
      expectNear(storeAt(40, 66), innerEar, 'store icon: the raised ear, on the left');
    });
  });

  group('PNG metadata', () {
    // The repo is public: an image keeps only what draws it, never text, dates or camera data.
    const allowed = {'IHDR', 'PLTE', 'tRNS', 'sBIT', 'sRGB', 'IDAT', 'IEND'};

    test('every PNG of the app and the goldens has image chunks only', () {
      final pngs = [
        for (final dir in [res, xc, 'test/goldens'])
          ...Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.png')),
      ];
      expect(pngs.length, greaterThan(150));
      for (final png in pngs) {
        expect(pngChunkTypes(png.readAsBytesSync()).toSet().difference(allowed), isEmpty, reason: png.path);
      }
    });

    test('control: a tEXt chunk is caught', () {
      final png = File('$res/mipmap-mdpi/ic_launcher.png').readAsBytesSync();
      expect(pngChunkTypes(png).toSet().difference(allowed), isEmpty);
      // The same image with a tEXt chunk ("k" = "v") after IHDR, which ends at byte 33. Only the
      // chunk types are read, so its CRC can stay zero.
      final tagged = Uint8List.fromList([
        ...png.sublist(0, 33),
        ...[0, 0, 0, 3, ...'tEXt'.codeUnits, 0x6B, 0x00, 0x76, 0, 0, 0, 0],
        ...png.sublist(33),
      ]);
      expect(pngChunkTypes(tagged).toSet().difference(allowed), {'tEXt'});
    });
  });
}
