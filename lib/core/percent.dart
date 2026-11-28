import 'package:intl/intl.dart' show NumberFormat;

import '../money/locale.dart';

/// A whole percent (0 to 100) as the phone's region writes it: "37%" in
/// English, "37 %" in French and German. A goal's progress is a ratio, not
/// an amount, so it lives outside the money paths: intl's percent format
/// takes a fraction, and no amount of money is ever one (decision 52).
String formatPercent(int percent, String locale) =>
    NumberFormat.percentPattern(intlNumberLocale(locale)).format(percent / 100);
