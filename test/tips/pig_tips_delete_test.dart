import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/me/me_actions.dart' show deleteEverything;
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/tips/pig_tips.dart';

import '../helpers.dart';

/// Delete everything's two pig tips steps, and what the journal held at each.
class _Recording extends FakePigTips {
  _Recording() : super(on: true);

  late TestApp app;
  final steps = <String>[];

  @override
  Future<String?> eraseBegin() async {
    steps.add('begin: ${(await app.journal.entries()).length} entries');
    return 'the delete still to send';
  }

  @override
  Future<void> eraseEnd(String? pending) async {
    steps.add('end: ${(await app.journal.entries()).length} entries, $pending');
  }
}

/// Delete everything and pig tips: off, and the anonymous id's delete tried
/// before anything is erased; what couldn't be sent is handed back after the
/// erase, so the promise to delete the id outlives it.
void main() {
  testWidgets("Delete everything: pig tips' id goes first, and its pending delete comes back after", (tester) async {
    final tips = _Recording();
    final app = TestApp(pigTips: tips);
    tips.app = app;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(
      () => app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 100000,
        currency: 'THB',
        localDate: '2026-10-01',
      ),
    );
    await app.pump(tester);
    final temp = (await tester.runAsync(() => Directory.systemTemp.createTemp('pig-tips-delete')))!;
    addTearDown(() => temp.deleteSync(recursive: true));
    await tester.runAsync(() => deleteEverything(app.services, app.session, cache: () async => temp));
    await tester.pumpAndSettle();
    expect(tips.steps, [
      'begin: 1 entries',
      'end: 0 entries, the delete still to send',
    ]);
  });
}
