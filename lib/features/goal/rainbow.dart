import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The goal's rainbow (plan §3.5): five arcs, outer to inner, each 20 % of
/// the goal. The outer arc fills first, sweeping from the left foot over the
/// top to the right foot; an arc in progress is partly filled. A change of
/// [percent] animates (~600 ms, ease-out), except under reduce-motion.
///
/// Decorative: the numbers are always in text next to it. Give
/// [semanticLabel] where the rainbow itself is read out (goal detail).
class Rainbow extends StatelessWidget {
  const Rainbow({super.key, required this.percent, this.semanticLabel});

  /// 0–100: how much of the goal is saved.
  final int percent;
  final String? semanticLabel;

  /// Outer to inner: rose, peach, gold, mint, lavender.
  static const arcColours = [
    Color(0xFFE27D9A),
    Color(0xFFF2A07B),
    Color(0xFFF3C24F),
    Color(0xFF8CCFB0),
    Color(0xFF9B84D6),
  ];
  static const trackLight = Color(0xFFECE6F0);
  static const trackDark = Color(0xFF3A3350);

  /// The design's box (design/rainbow-*.svg): 240 × 132.
  static const aspectRatio = 240 / 132;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = MediaQuery.disableAnimationsOf(context);
    final fill = percent.clamp(0, 100) / 100;
    final drawing = AspectRatio(
      aspectRatio: aspectRatio,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fill),
        duration: still ? Duration.zero : const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (context, value, _) => CustomPaint(
          painter: RainbowPainter(
            fill: value,
            track: dark ? trackDark : trackLight,
          ),
        ),
      ),
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: drawing)
        : Semantics(
            label: label,
            image: true,
            child: ExcludeSemantics(child: drawing),
          );
  }
}

/// Paints the rainbow at [fill] (0–1) over its [track].
class RainbowPainter extends CustomPainter {
  const RainbowPainter({required this.fill, required this.track});

  final double fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    // The design's geometry, scaled: centre (120, 122), radii 108 to 52 in
    // steps of 14, strokes 11 wide with round ends.
    final s = size.width / 240;
    final centre = Offset(120 * s, 122 * s);
    for (var i = 0; i < 5; i++) {
      final r = (108 - 14 * i) * s;
      final rect = Rect.fromCircle(center: centre, radius: r);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11 * s
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, math.pi, math.pi, false, paint..color = track);
      // This arc's share of the fill: 0 to 1 (arc 1 covers 0–20 %, …).
      final part = (fill * 5 - i).clamp(0.0, 1.0);
      // A zero-length arc with round ends would still paint a dot.
      if (part > 0) {
        canvas.drawArc(
          rect,
          math.pi,
          math.pi * part,
          false,
          paint..color = Rainbow.arcColours[i],
        );
      }
    }
  }

  @override
  bool shouldRepaint(RainbowPainter old) =>
      old.fill != fill || old.track != track;
}
