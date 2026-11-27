// Device locale strings, as the money code needs them.
//
// Devices report locales in several shapes ("en_US", "en-US", "zh_Hant_TW", Android's
// "th_TH_#u-nu-thai", POSIX "de_DE.UTF-8" or "de_DE@euro"); this turns them into language,
// script and region, and picks the locale intl will actually format with.

import 'package:intl/intl.dart' show Intl, NumberFormat;

typedef LocaleParts = ({String language, String? script, String? region});

final _language = RegExp(r'^[A-Za-z]{2,3}$');
final _script = RegExp(r'^[A-Za-z]{4}$');
final _region = RegExp(r'^(?:[A-Za-z]{2}|[0-9]{3})$');

/// Splits a device locale string; null when there's no usable language ("C", "", null).
LocaleParts? parseLocale(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  for (final cut in const ['#', '.', '@']) {
    final i = s.indexOf(cut);
    if (i >= 0) s = s.substring(0, i);
  }
  final parts = s.split(RegExp('[-_]')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || !_language.hasMatch(parts.first)) return null;
  String? script;
  String? region;
  for (final p in parts.skip(1)) {
    if (script == null && region == null && _script.hasMatch(p)) {
      script = p[0].toUpperCase() + p.substring(1).toLowerCase();
    } else if (region == null && _region.hasMatch(p)) {
      region = p.toUpperCase();
    } else {
      break;
    }
  }
  return (language: parts.first.toLowerCase(), script: script, region: region);
}

/// The locale intl formats numbers with for [raw]: the full locale if intl has it, else its
/// language ("de_DE" → "de", "es_AR" → "es"), else "en". Never throws.
String intlNumberLocale(String? raw) {
  final p = parseLocale(raw);
  if (p == null) return 'en';
  final candidate = p.region == null ? p.language : '${p.language}_${p.region}';
  return Intl.verifiedLocale(candidate, NumberFormat.localeExists, onFailure: (_) => 'en')!;
}
