import 'dart:convert';
import 'dart:io';
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
}
