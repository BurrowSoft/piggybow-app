// Flutter re-exports the characters package's String.characters (grapheme
// clusters), so no extra dependency.
import 'package:flutter/widgets.dart' show StringCharacters;

/// Feature 1, the pig's name: optional, at most this many characters (as a
/// person counts them: an emoji or an accented letter is one).
const pigNameMaxLength = 20;

/// The name as it's kept: line breaks and tabs become spaces, the ends are
/// trimmed, and it's cut to [pigNameMaxLength] characters. Nothing left (or
/// null) is no name.
String? normalizePigName(String? typed) {
  if (typed == null) return null;
  final flat = typed.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  if (flat.isEmpty) return null;
  final cut = flat.characters.take(pigNameMaxLength).toString().trimRight();
  return cut.isEmpty ? null : cut;
}
