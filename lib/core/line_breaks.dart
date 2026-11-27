import 'package:flutter/services.dart';

/// For a field that shows up to a few lines but holds one line of text (a
/// note, a goal's name): every line break typed or pasted becomes a space,
/// one for one, so the cursor stays where it was.
class LineBreaksAsSpaces extends TextInputFormatter {
  const LineBreaksAsSpaces();

  static final _breaks = RegExp(r'[\r\n\u2028\u2029]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!_breaks.hasMatch(newValue.text)) return newValue;
    return newValue.copyWith(text: newValue.text.replaceAll(_breaks, ' '));
  }
}
