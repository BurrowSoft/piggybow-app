import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/line_breaks.dart';
import 'package:piggybow/features/add/entry_sheet.dart';

import 'helpers.dart';

/// The note field (decision 55): up to 3 lines, so a long note is seen
/// whole, but still one line of text: Enter is Done, and a line break typed
/// or pasted becomes a space.
void main() {
  TextEditingValue value(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  test('line breaks become spaces, one for one', () {
    const f = LineBreaksAsSpaces();
    String format(String text) =>
        f.formatEditUpdate(TextEditingValue.empty, value(text)).text;
    expect(format('A\nB'), 'A B');
    expect(format('A\r\nB'), 'A  B');
    expect(format('A\u2028B\u2029C'), 'A B C');
    // One for one: the cursor stays where it was.
    expect(
      f.formatEditUpdate(TextEditingValue.empty, value('A\nB')).selection,
      value('A\nB').selection,
    );
    final plain = value('no breaks');
    expect(
      identical(f.formatEditUpdate(TextEditingValue.empty, plain), plain),
      isTrue,
    );
  });

  testWidgets('the note: up to 3 lines, Enter is Done, a break a space', (
    tester,
  ) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.tapId('tl-empty-add');
    // The note is down the sheet, under the amount, its currency and the
    // categories: on screen first.
    await tester.scrollUntilVisible(
      byId('add-note'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(EntrySheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterId('add-note', 'Lunch\nwith the team');
    final field = tester.widget<TextField>(
      find.descendant(of: byId('add-note'), matching: find.byType(TextField)),
    );
    expect(field.minLines, 1);
    expect(field.maxLines, 3);
    expect(field.keyboardType, TextInputType.text);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.controller!.text, 'Lunch with the team');
  });
}
