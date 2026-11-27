import 'package:flutter/material.dart';

/// Long words at large text (French row, 320 dp / 200 %): Flutter breaks a word
/// that doesn't fit its line in the middle ("Statist/iques"), and an [AppBar]
/// cuts its title with an "…". These keep the system's text size whenever the
/// text fits, and scale down only as far as it needs.

/// The system's [scaler], or a smaller one so each of [texts] fits [available]
/// on one line. Measured at each size: letter spacing doesn't scale with the
/// text, so width isn't a straight line.
TextScaler _fitting(
  BuildContext context,
  TextScaler scaler,
  Iterable<String> texts,
  TextStyle? style,
  double available, {
  double floor = 0,
}) {
  // No room to measure against (mid-layout): nothing to fit to.
  if (available <= 1) return scaler;
  // As Text reads it: over the inherited style.
  final merged = DefaultTextStyle.of(context).style.merge(style);
  final direction = Directionality.of(context);
  double widthAt(String text, TextScaler at) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: merged),
      textDirection: direction,
      textScaler: at,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  var result = scaler;
  for (final text in texts) {
    // A hair under: exactly the width can still round over and break the word.
    for (var i = 0; i < 4; i++) {
      final width = widthAt(text, result);
      if (width <= available - 0.5) break;
      result = TextScaler.linear(result.scale(1) * (available - 1) / width);
    }
  }
  // Never above the system's size, never under the floor unless the system's
  // own size already is.
  final limit = floor < scaler.scale(1) ? floor : scaler.scale(1);
  return result.scale(1) < limit ? TextScaler.linear(limit) : result;
}

/// Plain spaces only: a no-break space holds its words together, so French's
/// "aujourd'hui ?" must fit as one.
final _spaces = RegExp('[ \t\r\n]+');

/// Thai has no spaces between words and line-breaks by dictionary: the whole
/// text isn't one word, so it isn't fitted as one.
bool _hasThai(String text) =>
    text.codeUnits.any((u) => u >= 0x0E00 && u <= 0x0E7F);

/// The size at which [number] stays on one line in [text], with what's attached
/// to it ("(0800 111 0 111)"): the system's, or as much smaller as it needs.
/// The other words ("TelefonSeelsorge") stay whole too, down to normal size:
/// past that a name may break, as a line too small to read is worse (UX).
TextScaler wholeNumberScaler(
  BuildContext context, {
  required String text,
  required String number,
  required TextStyle? style,
  required double available,
}) {
  final words = text.split(_spaces);
  final forNumber = _fitting(
    context,
    MediaQuery.textScalerOf(context),
    [words.firstWhere((w) => w.contains(number), orElse: () => number)],
    style,
    available,
  );
  if (_hasThai(text)) return forNumber;
  return _fitting(context, forNumber, words, style, available, floor: 1);
}

/// One size for [texts] set side by side in cells [available] wide (a grid
/// of labels): the system's, or as much smaller as the longest word needs to
/// stay whole, never below normal size. Thai texts don't count: they break
/// by dictionary.
TextScaler wholeWordsScaler(
  BuildContext context, {
  required Iterable<String> texts,
  required TextStyle? style,
  required double available,
}) => _fitting(
  context,
  MediaQuery.textScalerOf(context),
  [
    for (final t in texts)
      if (!_hasThai(t)) ...t.split(_spaces),
  ],
  style,
  available,
  floor: 1,
);

/// Text whose words are never broken inside: an amount like
/// "$9,999,999,999.99" stays whole, wrapping only between words. The
/// system's size, or as much smaller as the longest word needs (never below
/// normal size).
class WholeWordsText extends StatelessWidget {
  const WholeWordsText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Text(
      text,
      style: style,
      textAlign: textAlign,
      textScaler: wholeWordsScaler(
        context,
        texts: [text],
        style: style,
        available: box.maxWidth,
      ),
    ),
  );
}

/// A screen's big title, or a label next to one: wraps between words, never
/// inside one. Stops at normal size (Reviewer E4): a title stays a title.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Text(
      text,
      style: style,
      textScaler: _fitting(
        context,
        MediaQuery.textScalerOf(context),
        _hasThai(text) ? const [] : text.split(_spaces),
        style,
        box.maxWidth,
        floor: 1,
      ),
    ),
  );
}

/// An [AppBar]'s title: one line in the bar's fixed height, all of it.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false),
  );
}
