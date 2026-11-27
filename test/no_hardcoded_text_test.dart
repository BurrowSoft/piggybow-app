import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_hardcoded_text.dart';

void main() {
  test('lib/ has no hard-coded user-facing text', () {
    expect(hardcodedText(), isEmpty);
  });

  test('the check catches the usual forms and honours l10n-ignore', () {
    final dir = Directory.systemTemp.createTempSync('l10n_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/sample.dart').writeAsStringSync('''
Widget a() => Text('Save');
Widget b() => Text(
      "Delete this entry?",
    );
Widget c() => InputDecoration(labelText: 'Email');
Widget d() => IconButton(tooltip: 'Back', onPressed: null, icon: x);
Widget e() => TextSpan(style: s, text: 'Read the Terms');
Widget ok1() => Text(l10n.save);
Widget ok2() => TestId('entry-save', child: x);
Widget ok3() => Text('\$hours');
Widget f() => Text('วันนี้');
String g(d) => DateFormat('EEEE, d MMMM y', l).format(d);
String ok5(d) => DateFormat.yMMMMEEEEd(l).format(d);
Widget ok4() => Text('English'); // l10n-ignore
Widget h() => FilledButton(onPressed: null, child: ButtonLabel('Add'));
Widget ok6() => ButtonLabel(l10n.addSubmit);
// Text('a comment');
''');
    final problems = hardcodedText(root: dir.path);
    expect(problems, hasLength(8), reason: problems.join('\n'));
    expect(problems.join('\n'), isNot(contains('English')));
  });
}
