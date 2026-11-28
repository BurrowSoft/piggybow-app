import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/add/entry_sheet.dart';

import 'helpers.dart';

/// Keyboard learning off (Android): every text field asks the keyboard not
/// to learn from what is typed in it (enableIMEPersonalizedLearning: false).
/// The scan holds all of lib/ to it, a field added later included; the
/// screens show it on the fields they build.
void main() {
  group('the lib/ scan', () {
    // A text field's constructor, named ones (CupertinoTextField.borderless)
    // and type arguments (Autocomplete<String>) included. The search and
    // autocomplete widgets build their own fields: used here, they need
    // one the flag reaches.
    final call = RegExp(
      r'\b(TextField|TextFormField|CupertinoTextField|CupertinoSearchTextField'
      r'|EditableText|SearchBar|SearchAnchor|Autocomplete|RawAutocomplete)'
      r'(<[^<>()]*>)?(\.\w+)?\(',
    );
    const flag = 'enableIMEPersonalizedLearning: false';

    /// The argument list that opens at [open]: "(" to its ")".
    String argsOf(String src, int open) {
      var depth = 0;
      for (var i = open; i < src.length; i++) {
        if (src[i] == '(') depth++;
        if (src[i] == ')' && --depth == 0) return src.substring(open, i + 1);
      }
      return src.substring(open);
    }

    /// Each text field in [src] without the flag, as "line: kind".
    List<String> missingIn(String src) => [
      for (final m in call.allMatches(src))
        if (!argsOf(src, m.end - 1).contains(flag))
          '${'\n'.allMatches(src.substring(0, m.start)).length + 1}: ${m[1]}',
    ];

    test('it sees a field without the flag, and one with it', () {
      expect(missingIn('child: TextField(\n  controller: c,\n),'), [
        '1: TextField',
      ]);
      expect(
        missingIn(
          'TextFormField(\n  decoration: InputDecoration(labelText: x),\n'
          '  enableIMEPersonalizedLearning: false,\n)',
        ),
        isEmpty,
      );
      // A named constructor, and a search field.
      expect(missingIn('CupertinoTextField.borderless(controller: c)'), [
        '1: CupertinoTextField',
      ]);
      expect(missingIn('SearchAnchor.bar(suggestionsBuilder: s)'), [
        '1: SearchAnchor',
      ]);
      // Autocomplete with type arguments, its own field flagged inside.
      expect(
        missingIn(
          'Autocomplete<String>(\n  fieldViewBuilder: (c, t, f, s) => '
          'TextField(enableIMEPersonalizedLearning: false, controller: t),\n)',
        ),
        isEmpty,
      );
    });

    test('every text field in lib/ turns keyboard learning off', () {
      final missing = <String>[];
      var fields = 0;
      for (final file
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = file.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart') || path.contains('/l10n/gen/')) continue;
        // Comment lines don't count.
        final src = [
          for (final line in file.readAsLinesSync())
            line.trimLeft().startsWith('//') ? '' : line,
        ].join('\n');
        fields += call.allMatches(src).length;
        missing.addAll([for (final m in missingIn(src)) '$path:$m']);
      }
      expect(fields, greaterThanOrEqualTo(7), reason: 'the scan finds them');
      expect(missing, isEmpty, reason: 'add $flag to each');
    });
  });

  group('on screen', () {
    /// The field inside [id], as the app built it.
    void expectOff(WidgetTester tester, String id) {
      final field = tester.widget<EditableText>(
        find.descendant(of: byId(id), matching: find.byType(EditableText)),
      );
      expect(field.enableIMEPersonalizedLearning, isFalse, reason: id);
    }

    testWidgets('the Add sheet: the amount and the note', (tester) async {
      await TestApp().pump(tester);
      await tester.tapId('home-add');
      expectOff(tester, 'add-amount');
      await tester.scrollUntilVisible(
        byId('add-note'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(EntrySheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expectOff(tester, 'add-note');
    });

    testWidgets('a new goal: its name, its amount and what is saved already', (
      tester,
    ) async {
      await TestApp().pump(tester);
      await tester.tapId('goal-create');
      for (final id in ['goal-name', 'goal-amount', 'goal-start']) {
        await tester.revealId(id);
        expectOff(tester, id);
      }
    });

    /// Frames until [f] shows: Me and its pages read the journal first.
    Future<void> settle(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    /// Me on a phone-sized screen, as me_test opens it.
    Future<void> openMe(WidgetTester tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final app = TestApp();
      await tester.runAsync(app.openJournal);
      await app.pump(tester, location: '/me');
      await settle(tester, byId('me-happy'));
    }

    testWidgets("Me: the weekly plan's amount", (tester) async {
      await openMe(tester);
      await tester.tapId('me-plan');
      expectOff(tester, 'me-plan-amount');
    });

    testWidgets("Me → What makes your pig happy: the plan pick's amount", (
      tester,
    ) async {
      await openMe(tester);
      await tester.tapId('me-happy');
      await settle(tester, byId('onb-pick-plan'));
      await tester.tapId('onb-pick-plan');
      await tester.revealId('onb-plan');
      expectOff(tester, 'onb-plan');
    });
  });
}
