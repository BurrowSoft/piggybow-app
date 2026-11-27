import 'package:flutter/material.dart';

/// A text field whose label is never cut off (localization plan, the L rows).
/// [InputDecoration] keeps a label on one line with an "…", and a wrapped one
/// would run over the field. So a label that fits is the usual floating label,
/// and one that doesn't (large text, a long language) sits above the field in
/// full; the field keeps it as its spoken name either way.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.field,
    this.decoration = const InputDecoration(),
    this.width,
  });

  final String label;

  /// Everything but the label.
  final InputDecoration decoration;

  /// Builds the field with the decoration to use.
  final Widget Function(InputDecoration decoration) field;

  /// The field's width, only where it can't be asked for: an [AlertDialog]
  /// sizes itself by intrinsics, which a [LayoutBuilder] doesn't support.
  final double? width;

  /// Material's space for a prefix or suffix icon, and its padding without one.
  static const _iconSpace = 48.0;
  static const _padding = 16.0;

  bool _fits(BuildContext context, double width, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final used = painter.width;
    painter.dispose();
    return used <=
        width -
            (decoration.prefixIcon == null ? _padding : _iconSpace) -
            (decoration.suffixIcon == null ? _padding : _iconSpace);
  }

  Widget _build(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final fits = _fits(context, width, style);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // Spoken with the field, as a floating label is.
            child: ExcludeSemantics(child: Text(label, style: style)),
          ),
        // Keyed: typed text and focus survive a rotation across the two forms.
        KeyedSubtree(
          key: const ValueKey('field'),
          child: field(
            fits
                ? decoration.copyWith(labelText: label)
                : decoration.copyWith(
                    label: Semantics(
                      label: label,
                      child: const SizedBox.shrink(),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = this.width;
    return width != null
        ? _build(context, width)
        : LayoutBuilder(
            builder: (context, box) => _build(context, box.maxWidth),
          );
  }
}
