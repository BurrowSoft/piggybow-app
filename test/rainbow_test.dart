import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/goal/rainbow.dart';
import 'package:piggybow/theme/theme.dart';

/// The rainbow (plan §3.5): which arcs are filled at each percent, the
/// colours and the tracks, the motion (none under reduce-motion), and that
/// it's read out only where it's given a label.
class _Arcs implements Canvas {
  /// Each arc's colour as ARGB (Paint keeps 32-bit floats, so a Color read
  /// back can differ from the one set in its last bits) and its sweep.
  final arcs = <({int colour, double sweep})>[];

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) {
    expect(startAngle, math.pi, reason: 'every arc starts at the left foot');
    arcs.add((colour: paint.color.toARGB32(), sweep: sweepAngle / math.pi));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The coloured arcs painted at [fill], as (arc index, share of its sweep).
List<(int, double)> filled(double fill) {
  final canvas = _Arcs();
  RainbowPainter(
    fill: fill,
    track: PiggybowPalette.light.rainbowTrack,
  ).paint(canvas, const Size(240, 132));
  return [
    for (final a in canvas.arcs)
      if (a.colour != PiggybowPalette.light.rainbowTrack.toARGB32())
        (
          Rainbow.arcColours
              .map((c) => c.toARGB32())
              .toList()
              .indexOf(a.colour),
          a.sweep,
        ),
  ];
}

void main() {
  test('each arc is 20 %; the outer one fills first; a part fills partly', () {
    expect(filled(0), isEmpty, reason: 'only the tracks (no dots)');
    final at19 = filled(0.19);
    expect(at19, hasLength(1));
    expect(at19.single.$1, 0);
    expect(at19.single.$2, closeTo(0.95, 1e-9));
    expect(filled(0.20), [(0, 1.0)]);
    final at32 = filled(0.32);
    expect(at32.map((a) => a.$1), [0, 1]);
    expect(at32.last.$2, closeTo(0.6, 1e-9));
    expect(filled(0.60).map((a) => a.$1), [0, 1, 2]);
    final at99 = filled(0.99);
    expect(at99.map((a) => a.$1), [0, 1, 2, 3, 4]);
    expect(at99.last.$2, closeTo(0.95, 1e-9));
    expect(filled(1.0), [for (var i = 0; i < 5; i++) (i, 1.0)]);
  });

  test('at each multiple of 20 %, whole arcs only: no dot on the next one', () {
    for (final p in [20, 40, 60, 80, 100]) {
      expect(filled(p / 100), [
        for (var i = 0; i < p ~/ 20; i++) (i, 1.0),
      ], reason: '$p %');
    }
  });

  test('five tracks always, in the light or the dark colour', () {
    for (final track in [
      PiggybowPalette.light.rainbowTrack,
      PiggybowPalette.dark.rainbowTrack,
    ]) {
      final canvas = _Arcs();
      RainbowPainter(
        fill: 0.5,
        track: track,
      ).paint(canvas, const Size(480, 264));
      expect(
        canvas.arcs.where((a) => a.colour == track.toARGB32()),
        hasLength(5),
      );
      expect(
        canvas.arcs
            .where((a) => a.colour == track.toARGB32())
            .map((a) => a.sweep),
        everyElement(1.0),
      );
    }
    expect(Rainbow.arcColours, const [
      Color(0xFFE27D9A),
      Color(0xFFF2A07B),
      Color(0xFFF3C24F),
      Color(0xFF8CCFB0),
      Color(0xFF9B84D6),
    ]);
    expect(PiggybowPalette.light.rainbowTrack, const Color(0xFFECE6F0));
    expect(PiggybowPalette.dark.rainbowTrack, const Color(0xFF3A3350));
  });

  Finder painter() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is RainbowPainter,
  );
  double fillOf(WidgetTester tester) =>
      (tester.widget<CustomPaint>(painter()).painter! as RainbowPainter).fill;

  Future<void> show(
    WidgetTester tester,
    int percent, {
    Brightness brightness = Brightness.light,
    String? label,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Center(
        child: SizedBox(
          width: 240,
          child: Rainbow(percent: percent, semanticLabel: label),
        ),
      ),
    ),
  );

  testWidgets('a save animates from the old fill to the new one', (
    tester,
  ) async {
    await show(tester, 20);
    expect(fillOf(tester), 0.2, reason: 'no animation on first show');
    await show(tester, 60);
    await tester.pump(const Duration(milliseconds: 300));
    expect(fillOf(tester), allOf(greaterThan(0.2), lessThan(0.6)));
    await tester.pumpAndSettle();
    expect(fillOf(tester), 0.6);
  });

  testWidgets('reduce-motion: straight to the new fill', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await show(tester, 20);
    await show(tester, 60);
    await tester.pump();
    expect(fillOf(tester), 0.6);
  });

  testWidgets('dark mode uses the dark track', (tester) async {
    await show(tester, 40, brightness: Brightness.dark);
    expect(
      (tester.widget<CustomPaint>(painter()).painter! as RainbowPainter).track,
      PiggybowPalette.dark.rainbowTrack,
    );
  });

  testWidgets('read out only with a label', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, 32, label: 'Rainbow 32% filled');
    expect(find.bySemanticsLabel('Rainbow 32% filled'), findsOneWidget);
    await show(tester, 32);
    expect(find.bySemanticsLabel(RegExp('Rainbow')), findsNothing);
    semantics.dispose();
  });
}
