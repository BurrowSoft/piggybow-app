@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/fixtures/launch_fixture.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/theme/theme.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/goldens.dart';

/// Piggybow Plus's themes (plus-spec §1): the default and each Plus theme,
/// light and dark. Home on the store screenshots' journal (STORE1: the plan's
/// week, "Trip to Japan" at 32 %), and each theme's swatch card: its colours
/// and the contrast of the pairs the app draws text and buttons with.
void main() {
  setUpAll(loadAppFonts);

  final themes = <PlusPalette?>[null, ...PlusPalette.values];
  String nameOf(PlusPalette? theme) => theme?.name ?? 'default';

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    addTearDown(tester.view.reset);
  }

  for (final (i, theme) in themes.indexed) {
    for (final brightness in Brightness.values) {
      final appearance = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('Home in ${nameOf(theme)}, $appearance', (tester) async {
        phone(tester);
        final fixture = LaunchFixture.byId('STORE1', '{"cases": []}');
        final app = TestApp(currency: 'USD', clock: fixture.clock)
          ..prefs.appearance = appearance;
        if (theme != null) {
          app.prefs.palette = encodePalette(theme, DateTime.utc(2099));
        }
        await tester.runAsync(app.openJournal);
        expect(await tester.runAsync(() => fixture.write(app.journal)), isNull);
        await app.pump(tester);
        final pigLine = byId('home-pig-line');
        for (var k = 0; k < 40 && pigLine.evaluate().isEmpty; k++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(byId('home-screen'), findsOneWidget);
        await expectGolden(
          tester,
          find.byType(MaterialApp),
          screen: 'theme-home',
          state: nameOf(theme),
          stateId: 'TH$i',
          brightness: brightness,
          width: 360,
          textScale: 1,
        );
      });

      testWidgets('the swatch of ${nameOf(theme)}, $appearance', (
        tester,
      ) async {
        phone(tester);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(brightness, plusPalette: theme),
            home: _Swatch(
              name: nameOf(theme),
              colours: paletteColours(theme, brightness),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectGolden(
          tester,
          find.byType(MaterialApp),
          screen: 'theme-swatch',
          state: nameOf(theme),
          stateId: 'TS$i',
          brightness: brightness,
          width: 360,
          textScale: 1,
        );
      });
    }
  }
}

/// WCAG 2 contrast between two colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// One theme's colours, and its text and buttons with their contrast.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.colours});

  final String name;
  final PiggybowPalette colours;

  @override
  Widget build(BuildContext context) {
    final c = colours;
    String ratio(Color fg, Color bg) =>
        '${contrast(fg, bg).toStringAsFixed(1)}:1';
    final tokens = <(String, Color)>[
      ('page', c.background),
      ('text', c.text),
      ('muted', c.mutedText),
      ('accent', c.accent),
      ('on accent', c.onAccent),
      ('card', c.pillBackground),
    ];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: c.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (label, colour) in tokens)
                    SizedBox(
                      width: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: colour,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.mutedText),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$label\n${_hex(colour)}',
                            style: TextStyle(color: c.mutedText, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Body text  ${ratio(c.text, c.background)}',
                style: TextStyle(color: c.text, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Muted text  ${ratio(c.mutedText, c.background)}',
                style: TextStyle(color: c.mutedText, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Accent text  ${ratio(c.accent, c.background)}',
                style: TextStyle(color: c.accent, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text(
                  'Button  ${ratio(c.onAccent, c.accent)}',
                  style: TextStyle(color: c.onAccent, fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.pillBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On a card  ${ratio(c.text, c.pillBackground)}',
                      style: TextStyle(color: c.text, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Accent on a card  ${ratio(c.accent, c.pillBackground)}',
                      style: TextStyle(color: c.accent, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Muted on a card  '
                      '${ratio(c.mutedText, c.pillBackground)}',
                      style: TextStyle(color: c.mutedText, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
