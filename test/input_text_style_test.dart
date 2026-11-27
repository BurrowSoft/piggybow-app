import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What people type is ink, never the hint grey (decision 206). Material 3
/// draws a field's text in textTheme.bodyLarge, which is our muted body text,
/// so every TextField and TextFormField sets `style: context.inputText`
/// (theme.dart's PiggybowThemeX). 1.4.0 shipped 11 fields without it (letters,
/// the safety plan, tags, routine, toolbox, appointment, trusted share), and
/// their typing looked like a placeholder (1.4.1, UX 20 Nov).
///
/// Every TextField( or TextFormField( constructed in [root] whose arguments
/// don't include `style: context.inputText`, as "path:line". Wrappers named
/// …TextField (IdTextField) aren't constructions of the field itself.
({int fields, List<String> bare}) bareTextFields(String root) {
  final call = RegExp(r'(?<![A-Za-z0-9_])(TextField|TextFormField)\(');
  final bare = <String>[];
  var fields = 0;
  final files = Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final src = file.readAsStringSync();
    for (final m in call.allMatches(src)) {
      // The constructor's arguments, up to its matching parenthesis.
      var depth = 0;
      var i = m.end - 1;
      for (; i < src.length; i++) {
        if (src[i] == '(') depth++;
        if (src[i] == ')' && --depth == 0) break;
      }
      fields++;
      if (!src.substring(m.end, i).contains('style: context.inputText')) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        bare.add('${file.path.replaceAll('\\', '/')}:$line');
      }
    }
  }
  return (fields: fields, bare: bare);
}

void main() {
  test('every TextField and TextFormField in lib/ types in ink', () {
    final scan = bareTextFields('lib');
    expect(scan.fields, greaterThan(15), reason: 'the scan finds the fields');
    expect(scan.bare, isEmpty, reason: 'fields without style: context.inputText');
  });

  test('the scan catches a bare field and passes a styled one', () {
    final dir = Directory.systemTemp.createTempSync('input_text_style');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/sample.dart').writeAsStringSync('''
Widget a() => TextField(controller: c);
Widget b() => TextField(
      controller: c,
      decoration: InputDecoration(label: Text('x', style: s)),
    );
Widget ok1() => TextField(controller: c, style: context.inputText);
Widget ok2() => TextFormField(
      controller: c,
      style: context.inputText,
      decoration: InputDecoration(hintText: f(g(1))),
    );
Widget ok3() => IdTextField(id: 'x', controller: c);
''');
    final scan = bareTextFields(dir.path);
    expect(scan.fields, 4);
    expect(scan.bare.map((s) => s.split(':').last), ['1', '2']);
  });
}
