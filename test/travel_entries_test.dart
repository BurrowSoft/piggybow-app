import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/money/rate.dart';
import 'package:sembast/sembast_memory.dart';

import 'helpers.dart';

/// Money in another currency (feature 19), in the store: a spend or a save
/// abroad keeps its amount as spent, the rate typed and its home amount,
/// converted once; an edit converts that entry again; back in the home
/// currency it keeps no rate; goals count the home amount; the last rate per
/// currency is kept; a home-currency record is as before; and a journal from
/// a newer Piggybow is refused.
void main() {
  late MovableClock clock;
  late JournalStore store;
  var ids = 0;
  final eur = parseRate('39.12', RateDirection.toHome).rate!;

  setUp(() async {
    ids = 0;
    clock = MovableClock(DateTime.utc(2026, 11, 28, 2, 0));
    store = await JournalStore.inMemory(clock: clock, newId: () => 'e${++ids}');
    await store.setCurrency('THB');
  });
  tearDown(() => store.close());

  Future<Entry> spend(int minor, String currency, {Rate? rate}) => store.addEntry(
    type: EntryType.spent,
    amountMinor: minor,
    currency: currency,
    localDate: '2026-11-28',
    category: SpendCategory.food,
    rate: rate,
  );

  test('a spend in euros: as spent, its rate, and ฿482.74 at home', () async {
    final e = await spend(1234, 'EUR', rate: eur);
    expect((e.amountMinor, e.currency, e.rate, e.convertedMinor, e.homeMinor), (1234, 'EUR', eur, 48274, 48274));
    expect(await store.entry(e.id), e);
    expect(e.toMap()['home_minor'], 48274);
    expect(e.toMap()['rate'], {'units': 3912, 'scale': 2, 'dir': 'to_home'});
  });

  test('a home-currency entry is stored as before: no rate, no home amount', () async {
    final e = await spend(12050, 'THB');
    expect((e.rate, e.convertedMinor, e.homeMinor), (null, null, 12050));
    expect(e.toMap().containsKey('rate'), isFalse);
    expect(e.toMap().containsKey('home_minor'), isFalse);
  });

  test('a rate in the home currency, another currency without one, or a '
      'conversion out of range: refused', () async {
    await expectLater(spend(100, 'THB', rate: eur), throwsArgumentError);
    await expectLater(spend(100, 'EUR'), throwsArgumentError);
    // €0.01 at "1 EUR = 0.4 THB" is 0.4 of a satang.
    await expectLater(spend(1, 'EUR', rate: parseRate('0.4', RateDirection.toHome).rate), throwsArgumentError);
    expect(await store.entries(), isEmpty);
  });

  test('an edit converts that entry again; back in the home currency it keeps no rate', () async {
    final e = await spend(1234, 'EUR', rate: eur);
    final more = await store.updateEntry(e.copyWith(amountMinor: 2000));
    expect(more.homeMinor, 78240);
    final other = parseRate('40', RateDirection.toHome).rate!;
    final rated = await store.updateEntry(more.copyWith(rate: other));
    expect(rated.homeMinor, 80000);
    final home = await store.updateEntry(rated.copyWith(currency: 'THB', amountMinor: 80000, clearRate: true));
    expect((home.currency, home.rate, home.convertedMinor, home.homeMinor), ('THB', null, null, 80000));
  });

  test('the last rate typed for each currency is kept, to fill in the next one', () async {
    expect(await store.lastRate('EUR'), isNull);
    await spend(1234, 'EUR', rate: eur);
    expect(await store.lastRate('EUR'), eur);
    final yen = parseRate('0.2301', RateDirection.toHome).rate!;
    await spend(1000, 'JPY', rate: yen);
    expect((await store.lastRate('EUR'), await store.lastRate('JPY')), (eur, yen));
  });

  test("a save abroad counts toward its goal at its home amount", () async {
    await store.putGoal(
      Goal(
        id: 'g1',
        name: 'Bike',
        targetMinor: 100000,
        createdAt: clock.nowUtc(),
        updatedAt: clock.nowUtc(),
      ),
    );
    await store.addEntry(
      type: EntryType.saved,
      amountMinor: 1234,
      currency: 'EUR',
      localDate: '2026-11-28',
      rate: eur,
    );
    expect(await store.goalProgress((await store.goal('g1'))!), 48274);
  });

  test('a record with a rate but no home amount, or the reverse, is not read', () {
    final m = {
      'type': 'spent',
      'amount_minor': 1234,
      'currency': 'EUR',
      'category': 'food',
      'note': '',
      'local_date': '2026-11-28',
      'created_at': '2026-11-28T02:00:00.000Z',
      'updated_at': '2026-11-28T02:00:00.000Z',
    };
    expect(Entry.fromMap('x', {...m, 'rate': eur.toMap()}), isNull);
    expect(Entry.fromMap('x', {...m, 'home_minor': 48274}), isNull);
    expect(Entry.fromMap('x', {...m, 'rate': {'units': 0}, 'home_minor': 48274}), isNull);
    expect(Entry.fromMap('x', {...m, 'rate': eur.toMap(), 'home_minor': 48274})!.homeMinor, 48274);
    expect(Entry.fromMap('x', m)!.homeMinor, 1234);
  });

  group('the journal format', () {
    test('a new journal, or one from before, is marked with this format', () async {
      final factory = newDatabaseFactoryMemory();
      final older = await factory.openDatabase('journal.db');
      await StoreRef<String, Object?>('settings').record('currency').put(older, 'THB');
      await older.close();
      final reopened = await JournalStore.inMemory(clock: clock, factory: factory);
      await reopened.close();
      final db = await factory.openDatabase('journal.db');
      expect(await StoreRef<String, Object?>('settings').record('format').get(db), JournalStore.format);
      await db.close();
    });

    test('a journal from a newer Piggybow is refused, never half-read', () async {
      final factory = newDatabaseFactoryMemory();
      final newer = await factory.openDatabase('journal.db');
      await StoreRef<String, Object?>('settings').record('format').put(newer, JournalStore.format + 1);
      await newer.close();
      await expectLater(
        JournalStore.inMemory(clock: clock, factory: factory),
        throwsA(isA<JournalTooNew>().having((e) => e.format, 'format', JournalStore.format + 1)),
      );
    });

    test('Delete everything keeps it this format', () async {
      final factory = newDatabaseFactoryMemory();
      final journal = await JournalStore.inMemory(clock: clock, factory: factory);
      await journal.wipe();
      await journal.close();
      final db = await factory.openDatabase('journal.db');
      expect(await StoreRef<String, Object?>('settings').record('format').get(db), JournalStore.format);
      await db.close();
    });
  });
}
