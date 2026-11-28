import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';

/// A store whose "what do you own?" waits until [answer] is called.
class _SlowStore extends FakePlusStore {
  final _gate = Completer<void>();

  void answer() => _gate.complete();

  @override
  Future<List<PlusProof>?> owned() async {
    await _gate.future;
    return super.owned();
  }
}

/// A store that answers each "what do you own?" with what it held when
/// asked, only once the test lets that answer through.
class _HeldStore extends FakePlusStore {
  final held = <Completer<void>>[];

  @override
  Future<List<PlusProof>?> owned() async {
    final gate = Completer<void>();
    held.add(gate);
    final answer = available ? owns : null;
    await gate.future;
    return answer;
  }
}

/// Plus on the phone (decision 79): the store's answer is the truth at
/// launch and on resume; the launch hint only bridges until it comes,
/// bounded and never extended without the store; every purchase is
/// finished at once.
void main() {
  final now = DateTime.utc(2026, 11, 28, 5);
  const owned = PlusProof(token: 't1', productId: plusPlayProductId);
  const yearly = PlusPlan(period: PlusPeriod.year, price: '£19.99', trialOffered: true, handle: 'year');

  PlusEntitlement make(FakePlusStore store, MemoryPlusHint hint) =>
      PlusEntitlement(store: store, hint: hint, clock: Clock(fixed: now));

  /// Lets the store's reports run their course.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the hint grants Plus before its end, and never more than 3 days ahead', () {
    expect(plusHintMaxAge, const Duration(days: 3));
    expect(plusHintGrants(null, now), isFalse);
    expect(plusHintGrants(now.add(const Duration(seconds: 1)), now), isTrue);
    expect(plusHintGrants(now, now), isFalse, reason: 'its end excluded');
    expect(plusHintGrants(now.subtract(const Duration(seconds: 1)), now), isFalse);
    expect(plusHintGrants(now.add(plusHintMaxAge), now), isTrue);
    expect(
      plusHintGrants(now.add(plusHintMaxAge + const Duration(seconds: 1)), now),
      isFalse,
      reason: 'further out than the app ever writes',
    );
  });

  test("launch: the hint shows Plus until the store answers; the store's 'none' "
      'ends it and erases the hint', () async {
    final store = _SlowStore();
    final hint = MemoryPlusHint(now.add(const Duration(days: 2)));
    final plus = make(store, hint);
    final started = plus.start();
    await settle();
    expect(plus.active, isTrue, reason: 'the hint, before the store answers');
    store.answer();
    await started;
    expect(plus.active, isFalse);
    expect(hint.until, isNull);
  });

  test("the store's 'owned': Plus on, the hint written for 3 days, and a purchase "
      'that still waits finished', () async {
    final store = FakePlusStore()
      ..owns = const [PlusProof(token: 't1', productId: plusPlayProductId, needsFinish: true)];
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    await plus.start();
    expect(plus.active, isTrue);
    expect(hint.until, now.add(plusHintMaxAge));
    expect(store.finished, ['t1']);
  });

  test("the store can't say: the hint stands until its end and is never extended",
      () async {
    final store = FakePlusStore()..available = false;
    final until = now.add(const Duration(days: 1));
    final hint = MemoryPlusHint(until);
    final plus = make(store, hint);
    await plus.start();
    expect(plus.active, isTrue);
    await plus.refresh();
    expect(hint.until, until, reason: 'never extended without the store');

    for (final stale in [
      now.subtract(const Duration(minutes: 1)),
      now.add(const Duration(days: 30)),
    ]) {
      final other = make(FakePlusStore()..available = false, MemoryPlusHint(stale));
      await other.start();
      expect(other.active, isFalse, reason: '$stale');
    }
    final none = make(FakePlusStore()..available = false, MemoryPlusHint());
    await none.start();
    expect(none.active, isFalse);
  });

  test("a later 'can't say' keeps the store's latest answer", () async {
    final store = FakePlusStore()..owns = const [owned];
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    await plus.start();
    expect(plus.active, isTrue);
    store.available = false;
    await plus.refresh();
    expect(plus.active, isTrue);
    expect(hint.until, now.add(plusHintMaxAge));
  });

  test('buy: bought → finished at once, Plus on, the hint written', () async {
    final store = FakePlusStore();
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    await plus.start();
    expect(plus.active, isFalse);
    await plus.buy(yearly);
    expect(store.bought, [PlusPeriod.year]);
    expect(store.finished, ['fake-token-1']);
    expect(plus.active, isTrue);
    expect(plus.note, PlusNote.none);
    expect(plus.busy, isFalse);
    expect(hint.until, now.add(plusHintMaxAge));
  });

  test('an answer asked before a purchase that lands after it is dropped: '
      'Plus stays on, and a later question is the newest word', () async {
    final store = _HeldStore();
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    final started = plus.start();
    await settle();
    store.held.single.complete();
    await started;
    expect(plus.active, isFalse);

    // A resume asks before the purchase is recorded…
    final resumed = plus.refresh();
    await settle();
    await plus.buy(yearly);
    expect(plus.active, isTrue);
    // …and its "none" lands after it.
    store.owns = const [owned];
    store.held.last.complete();
    await resumed;
    expect(plus.active, isTrue);
    expect(hint.until, now.add(plusHintMaxAge));

    final later = plus.refresh();
    await settle();
    store.held.last.complete();
    await later;
    expect(plus.active, isTrue);
  });

  test('an older "owned" that lands after a newer "none" is dropped too', () async {
    final store = _HeldStore()..owns = const [owned];
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    final started = plus.start();
    await settle();
    store.held.single.complete();
    await started;
    expect(plus.active, isTrue);

    final older = plus.refresh();
    await settle();
    store.owns = const [];
    final newer = plus.refresh();
    await settle();
    store.held.last.complete();
    await newer;
    expect(plus.active, isFalse);
    store.held[1].complete();
    await older;
    expect(plus.active, isFalse);
    expect(hint.until, isNull);
  });

  test('buy: pending → its note and no Plus yet; the approval, reported later, '
      'is finished and turns Plus on', () async {
    final store = FakePlusStore()..nextOutcome = const PlusPending();
    final plus = make(store, MemoryPlusHint());
    await plus.start();
    await plus.buy(yearly);
    expect(plus.note, PlusNote.pending);
    expect(plus.active, isFalse);

    store.owns = const [owned];
    store.report(const PlusProof(token: 't1', productId: plusPlayProductId, needsFinish: true));
    await settle();
    expect(store.finished, ['t1']);
    expect(plus.active, isTrue);
    expect(plus.note, PlusNote.none);
  });

  test('buy: a closed sheet says nothing; a store that said no, its note', () async {
    final store = FakePlusStore()..nextOutcome = const PlusCancelled();
    final plus = make(store, MemoryPlusHint());
    await plus.start();
    await plus.buy(yearly);
    expect([plus.note, plus.active], [PlusNote.none, false]);
    store.nextOutcome = const PlusBuyFailed();
    await plus.buy(yearly);
    expect([plus.note, plus.active], [PlusNote.notThrough, false]);
    expect(store.finished, isEmpty);
  });

  test("restore: found, none, or the store can't say: each its own note", () async {
    final store = FakePlusStore();
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    await plus.start();

    store.owns = const [owned];
    await plus.restore();
    expect([plus.note, plus.active], [PlusNote.restored, true]);

    store.available = false;
    await plus.restore();
    expect([plus.note, plus.active], [PlusNote.unavailable, true]);

    store
      ..available = true
      ..owns = const [];
    await plus.restore();
    expect([plus.note, plus.active], [PlusNote.nothingToRestore, false]);
    expect(hint.until, isNull);
  });

  test("forget (Delete everything): the hint goes; the store's own record stays", () async {
    final store = FakePlusStore()..owns = const [owned];
    final hint = MemoryPlusHint();
    final plus = make(store, hint);
    await plus.start();
    await plus.forget();
    expect(hint.until, isNull);
    await plus.refresh();
    expect(plus.active, isTrue, reason: 'erasing the app never cancels a subscription');
  });

  test("the plans are the store's; the store's own page", () async {
    final store = FakePlusStore(yearly: r'US$59.99');
    final plus = make(store, MemoryPlusHint());
    expect(plus.plans, isNull);
    await plus.loadPlans();
    expect(plus.plans!.map((p) => p.price), [r'US$59.99']);
    store.available = false;
    await plus.loadPlans();
    expect(plus.plans, isEmpty);
    await plus.manage();
    expect(store.manageCalls, 1);
  });

  group('the file hint', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pb_plus_hint'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('written, read back, cleared; unreadable is none', () async {
      final hint = FilePlusHint(folder: () async => dir);
      expect(await hint.read(), isNull);
      final until = now.add(plusHintMaxAge);
      await hint.write(until);
      expect(await hint.read(), until);
      // Only the date: nothing about the purchase or the person.
      final file = File('${dir.path}/${FilePlusHint.fileName}');
      expect(file.readAsStringSync(), '{"until":"2026-12-01T05:00:00.000Z"}');
      await hint.clear();
      expect(file.existsSync(), isFalse);
      expect(await hint.read(), isNull);
      file.writeAsStringSync('not json');
      expect(await hint.read(), isNull);
    });

    test("it lives in the app's cache, which no backup carries", () {
      expect(FilePlusHint().folder, getTemporaryDirectory);
      // Android's backup rules include only the journal and the settings;
      // anything else in the app's folders stays on the phone.
      for (final path in [
        'android/app/src/main/res/xml/data_extraction_rules.xml',
        'android/app/src/main/res/xml-v28/backup_rules.xml',
      ]) {
        final included = RegExp(r'<include [^>]*path="([^"]+)"')
            .allMatches(File(path).readAsStringSync())
            .map((m) => m.group(1))
            .toSet();
        expect(included, {'journal.db', 'FlutterSharedPreferences.xml'}, reason: path);
      }
    });
  });
}
