import 'package:flutter/widgets.dart';

/// A button's label, centred on every line when it wraps (at large text a
/// label like "Add your first entry" takes two lines). Flutter's buttons
/// centre the label's box, but leave a wrapped Text's lines at the start.
class ButtonLabel extends StatelessWidget {
  const ButtonLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, textAlign: TextAlign.center);
}
