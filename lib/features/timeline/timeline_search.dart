// What Timeline's search matches (feature 15), on the phone only: nothing of
// it is ever stored. Every word typed must be in the entry's note or in the
// name its row shows (a spend's category, a save's goal). Case doesn't
// count, and neither do the accents of Latin letters (é, ñ, ß…). Thai is
// matched as typed: its tone marks and vowels change the word.

/// [text] lower-cased, with the accents taken off its Latin letters: what a
/// search compares.
String foldForSearch(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    // An accent typed as its own mark after the letter (U+0300 to U+036F).
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final folded = _folds[rune];
    if (folded != null) {
      out.write(folded);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// The words of a typed search, folded; none when it's blank.
List<String> searchWords(String query) => [
  for (final word in foldForSearch(query).split(_spaces))
    if (word.isNotEmpty) word,
];

/// Whether each of [words] is in one of [texts]. With no words, everything
/// matches.
bool matchesSearch(List<String> words, Iterable<String> texts) {
  if (words.isEmpty) return true;
  final folded = [for (final t in texts) foldForSearch(t)];
  return words.every((w) => folded.any((t) => t.contains(w)));
}

final _spaces = RegExp(r'\s+');

/// The Latin letters with an accent (lower case), by the letter they read
/// as.
const _accented = {
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
  'c': 'çćĉċč',
  'd': 'ďđð',
  'e': 'èéêëēĕėęěȅȇȩẹẻẽếềểễệ',
  'g': 'ĝğġģǧ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįıǐȉȋỉị',
  'j': 'ĵ',
  'k': 'ķǩ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉǹ',
  'o': 'òóôõöøōŏőơǒǫȍȏȫȭȯȱọỏốồổỗộớờởỡợ',
  'r': 'ŕŗřȑȓ',
  's': 'śŝşšș',
  't': 'ţťŧț',
  'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗụủứừửữự',
  'w': 'ŵẁẃẅ',
  'y': 'ýÿŷỳỵỷỹ',
  'z': 'źżž',
};

/// The Latin letters that read as two.
const _pairs = {'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'þ': 'th', 'ĳ': 'ij'};

final Map<int, String> _folds = {
  for (final MapEntry(key: plain, value: letters) in _accented.entries)
    for (final rune in letters.runes)
      if (rune < 0x300 || rune > 0x36f) rune: plain,
  for (final MapEntry(key: letter, value: plain) in _pairs.entries)
    for (final rune in letter.runes) rune: plain,
};
