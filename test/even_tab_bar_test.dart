import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/shell/even_tab_bar.dart';

import 'helpers.dart';

// The bottom tabs evenly spaced: equal space at the left, between every two
// labels and at the right; each tab's tap area from mid-gap to mid-gap, at
// least 48 dp; every indicator on screen and clear of its neighbours'; no
// label cut, in every shipped language, at 360 dp, a small 320 dp and a roomy
// 411 dp, at normal and the largest text. At 320 dp a space may widen, only as
// far as it must to keep two indicators apart or one on the bar.

const _tabs = ['home', 'timeline', 'summary', 'me'];
const _locales = ['en'];

Map<String, dynamic> _arb(String code) =>
    json.decode(File('lib/l10n/app_$code.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The label text drawn in tab [id].
Finder _label(String id, String text) =>
    find.descendant(of: byId('tab-$id'), matching: find.text(text));

void main() {
  setUpAll(() async {
    // The real fonts (Poppins, and Prompt for Thai): the widths users see. The
    // default test font draws every glyph 1 em wide.
    final poppins = FontLoader('Poppins')
      ..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Poppins-Medium.ttf'));
    final prompt = FontLoader('Prompt')
      ..addFont(rootBundle.load('assets/fonts/Prompt-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Prompt-Medium.ttf'));
    await Future.wait([poppins.load(), prompt.load()]);
  });

  group('EvenTabLayout', () {
    test(
      'equal margins and gaps; the tap areas tile the bar, mid-gap to mid-gap',
      () {
        final l = EvenTabLayout.compute(360, [41, 55, 80, 18])!;
        expect(l.gap, closeTo((360 - 194) / 5, 1e-9));
        final lefts = [
          for (var i = 0; i < 4; i++) l.centers[i] - [41, 55, 80, 18][i] / 2,
        ];
        final rights = [
          for (var i = 0; i < 4; i++) l.centers[i] + [41, 55, 80, 18][i] / 2,
        ];
        expect(lefts.first, closeTo(l.gap, 1e-9));
        expect(360 - rights.last, closeTo(l.gap, 1e-9));
        for (var i = 0; i < 3; i++) {
          expect(lefts[i + 1] - rights[i], closeTo(l.gap, 1e-9));
          expect(l.edges[i + 1], closeTo(rights[i] + l.gap / 2, 1e-9));
        }
        expect(l.edges.first, 0);
        expect(l.edges.last, 360);
      },
    );

    test('null when a tap area would be under 48 dp or an indicator off the bar', () {
      // Long labels: 20 dp of room, but the last indicator alone needs 22.
      expect(EvenTabLayout.compute(360, [100, 100, 120, 20]), isNull);
      // Short labels in 200 dp: no room to keep the indicators on the bar and apart.
      expect(EvenTabLayout.compute(200, [40, 40, 40, 10]), isNull);
      expect(EvenTabLayout.compute(360, [41, 55, 80, 18])!.even, isTrue);
      // The Reviewer (27 Nov): 4 × 20 dp labels in 220 dp, evenly spaced, pass
      // the 48 dp rule and the edges, yet their centres are only 48 apart, so
      // the 64 dp indicators would overlap; and there is no room to part them.
      final close = EvenTabLayout.compute(220, [20, 20, 20, 20], minHit: 48);
      expect(close, isNull);
      // The same labels with room: even, centres 64 apart.
      final roomy = EvenTabLayout.compute(300, [20, 20, 20, 20])!;
      expect(roomy.even, isTrue);
      expect(roomy.centers[1] - roomy.centers[0], closeTo(64, 1e-9));
    });

    test('a narrow screen: only the spaces that must widen do, the others stay equal', () {
      // 320 dp, a short last label (as fr "Moi"): equal spaces (17.6 dp)
      // would put the last two indicators 57.6 dp apart and the last one off
      // the bar. The last gap widens to 24 and the right margin to 22; the
      // other three spaces share the rest equally: 14 dp each.
      final l = EvenTabLayout.compute(320, [76, 76, 60, 20])!;
      expect(l.even, isFalse);
      expect(l.gap, closeTo(14, 1e-9));
      for (final k in [0, 1, 2]) {
        expect(l.gaps[k], closeTo(l.gap, 1e-9));
      }
      expect(l.gaps[3], closeTo(24, 1e-9));
      expect(l.gaps[4], closeTo(22, 1e-9));
      expect(l.centers[3] - l.centers[2], closeTo(64, 1e-9));
      expect(l.centers[3] + 32, closeTo(320, 1e-9));
      expect(l.hitWidth(3), greaterThanOrEqualTo(48));
      expect(l.edges.first, 0);
      expect(l.edges.last, 320);
      // A little longer labels: the three shared spaces would be 11.3 dp,
      // under the 12 dp floor (labels nearly touching): refused, so the
      // text steps down instead.
      expect(EvenTabLayout.compute(320, [80, 80, 60, 20]), isNull);
    });
  });

  for (final width in [320.0, 360.0, 411.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final code in _locales) {
        testWidgets(
          '$code, $width dp, text ×$scale: even spacing, tap areas, no cut label',
          (tester) async {
            tester.view.devicePixelRatio = 3;
            tester.view.physicalSize = Size(width * 3, 800 * 3);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final semantics = tester.ensureSemantics();
            final app = TestApp(
              chosenLocale: code,
              shippedLocales: ['en', if (code != 'en') code],
            );
            await app.pump(tester);
            final arb = _arb(code);
            final labels = {
              'home': arb['tabHome'] as String,
              'timeline': arb['tabTimeline'] as String,
              'summary': arb['tabSummary'] as String,
              'me': arb['tabMe'] as String,
            };
            final rects = [
              for (final id in _tabs) tester.getRect(_label(id, labels[id]!)),
            ];
            final hits = [
              for (final id in _tabs) tester.getRect(byId('tab-$id')),
            ];

            // The spaces: left margin, the three gaps, right margin.
            final spaces = [
              rects.first.left,
              for (var i = 0; i < 3; i++) rects[i + 1].left - rects[i].right,
              width - rects.last.right,
            ];
            // The least each needs: 12 dp; more where a margin keeps its 64 dp
            // indicator on the bar, or a gap keeps two neighbouring indicators
            // apart.
            final w = [for (final r in rects) r.width];
            final least = [
              32 - w.first / 2,
              for (var i = 1; i < 4; i++) 64 - (w[i - 1] + w[i]) / 2,
              32 - w.last / 2,
            ].map((m) => m < 12 ? 12.0 : m).toList();
            final factors = [
              for (final id in _tabs)
                tester
                        .renderObject<RenderParagraph>(_label(id, labels[id]!))
                        .textScaler
                        .scale(100) /
                    100,
            ];
            final printable = spaces
                .map((s) => s.toStringAsFixed(1))
                .join(' / ');
            final lo = spaces.reduce((a, b) => a < b ? a : b);
            final hi = spaces.reduce((a, b) => a > b ? a : b);
            debugPrint(
              'TABS $code ${width.toInt()} dp ×$scale: '
              'text ${factors.first.toStringAsFixed(2)}; '
              '${hi - lo <= 1 ? 'even' : 'widened'}; spaces $printable; '
              'labels ${w.map((x) => x.toStringAsFixed(1)).join(' ')}; '
              'hits ${hits.map((r) => r.width.toStringAsFixed(1)).join(' ')}',
            );
            // One text size for the four labels.
            for (final f in factors) {
              expect(f, closeTo(factors.first, 1e-9));
            }
            // 360 dp and wider: every space equal (±1 dp).
            if (width >= 360) {
              expect(
                hi - lo,
                lessThanOrEqualTo(1.0),
                reason: 'spaces $printable',
              );
            }
            // Everywhere: each space at least what it needs, and any space
            // wider than the others (±1 dp) widened only to what it needs.
            for (var k = 0; k < 5; k++) {
              expect(
                spaces[k],
                greaterThanOrEqualTo(least[k] - 0.5),
                reason: 'space $k: $printable',
              );
              if (spaces[k] > lo + 1) {
                expect(
                  spaces[k],
                  closeTo(least[k], 1.0),
                  reason: 'space $k widened past its need: $printable',
                );
              }
            }
            // No two indicators overlap: the labels' centres 64 dp apart or more.
            for (var i = 1; i < 4; i++) {
              expect(
                rects[i].center.dx - rects[i - 1].center.dx,
                greaterThanOrEqualTo(64 - 0.5),
                reason: '${_tabs[i - 1]} and ${_tabs[i]} indicators',
              );
            }

            // The tap areas tile the bar with no hole and no overlap, each ≥ 48 dp,
            // and each holds its own label.
            expect(hits.first.left, closeTo(0, 0.5));
            expect(hits.last.right, closeTo(width, 0.5));
            for (var i = 0; i < 4; i++) {
              expect(
                hits[i].width,
                greaterThanOrEqualTo(48),
                reason: '${_tabs[i]} ${hits[i].width}',
              );
              if (i < 3) expect(hits[i + 1].left, closeTo(hits[i].right, 0.5));
              expect(rects[i].left, greaterThanOrEqualTo(hits[i].left - 0.5));
              expect(rects[i].right, lessThanOrEqualTo(hits[i].right + 0.5));
            }

            // No label cut or wrapped: one line, all of it drawn.
            for (final id in _tabs) {
              final p = tester.renderObject<RenderParagraph>(
                _label(id, labels[id]!),
              );
              expect(p.didExceedMaxLines, isFalse, reason: '$id cut');
              expect(
                p.size.width,
                greaterThanOrEqualTo(
                  p.getMaxIntrinsicWidth(double.infinity) - 0.5,
                ),
                reason: '$id narrower than its text',
              );
            }

            // Every tab's indicator (64 dp) on the bar, the selected one's too.
            for (final id in _tabs) {
              final pill = tester.getRect(
                find.descendant(
                  of: byId('tab-$id'),
                  matching: find.byType(NavigationIndicator),
                ),
              );
              expect(
                pill.left,
                greaterThanOrEqualTo(-0.5),
                reason: '$id indicator',
              );
              expect(
                pill.right,
                lessThanOrEqualTo(width + 0.5),
                reason: '$id indicator',
              );
            }

            // Read as its name, then "Tab 3 of 4".
            final spoken = tester
                .getSemantics(byId('tab-summary'))
                .getSemanticsData()
                .label;
            expect(spoken, startsWith(arb['tabSummary'] as String));
            expect(spoken, contains('3'));
            semantics.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'a tap anywhere in a tab area opens that tab; the selected state follows',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await TestApp().pump(tester);
      for (final id in ['me', 'summary', 'timeline', 'home']) {
        final area = tester.getRect(byId('tab-$id'));
        // Near the area's own edge, away from its label: still that tab.
        await tester.tapAt(Offset(area.left + 3, area.center.dy));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(byId('tab-$id'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
          reason: id,
        );
        // A screen reader can open it too: the tab node carries the tap action.
        expect(
          tester
              .getSemantics(byId('tab-$id'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$id has no tap action',
        );
      }
      semantics.dispose();
    },
  );
}
