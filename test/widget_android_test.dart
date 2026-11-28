import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/widget/widget_sync.dart';
import 'package:piggybow/router.dart';

import 'helpers.dart';

/// The home-screen widget's Android side (feature 16), as its files declare
/// it: the receiver (not exported, offered only in builds with Plus, woken by
/// the system's updates and the clock's changes); its provider (home screen
/// only, no periodic updates); the channel's method, the same on both sides;
/// the words Android itself shows, the app's own; the widget's file, never
/// backed up. And Me → Your privacy says so, in builds with Plus only.
void main() {
  String read(String path) => File(path).readAsStringSync();
  final manifest = read('android/app/src/main/AndroidManifest.xml');
  final arb = jsonDecode(read('lib/l10n/app_en.arb')) as Map<String, dynamic>;

  String receiver() {
    final at = manifest.indexOf('android:name=".widget.PiggybowWidget"');
    expect(at, greaterThan(0), reason: 'the receiver is declared');
    return manifest.substring(manifest.lastIndexOf('<receiver', at), manifest.indexOf('</receiver>', at));
  }

  test('the receiver: not exported, offered only in builds with Plus, woken '
      "by the system's updates and the clock's changes", () {
    final r = receiver();
    expect(r, contains('android:exported="false"'));
    expect(r, contains('android:enabled="@bool/widget_enabled"'));
    expect(
      RegExp(r'<action android:name="([^"]+)"/>').allMatches(r).map((m) => m.group(1)),
      [
        'android.appwidget.action.APPWIDGET_UPDATE',
        'android.intent.action.TIME_SET',
        'android.intent.action.TIMEZONE_CHANGED',
      ],
    );
    expect(r, contains('android:resource="@xml/piggybow_widget_info"'));
    expect(
      read('android/app/build.gradle.kts'),
      contains('resValue("bool", "widget_enabled", (dartDefines["PLUS_ENABLED"] == "true").toString())'),
    );
  });

  test('its provider: home screen only, and no periodic updates', () {
    final info = read('android/app/src/main/res/xml/piggybow_widget_info.xml');
    expect(info, contains('android:widgetCategory="home_screen"'));
    expect(info, contains('android:updatePeriodMillis="0"'));
    expect(info, contains('android:description="@string/widget_description"'));
  });

  test("the channel's method is the same on both sides", () {
    expect(
      read('android/app/src/main/kotlin/com/burrowsoft/piggybow/MainActivity.kt'),
      contains('const val UPDATE_WIDGET = "${ChannelWidgetBridge.method}"'),
    );
  });

  test("the words Android itself shows are the app's own", () {
    final res = read('android/app/src/main/res/values/widget.xml');
    String string(String name) =>
        RegExp('<string name="$name">([^<]*)</string>').firstMatch(res)!.group(1)!.replaceAll(r"\'", "'");
    expect(string('widget_description'), arb['widgetDescription']);
    expect(string('widget_tap_to_open'), arb['widgetLocked']);
    // The widget's + says what #58's shortcut says: one "Add a spend".
    expect(res, isNot(contains('name="widget_add"')));
    for (final layout in ['widget_small', 'widget_wide']) {
      expect(
        read('android/app/src/main/res/layout/$layout.xml'),
        contains('android:contentDescription="@string/shortcut_add_long"'),
        reason: layout,
      );
    }
  });

  // Wiring item 15 (#72 with #58): the widget's taps go through #58's launch
  // actions, and from the widget the lock screen always comes first.
  test("the widget's taps: #58's action for +, its own for the widget, both "
      'marked as from the widget', () {
    final widget = read('android/app/src/main/kotlin/com/burrowsoft/piggybow/widget/PiggybowWidget.kt');
    expect(widget, contains('.setAction(MainActivity.ACTION_ADD_SPEND)'));
    expect(widget, contains('.putExtra(MainActivity.EXTRA_FROM_WIDGET, true)'));
    expect(widget, contains('.setAction(MainActivity.ACTION_OPEN_FROM_WIDGET)'));
    expect(widget, isNot(contains('const val ACTION_ADD_SPEND')), reason: "MainActivity's, once");
    final main = read('lib/main.dart').replaceAll(RegExp(r'\s+'), ' ');
    expect(main, contains('PlatformLaunchActions(onFromWidget: () => appLock?.lockNow())'));
  });

  test("the widget's file is never backed up: every rule names only the "
      "journal and the app's settings", () {
    for (final path in [
      'android/app/src/main/res/xml/data_extraction_rules.xml',
      'android/app/src/main/res/xml-v28/backup_rules.xml',
      'android/app/src/main/res/xml/backup_rules.xml',
    ]) {
      final rules = read(path);
      expect(rules, isNot(contains('piggybow_widget')), reason: path);
      final included = {for (final m in RegExp(r'<include [^>]*path="([^"]+)"').allMatches(rules)) m.group(1)};
      expect(included.difference({'journal.db', 'FlutterSharedPreferences.xml'}), isEmpty, reason: path);
    }
  });

  for (final plus in [true, false]) {
    testWidgets('Me → Your privacy ${plus ? 'with' : 'without'} Plus: the '
        "widget's line ${plus ? 'is' : "isn't"} there", (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final app = TestApp(config: AppConfig(flavor: Flavor.staging, plusEnabled: plus));
      await app.pump(tester, location: MeRoutes.privacy);
      expect(byId('me-privacy-screen'), findsOneWidget);
      expect(find.text(arb['mePrivacyWidget'] as String), plus ? findsOneWidget : findsNothing);
    });
  }

  // Wiring item 16 (#72 with #51): each Plus theme's accent and empty track
  // are the app's own, light and dark, and the widget picks them by the
  // snapshot's theme id (palettes.dart's names; "default" otherwise).
  test("each theme's accent and track, light and dark, as the app's", () {
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    String colour(String xml, String name) =>
        RegExp('<color name="$name">(#[0-9A-F]{6})</color>').firstMatch(xml)![1]!;
    final light = read('android/app/src/main/res/values/widget.xml');
    final dark = read('android/app/src/main/res/values-night/widget.xml');
    final widget = read('android/app/src/main/kotlin/com/burrowsoft/piggybow/widget/PiggybowWidget.kt');
    for (final palette in [null, ...PlusPalette.values]) {
      final suffix = palette == null ? '' : '_${palette.name}';
      for (final (xml, brightness) in [(light, Brightness.light), (dark, Brightness.dark)]) {
        final app = paletteColours(palette, brightness);
        expect(colour(xml, 'widget_accent$suffix'), hex(app.accent), reason: '$palette $brightness');
        expect(colour(xml, 'widget_track$suffix'), hex(app.rainbowTrack), reason: '$palette $brightness');
      }
      if (palette == null) continue;
      final t = palette.name;
      expect(read('android/app/src/main/res/drawable/widget_add_background_$t.xml'), contains('@color/widget_accent_$t"'));
      for (var i = 1; i <= 5; i++) {
        expect(read('android/app/src/main/res/drawable/widget_track_${t}_$i.xml'), contains('@color/widget_track_$t"'));
      }
      expect(widget, contains('"$t" -> R.drawable.widget_add_background_$t'));
      expect(widget, contains('R.drawable.widget_track_${t}_1'));
    }
  });
}
