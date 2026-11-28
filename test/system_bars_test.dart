import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/device.dart';
import 'package:piggybow/core/system_bars.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import 'helpers.dart';

/// The system bars over every page: see-through, so the page shows behind
/// them, with icons that read on the page in light and dark. O1 Welcome
/// showed a grey band under the status bar (decision 65), and Android 14
/// drew an opaque black bar behind the gesture handle (the Play dry run);
/// Android 15+ already draws the app there.
void main() {
  /// What the app last asked the system for, as both bars show it. Android
  /// takes the status bar's fields from what's at the top of the screen and
  /// the navigation bar's from what's at the bottom: under an AppBar
  /// ([statusBar] false) the status bar is the AppBar's own style.
  void expectPageSystemBars(bool dark, String where, {bool statusBar = true}) {
    final style = SystemChrome.latestStyle!;
    final icons = dark ? Brightness.light : Brightness.dark;
    if (statusBar) {
      expect(style.statusBarColor, Colors.transparent, reason: where);
      expect(
        style.statusBarIconBrightness,
        icons,
        reason: '$where: Android status icons',
      );
      expect(
        style.statusBarBrightness,
        dark ? Brightness.dark : Brightness.light,
        reason: '$where: iOS status icons',
      );
      expect(style.systemStatusBarContrastEnforced, isFalse, reason: where);
    }
    expect(
      style.systemNavigationBarColor,
      Colors.transparent,
      reason: '$where: navigation bar',
    );
    expect(
      style.systemNavigationBarDividerColor,
      Colors.transparent,
      reason: '$where: navigation bar divider',
    );
    expect(
      style.systemNavigationBarIconBrightness,
      icons,
      reason: '$where: navigation icons',
    );
    expect(
      style.systemNavigationBarContrastEnforced,
      isFalse,
      reason: '$where: no scrim behind three-button navigation',
    );
  }

  /// A style no page asks for, so a stale one from the last test can't pass.
  Future<void> forgetTheLastStyle(WidgetTester tester) async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFFF0000),
        systemNavigationBarColor: Color(0xFFFF0000),
      ),
    );
    await tester.pump();
    expect(SystemChrome.latestStyle!.statusBarColor, const Color(0xFFFF0000));
    expect(
      SystemChrome.latestStyle!.systemNavigationBarColor,
      const Color(0xFFFF0000),
    );
  }

  test('the style: both bars see-through, icons for the theme', () {
    for (final brightness in Brightness.values) {
      final s = pageSystemBars(brightness);
      expect(s.statusBarColor, Colors.transparent);
      expect(s.systemNavigationBarColor, Colors.transparent);
      expect(s.systemNavigationBarDividerColor, Colors.transparent);
      expect(s.systemStatusBarContrastEnforced, isFalse);
      expect(s.systemNavigationBarContrastEnforced, isFalse);
      expect(s.systemNavigationBarIconBrightness, s.statusBarIconBrightness);
    }
    expect(
      pageSystemBars(Brightness.light).statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      pageSystemBars(Brightness.dark).statusBarIconBrightness,
      Brightness.light,
    );
  });

  testWidgets('edge to edge: drawn behind both bars on every Android version', (
    tester,
  ) async {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add('${call.method} ${call.arguments}');
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await enableEdgeToEdge();
    expect(
      calls,
      contains('SystemChrome.setEnabledSystemUIMode SystemUiMode.edgeToEdge'),
    );
  });

  test('main() asks for edge to edge before the first frame', () {
    final source = File('lib/main.dart').readAsStringSync();
    final call = source.indexOf('enableEdgeToEdge()');
    expect(call, greaterThan(-1), reason: 'main() calls enableEdgeToEdge');
    expect(
      call,
      lessThan(source.indexOf('runApp(')),
      reason: 'before any runApp',
    );
  });

  group('Android 7 (no dark navigation icons)', () {
    test('a light page keeps a black bar under the white icons', () {
      final light = pageSystemBars(Brightness.light, darkNavIcons: false);
      expect(light.systemNavigationBarColor, Colors.black);
      expect(light.systemNavigationBarIconBrightness, Brightness.light);
      // The status bar is as on every other phone.
      expect(light.statusBarColor, Colors.transparent);
      expect(light.statusBarIconBrightness, Brightness.dark);
      // A dark page was already right: see-through, light icons.
      final dark = pageSystemBars(Brightness.dark, darkNavIcons: false);
      expect(dark.systemNavigationBarColor, Colors.transparent);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    });

    test('which phones: Android 8 (SDK 26) and later draw dark icons', () {
      expect(navIconsCanBeDarkOn(24), isFalse);
      expect(navIconsCanBeDarkOn(25), isFalse);
      expect(navIconsCanBeDarkOn(26), isTrue);
      expect(navIconsCanBeDarkOn(36), isTrue);
      expect(navIconsCanBeDarkOn(null), isTrue, reason: 'unknown: as before');
    });

    testWidgets('the SDK level: the phone\'s answer, else null', (
      tester,
    ) async {
      const channel = MethodChannel(settingsChannel);
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == androidSdkMethod ? 25 : null,
      );
      expect(await readAndroidSdk(), 25);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'nope'),
      );
      expect(await readAndroidSdk(), isNull, reason: 'a failed call');
      // What iOS answers (no handler there): the same as no answer.
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw MissingPluginException(),
      );
      expect(await readAndroidSdk(), isNull, reason: 'no handler (iOS)');
    });

    test('MainActivity answers it, under the same name', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/burrowsoft/piggybow/MainActivity.kt',
      ).readAsStringSync();
      expect(kotlin, contains('ANDROID_SDK = "$androidSdkMethod"'));
      expect(kotlin, contains('result.success(Build.VERSION.SDK_INT)'));
    });

    test('main() sets it before the first frame', () {
      final source = File('lib/main.dart').readAsStringSync();
      final set = source.indexOf('navIconsCanBeDark = navIconsCanBeDarkOn(');
      expect(set, greaterThan(-1));
      expect(set, lessThan(source.indexOf('runApp(')));
    });

    testWidgets('Home on Android 7, light: the black bar', (tester) async {
      navIconsCanBeDark = false;
      addTearDown(() => navIconsCanBeDark = true);
      await forgetTheLastStyle(tester);
      final app = TestApp()..prefs.appearance = 'light';
      await tester.runAsync(app.openJournal);
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(byId('home-screen'), findsOneWidget);
      final style = SystemChrome.latestStyle!;
      expect(style.systemNavigationBarColor, Colors.black);
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
    });
  });

  for (final appearance in ['light', 'dark']) {
    final dark = appearance == 'dark';

    testWidgets('O1 Welcome: see-through bars, icons for $appearance', (
      tester,
    ) async {
      await forgetTheLastStyle(tester);
      final app = TestApp(onboarded: false)..prefs.appearance = appearance;
      await tester.runAsync(app.openJournal);
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(byId('onb-welcome'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing, reason: 'no bar of its own');
      expectPageSystemBars(dark, 'O1');
    });

    testWidgets('Home: see-through navigation bar, icons for $appearance', (
      tester,
    ) async {
      await forgetTheLastStyle(tester);
      final app = TestApp()..prefs.appearance = appearance;
      await tester.runAsync(app.openJournal);
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(byId('home-screen'), findsOneWidget);
      // Home has an AppBar: the status bar is its style.
      expect(find.byType(AppBar), findsOneWidget);
      expectPageSystemBars(dark, 'Home', statusBar: false);
    });

    testWidgets('the celebration: see-through bars, icons for $appearance', (
      tester,
    ) async {
      await forgetTheLastStyle(tester);
      final app = TestApp()..prefs.appearance = appearance;
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        final t = DateTime.utc(2026, 9, 20);
        await app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 1000,
            createdAt: t,
            updatedAt: t,
          ),
        );
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 1000,
          currency: 'THB',
          localDate: '2026-10-01',
        );
      });
      await app.pump(tester);
      for (
        var i = 0;
        i < 40 && byId('goal-done-screen').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(byId('goal-done-screen'), findsOneWidget);
      expectPageSystemBars(dark, 'the celebration');
    });
  }
}
