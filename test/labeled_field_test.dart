import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/labeled_field.dart';
import 'package:piggybow/core/semantics_id.dart';

const _label = 'A label of some length';

void main() {
  /// [scale] text on a screen [width] wide.
  void screen(WidgetTester tester, double width, double scale) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget page(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  Widget labeled({double? width}) => Align(
    alignment: Alignment.topCenter,
    child: LabeledField(
      label: _label,
      width: width,
      decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
      field: (decoration) => TextField(decoration: decoration),
    ),
  );

  InputDecoration decorationOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration!;

  testWidgets('normal text: the same field as a plain floating label', (
    tester,
  ) async {
    screen(tester, 800, 1);
    await tester.pumpWidget(
      page(
        const Align(
          alignment: Alignment.topCenter,
          child: TextField(
            decoration: InputDecoration(
              labelText: _label,
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
      ),
    );
    final plainRect = tester.getRect(find.byType(TextField));
    final plainLabel = tester.getRect(find.text(_label));

    await tester.pumpWidget(page(labeled()));
    await tester.pumpAndSettle();
    expect(decorationOf(tester).labelText, _label);
    expect(find.text(_label), findsOneWidget);
    expect(tester.getRect(find.byType(TextField)), plainRect);
    expect(tester.getRect(find.text(_label)), plainLabel);
  });

  testWidgets('large text on a narrow screen: all of it, above the field', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    screen(tester, 320, 2);
    await tester.pumpWidget(page(labeled()));
    await tester.pumpAndSettle();
    expect(decorationOf(tester).labelText, isNull);
    final text = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(_label), matching: find.byType(RichText)),
    );
    expect(text.didExceedMaxLines, isFalse);
    expect(
      tester.getBottomLeft(find.text(_label)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
    );
    // Read once, as the field's name, not as a stop of its own.
    expect(
      tester.getSemantics(find.byType(EditableText)).getSemanticsData().label,
      _label,
    );
    semantics.dispose();
  });

  // Above the field, the field keeps no empty band where a floating label
  // would be: its text starts where a field with no label's does, but for
  // Material's 4 dp gap at the text size (UX, from #87's goldens).
  testWidgets('large text: no empty band over the field under its label', (
    tester,
  ) async {
    screen(tester, 320, 2);
    double textTop() =>
        tester.getTopLeft(find.byType(EditableText)).dy -
        tester.getTopLeft(find.byType(TextField)).dy;
    await tester.pumpWidget(
      page(
        const Align(
          alignment: Alignment.topCenter,
          child: TextField(decoration: InputDecoration()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final plain = textTop();
    await tester.pumpWidget(page(labeled()));
    await tester.pumpAndSettle();
    expect(decorationOf(tester).labelText, isNull, reason: 'above the field');
    expect(textTop(), lessThanOrEqualTo(plain + 4 * 2 + 0.5));
  });

  testWidgets('typed text survives moving between the two forms', (
    tester,
  ) async {
    screen(tester, 1000, 2);
    await tester.pumpWidget(page(labeled()));
    await tester.enterText(find.byType(TextField), 'kept');
    await tester.pump();
    expect(decorationOf(tester).labelText, _label);

    tester.view.physicalSize = const Size(320, 1200);
    await tester.pumpAndSettle();
    expect(decorationOf(tester).labelText, isNull);
    expect(find.text('kept'), findsOneWidget);
  });

  group(
    'the text field node the platform gets, inside TestId as in the app',
    () {
      /// The one node flagged as a text field: what TalkBack reads.
      SemanticsData fieldNode() {
        final nodes = find.semantics
            .byPredicate(
              (n) =>
                  !n.isMergedIntoParent &&
                  n.getSemanticsData().flagsCollection.isTextField,
            )
            .evaluate()
            .toList();
        expect(nodes, hasLength(1));
        return nodes.single.getSemanticsData();
      }

      /// Nodes that say the label without being the field: extra stops.
      Iterable<SemanticsNode> labelStops() => find.semantics
          .byPredicate(
            (n) =>
                !n.isMergedIntoParent &&
                n.getSemanticsData().label.contains(_label) &&
                !n.getSemanticsData().flagsCollection.isTextField,
          )
          .evaluate();

      Widget inTestId({required bool plain}) => Align(
        alignment: Alignment.topCenter,
        child: plain
            ? const TestId(
                'the-field',
                child: TextField(
                  decoration: InputDecoration(labelText: _label),
                ),
              )
            : LabeledField(
                label: _label,
                field: (decoration) => TestId(
                  'the-field',
                  child: TextField(decoration: decoration),
                ),
              ),
      );

      testWidgets('control: a plain floating label', (tester) async {
        final semantics = tester.ensureSemantics();
        screen(tester, 800, 1);
        await tester.pumpWidget(page(inTestId(plain: true)));
        await tester.pumpAndSettle();
        expect(fieldNode().label, _label);
        expect(fieldNode().identifier, 'the-field');
        semantics.dispose();
      });

      testWidgets('a label that fits', (tester) async {
        final semantics = tester.ensureSemantics();
        screen(tester, 800, 1);
        await tester.pumpWidget(page(inTestId(plain: false)));
        await tester.pumpAndSettle();
        expect(decorationOf(tester).labelText, _label);
        expect(fieldNode().label, _label);
        expect(fieldNode().identifier, 'the-field');
        semantics.dispose();
      });

      for (final typed in const [false, true]) {
        testWidgets('a label moved above the field, typed: $typed', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          screen(tester, 320, 2);
          await tester.pumpWidget(page(inTestId(plain: false)));
          if (typed) await tester.enterText(find.byType(TextField), 'kept');
          await tester.pumpAndSettle();
          expect(decorationOf(tester).labelText, isNull);
          expect(fieldNode().label, _label);
          expect(fieldNode().identifier, 'the-field');
          expect(labelStops(), isEmpty);
          semantics.dispose();
        });
      }
    },
  );

  testWidgets('in a dialog, with its width given', (tester) async {
    screen(tester, 320, 2);
    await tester.pumpWidget(
      page(
        AlertDialog(
          scrollable: true,
          content: LabeledField(
            label: _label,
            width: 320 - 128,
            field: (decoration) => TextField(decoration: decoration),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(decorationOf(tester).labelText, isNull);
    expect(find.text(_label), findsOneWidget);
  });
}
