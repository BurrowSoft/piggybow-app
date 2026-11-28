import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';
import 'package:piggybow/backup/backup_snapshot.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/core/local_prefs.dart';
import 'package:piggybow/data/models.dart' show ReminderTime;
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/money/money.dart' show maxAmountMinor;
import 'package:piggybow/money/rate.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;
import 'package:piggybow/repeat/repeat.dart' show RepeatSchedule;
import 'package:shared_preferences/shared_preferences.dart';

/// Feature 21, what a backup carries: the whole journal comes back exactly,
/// in one transaction or not at all, checked before anything is touched;
/// the lock, the device account and device-only flags never travel; the
/// reminder comes back off.
void main() {
  final clock = Clock(fixed: DateTime.utc(2026, 11, 28, 2));
  const fast = BackupKdf(memoryKiB: 64, iterations: 1, parallelism: 1);
  const prefs = PrefsSnapshot(
    localeCode: 'th',
    appearance: 'dark',
    palette: null,
    reminderTime: ReminderTime(21, 30),
    reminderWasOn: true,
  );
  final stamp = DateTime.utc(2026, 11, 20, 3);

  late JournalStore store;
  var ids = 0;

  setUp(() async {
    ids = 0;
    store = await JournalStore.inMemory(clock: clock, newId: () => 'e${++ids}');
  });

  tearDown(() => store.close());

  Goal goal(String id, GoalStatus status, {DateTime? reachedAt}) => Goal(
    id: id,
    name: 'Bike $id',
    targetMinor: 100000,
    status: status,
    bandReachedAt: status == GoalStatus.reached
        ? [stamp, stamp, stamp, stamp, stamp]
        : const [null, null, null, null, null],
    reachedAt: reachedAt,
    createdAt: stamp,
    updatedAt: stamp,
  );

  /// A journal with everything a backup carries: spends (Thai, emoji and
  /// longest notes, with and without a feeling, one in your own category,
  /// one in euros), saves to the active goal (a band stamped) and a
  /// take-out, a reached and an ended goal, your own category, a hidden
  /// built-in, a repeat, and every setting.
  Future<void> fill(JournalStore s) async {
    await s.setCurrency('THB');
    await s.setPicks({HappyPick.save, HappyPick.worth});
    await s.setPlanMinor(150000);
    await s.setOnboarded();
    await s.answerReminderOffer();
    await s.setBuiltInHidden(SpendCategory.fun, true);
    // Me → Your pig's switches, and a letter put away (UX, 28 Nov).
    await s.setYesterdayFeelOn(false);
    await s.setLettersOn(false);
    await s.dismissLetter('2026-10');
    await s.putCustomCategory(
      CustomCategory(
        id: 'c:bubble',
        name: 'Bubble tea',
        icon: CategoryIcon.drinks,
        createdAt: stamp,
      ),
    );
    await s.putGoal(goal('g-reached', GoalStatus.reached, reachedAt: stamp));
    await s.markCelebrated('g-reached');
    await s.putGoal(goal('g-ended', GoalStatus.ended));
    await s.putGoal(goal('g-active', GoalStatus.active));
    Future<void> spend(int minor, String note, [Feeling? feeling]) =>
        s.addEntry(
          type: EntryType.spent,
          amountMinor: minor,
          currency: 'THB',
          localDate: '2026-11-27',
          category: SpendCategory.food,
          feeling: feeling,
          note: note,
        );
    await spend(4500, 'ข้าวมันไก่ 🐷', Feeling.worthIt);
    await spend(999999999999, 'x' * maxNoteLength);
    await spend(1, '');
    await s.addEntry(
      type: EntryType.spent,
      amountMinor: 6500,
      currency: 'THB',
      localDate: '2026-11-27',
      customCategory: 'c:bubble',
    );
    await s.addEntry(
      type: EntryType.saved,
      amountMinor: 25000,
      currency: 'THB',
      localDate: '2026-11-28',
    );
    await s.takeOut(
      goalId: 'g-active',
      amountMinor: 5000,
      currency: 'THB',
      localDate: '2026-11-28',
    );
    // Schema 2: a repeat (E) and Home's card for it put away; a spend in
    // euros at its rate (#74), which keeps the last rate.
    await s.addEntry(
      type: EntryType.spent,
      amountMinor: 1200000,
      currency: 'THB',
      localDate: '2026-11-27',
      category: SpendCategory.home,
      note: 'Rent',
      repeat: const RepeatSchedule.monthly(27),
      today: '2026-11-28',
    );
    await s.markRepeatsSeen(const []);
    await s.addEntry(
      type: EntryType.spent,
      amountMinor: 1234,
      currency: 'EUR',
      localDate: '2026-11-27',
      category: SpendCategory.food,
      rate: const Rate(units: 3912, scale: 2, direction: RateDirection.toHome),
    );
  }

  /// Another journal, so a restore has something to replace.
  Future<void> fillOther(JournalStore s) async {
    await s.setCurrency('EUR');
    await s.setPlanMinor(9900);
    await s.putGoal(goal('other', GoalStatus.active));
    await s.addEntry(
      type: EntryType.spent,
      amountMinor: 700,
      currency: 'EUR',
      localDate: '2026-11-01',
      category: SpendCategory.transport,
    );
  }

  Future<JournalStore> other() async {
    final s = await JournalStore.inMemory(clock: clock);
    addTearDown(s.close);
    await fillOther(s);
    return s;
  }

  Map<String, Object?> plain(JournalSnapshot s) => BackupSnapshot(
    journal: s,
    prefs: prefs,
  ).toJson()['journal']! as Map<String, Object?>;

  group('a restore', () {
    test('brings the journal back exactly, through a sealed file', () async {
      await fill(store);
      final before = await store.snapshot();
      expect(before.entries, hasLength(8));
      expect(before.goals, hasLength(3));
      expect(before.categories.keys, ['c:bubble']);
      expect(before.repeats, hasLength(1));
      expect(
        before.entries.values.where((e) => e['home_minor'] == 48274),
        hasLength(1),
        reason: 'EUR 12.34 at 39.12, at home',
      );
      expect(
        before.entries.values.where((e) => e['type'] == 'withdraw'),
        hasLength(1),
      );
      expect(before.settings.keys.toSet(), {
        ...JournalStore.travels,
        'celebrated.g-reached',
      }, reason: 'every setting that travels is in the test journal');
      expect(
        before.goals['g-active']!['band_reached_at'],
        isNot(everyElement(isNull)),
        reason: 'the save stamped a band',
      );

      final file = await sealBackup(
        BackupSnapshot(journal: before, prefs: prefs).toJson(),
        'correct horse',
        kdf: fast,
      );
      final back = BackupSnapshot.fromJson(
        await openBackup(file, 'correct horse'),
      );
      final target = await other();
      await target.replaceWith(back.journal);

      expect(plain(await target.snapshot()), plain(before));
      expect(back.prefs.localeCode, 'th');
      expect(back.prefs.appearance, 'dark');
      expect(back.prefs.palette, isNull);
    });

    test("the pig's name comes back, and none is none", () {
      Map<String, Object?> file(String? name) =>
          jsonDecode(
                jsonEncode(
                  BackupSnapshot(
                    journal: const JournalSnapshot(
                      entries: {},
                      goals: {},
                      settings: {},
                    ),
                    prefs: PrefsSnapshot(
                      localeCode: null,
                      appearance: null,
                      palette: null,
                      reminderTime: const ReminderTime(21, 30),
                      reminderWasOn: false,
                      pigName: name,
                    ),
                  ).toJson(),
                ),
              )
              as Map<String, Object?>;
      expect(BackupSnapshot.fromJson(file('Oink 🐷')).prefs.pigName, 'Oink 🐷');
      expect(BackupSnapshot.fromJson(file(null)).prefs.pigName, isNull);
    });

    // #85 with #47: with Plus, several goals are active at once, and a
    // backup carries them all.
    test('several active goals come back', () async {
      await fill(store);
      await store.putGoal(
        goal('g-second', GoalStatus.active),
        allowAnother: true,
      );
      final backup = await store.snapshot();
      expect(
        backup.goals.values.where((g) => g['status'] == GoalStatus.active.id),
        hasLength(2),
      );
      final target = await other();
      await target.replaceWith(backup);
      expect(plain(await target.snapshot()), plain(backup));
    });

    // A repeat in a category of your own carries it, as its spends do.
    test('a repeat in your own category comes back in it', () async {
      await fill(store);
      await store.addEntry(
        type: EntryType.spent,
        amountMinor: 6500,
        currency: 'THB',
        localDate: '2026-11-27',
        customCategory: 'c:bubble',
        repeat: const RepeatSchedule.weekly(5),
        today: '2026-11-28',
      );
      final backup = await store.snapshot();
      expect(
        backup.repeats.values.where((r) => r['category'] == 'c:bubble'),
        hasLength(1),
      );
      final target = await other();
      await target.replaceWith(backup);
      expect(plain(await target.snapshot()), plain(backup));
      expect(
        (await target.repeats()).where((r) => r.customCategory == 'c:bubble'),
        hasLength(1),
      );
    });

    test('a failure halfway leaves the old journal exactly as it was', () async {
      await fill(store);
      final backup = await store.snapshot();
      final target = await other();
      final before = await target.snapshot();
      await expectLater(
        target.replaceWith(
          backup,
          midway: () async => throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(plain(await target.snapshot()), plain(before));
    });

    test('anything the store never writes is refused before anything is '
        'touched', () async {
      await fill(store);
      final good = await store.snapshot();
      final target = await other();
      final before = await target.snapshot();

      JournalSnapshot withEntry(void Function(Map<String, Object?>) change) {
        final entries = {
          for (final MapEntry(:key, :value) in good.entries.entries)
            key: {...value},
        };
        change(entries.values.first);
        return JournalSnapshot(
          entries: entries,
          goals: good.goals,
          categories: good.categories,
          settings: good.settings,
        );
      }

      JournalSnapshot withGoal(void Function(Map<String, Object?>) change) {
        final goals = {
          for (final MapEntry(:key, :value) in good.goals.entries)
            key: {...value},
        };
        change(goals['g-active']!);
        return JournalSnapshot(
          entries: good.entries,
          goals: goals,
          categories: good.categories,
          settings: good.settings,
        );
      }

      JournalSnapshot withSetting(String key, Object? value) => JournalSnapshot(
        entries: good.entries,
        goals: good.goals,
        categories: good.categories,
        settings: {...good.settings, key: value},
      );

      JournalSnapshot withEuro(void Function(Map<String, Object?>) change) {
        final entries = {
          for (final MapEntry(:key, :value) in good.entries.entries)
            key: {...value},
        };
        change(entries.values.firstWhere((m) => m['currency'] == 'EUR'));
        return JournalSnapshot(
          entries: entries,
          goals: good.goals,
          categories: good.categories,
          repeats: good.repeats,
          settings: good.settings,
        );
      }

      JournalSnapshot withRepeat(void Function(Map<String, Object?>) change) {
        final repeats = {
          for (final MapEntry(:key, :value) in good.repeats.entries)
            key: {...value},
        };
        change(repeats.values.single);
        return JournalSnapshot(
          entries: good.entries,
          goals: good.goals,
          categories: good.categories,
          repeats: repeats,
          settings: good.settings,
        );
      }

      final bubble = good.categories['c:bubble']!;
      JournalSnapshot withCategories(
        Map<String, Map<String, Object?>> categories,
      ) => JournalSnapshot(
        entries: good.entries,
        goals: good.goals,
        categories: categories,
        settings: good.settings,
      );

      final bad = <String, JournalSnapshot>{
        // Your own categories (#49): as the store writes them, and a spend
        // in one of them has it in the backup too.
        'your own category under a built-in\'s id': withCategories({
          ...good.categories,
          'food': bubble,
        }),
        'two of your own with the same name': withCategories({
          ...good.categories,
          'c:twin': {...bubble, 'name': ' bubble TEA '},
        }),
        'your own category\'s name over the limit': withCategories({
          'c:bubble': {...bubble, 'name': 'x' * (categoryNameMax + 1)},
        }),
        'a spend in your own category the backup doesn\'t carry':
            withCategories(const {}),
        'a hidden built-in that isn\'t one': withSetting('hidden_categories', [
          'nope',
        ]),
        'an amount of 0': withEntry((m) => m['amount_minor'] = 0),
        'a float amount': withEntry((m) => m['amount_minor'] = 45.5),
        'a spend with no category': withEntry((m) => m['category'] = null),
        'a note over the limit': withEntry(
          (m) => m['note'] = 'x' * (maxNoteLength + 1),
        ),
        'no date': withEntry((m) => m.remove('local_date')),
        'an entry with no id': JournalSnapshot(
          entries: {'': good.entries.values.first},
          goals: good.goals,
          categories: good.categories,
          settings: good.settings,
        ),
        'an unreadable goal': JournalSnapshot(
          entries: good.entries,
          goals: {
            ...good.goals,
            'g-bad': {'name': 'Bike'},
          },
          categories: good.categories,
          settings: good.settings,
        ),
        // Values this build can't show: a currency it doesn't list (money
        // can't be formatted), an amount over the cap (the screens that edit
        // it can't open). A later build that adds a currency writes these.
        'an entry in a currency this build doesn\'t list': withEntry(
          (m) => m['currency'] = 'XYZ',
        ),
        'an entry over the cap': withEntry(
          (m) => m['amount_minor'] = maxAmountMinor + 1,
        ),
        'a goal target over the cap': withGoal(
          (m) => m['target_minor'] = maxAmountMinor + 1,
        ),
        'a goal start over the cap': withGoal(
          (m) => m['start_minor'] = maxAmountMinor + 1,
        ),
        'a plan over the cap': withSetting('plan_minor', maxAmountMinor + 1),
        'a setting that never travels': withSetting('device.account', 'x'),
        'a currency this build doesn\'t list': withSetting('currency', 'XYZ'),
        'a lowercase currency': withSetting('currency', 'thb'),
        'a plan below 1': withSetting('plan_minor', -5),
        'picks that aren\'t names': withSetting('picks', [1, 2]),
        'a celebration with no goal': withSetting('celebrated.', true),
        'a celebration that isn\'t a flag': withSetting('celebrated.g', 'yes'),
        'a pig switch that isn\'t a flag': withSetting('letters_off', 'yes'),
        'a letter month that isn\'t one': withSetting(
          'letter_dismissed',
          '2026-13',
        ),
        // Schema 2: repeats (E) and money in another currency (#74), as the
        // store writes them.
        'an unreadable repeat': withRepeat((m) => m['kind'] = 'yearly'),
        'a repeat over the cap': withRepeat(
          (m) => m['amount_minor'] = maxAmountMinor + 1,
        ),
        'a repeat in a currency this build doesn\'t list': withRepeat(
          (m) => m['currency'] = 'XYZ',
        ),
        'a repeating spend with no category': withRepeat(
          (m) => m['category'] = null,
        ),
        'a repeat in your own category the backup doesn\'t carry': withRepeat(
          (m) => m['category'] = 'c:gone',
        ),
        'a repeat with no id': JournalSnapshot(
          entries: good.entries,
          goals: good.goals,
          categories: good.categories,
          repeats: {'': good.repeats.values.single},
          settings: good.settings,
        ),
        'a rate this build can\'t read': withEuro(
          (m) => m['rate'] = {'units': 0, 'scale': 2, 'dir': 'to_home'},
        ),
        'a rate without its home amount': withEuro(
          (m) => m.remove('home_minor'),
        ),
        'a home amount over the cap': withEuro(
          (m) => m['home_minor'] = maxAmountMinor + 1,
        ),
        'a last rate this build can\'t read': withSetting('rates', {
          'EUR': {'units': -1, 'scale': 2, 'dir': 'to_home'},
        }),
        'a last rate for a currency this build doesn\'t list': withSetting(
          'rates',
          {
            'XYZ': {'units': 3912, 'scale': 2, 'dir': 'to_home'},
          },
        ),
        'a seen mark that isn\'t a time': withSetting(
          'repeats_seen_at',
          'soon',
        ),
        'seen ids that aren\'t ids': withSetting('repeats_seen_ids', [1]),
      };
      for (final MapEntry(key: what, value: snapshot) in bad.entries) {
        await expectLater(
          target.replaceWith(snapshot),
          throwsA(isA<FormatException>()),
          reason: what,
        );
        expect(plain(await target.snapshot()), plain(before), reason: what);
      }
    });

    test('the reminder comes back off, at its time', () {
      final back = BackupSnapshot.fromJson(
        jsonDecode(
          jsonEncode(
            BackupSnapshot(
              journal: const JournalSnapshot(
                entries: {},
                goals: {},
                settings: {},
              ),
              prefs: prefs,
            ).toJson(),
          ),
        ),
      );
      expect(back.prefs.reminderWasOn, isTrue);
      expect(back.prefs.restoredReminder.on, isFalse);
      expect(back.prefs.restoredReminder.time.wire, '21:30');
    });
  });

  group('never in a backup', () {
    test('the lock, the device account and device-only flags', () async {
      const pinHash = 'v2:c2FsdHNhbHQ=:aGFzaGhhc2g=';
      SharedPreferences.setMockInitialValues({
        'app_lock.on': true,
        'app_lock.restore_notice': true,
        'app_lock.installed': true,
        'app_lock.pin_hash': pinHash,
        'device.account': jsonEncode({'v': 1, 'id': 'device-id-7f3a'}),
        'device.account_on_device': true,
        'device.welcome_seen': true,
        'device.locale': 'th',
        'device.appearance': 'dark',
        'device.pig_name': 'Oink',
      });
      final local = await SharedLocalPrefs.load();
      await fill(store);
      final json = jsonEncode(
        BackupSnapshot(
          journal: await store.snapshot(),
          prefs: PrefsSnapshot.take(
            local,
            reminderOn: true,
            reminderTime: const ReminderTime(21, 30),
          ),
        ).toJson(),
      );
      for (final never in [
        'app_lock',
        pinHash,
        'device-id-7f3a',
        'device.',
        'welcome',
        'account',
      ]) {
        expect(json.contains(never), isFalse, reason: never);
      }
      expect(json, contains('"locale":"th"'));
      expect(json, contains('"appearance":"dark"'));
      expect(json, contains('"pig_name":"Oink"'));
    });

    test('every journal setting the store writes is classified: it travels '
        'or stays on the phone', () {
      final source = File('lib/journal/journal_store.dart').readAsStringSync();
      final written = {
        for (final m in RegExp(
          r"_settings\s*\.record\(\s*'([^']+)'",
        ).allMatches(source))
          m[1]!,
      };
      expect(written, isNotEmpty);
      for (final key in written) {
        expect(
          key.startsWith('celebrated.') ||
              JournalStore.travels.contains(key) ||
              JournalStore.staysOnPhone.contains(key),
          isTrue,
          reason: '$key: add it to JournalStore.travels or staysOnPhone',
        );
      }
      expect(
        JournalStore.travels.difference(written),
        isEmpty,
        reason: 'a key that travels but nothing writes',
      );
      // A new store (a later feature's records) is a choice as well: it
      // goes in the backup, with a schema step, or it's named as staying.
      final stores = {
        for (final m in RegExp(
          r"(?:store|StoreRef<[^>]*>)\(\s*'([^']+)'",
        ).allMatches(source))
          m[1]!,
      };
      expect(stores, JournalStore.backedUpStores);
    });
  });

  group('a snapshot this build can\'t read', () {
    Map<String, Object?> json() => BackupSnapshot(
      journal: const JournalSnapshot(entries: {}, goals: {}, settings: {}),
      prefs: prefs,
    ).toJson();

    test('not a backup', () {
      Map<String, Object?> edited(void Function(Map<String, Object?>) f) {
        final m = jsonDecode(jsonEncode(json())) as Map<String, Object?>;
        f(m);
        return m;
      }

      Map<String, Object?> part(Map<String, Object?> m, String key) =>
          m[key]! as Map<String, Object?>;

      final bad = <String, Object?>{
        'null': null,
        'a list': [],
        'no schema': edited((m) => m.remove('schema')),
        'a schema as text': edited((m) => m['schema'] = '1'),
        'schema 0': edited((m) => m['schema'] = 0),
        'no journal': edited((m) => m.remove('journal')),
        'entries as a list': edited((m) => part(m, 'journal')['entries'] = []),
        'an entry that isn\'t a map': edited(
          (m) => part(m, 'journal')['entries'] = {'e1': 'x'},
        ),
        'an entry with no id': edited(
          (m) => part(m, 'journal')['entries'] = {'': <String, Object?>{}},
        ),
        'no repeats': edited((m) => part(m, 'journal').remove('repeats')),
        'repeats as a list': edited((m) => part(m, 'journal')['repeats'] = []),
        'no prefs': edited((m) => m.remove('prefs')),
        'a pig name as a number': edited(
          (m) => part(m, 'prefs')['pig_name'] = 3,
        ),
        'a time past midnight': edited(
          (m) => part(m, 'prefs')['reminder_time'] = '25:00',
        ),
        'a time without minutes': edited(
          (m) => part(m, 'prefs')['reminder_time'] = '9',
        ),
        'reminder on as text': edited(
          (m) => part(m, 'prefs')['reminder_on'] = 'yes',
        ),
        'a language as a number': edited((m) => part(m, 'prefs')['locale'] = 3),
      };
      for (final MapEntry(key: what, value: value) in bad.entries) {
        expect(
          () => BackupSnapshot.fromJson(value),
          throwsA(isA<NotABackup>()),
          reason: what,
        );
      }
    });

    test('a newer schema: the app needs updating first', () {
      expect(
        () => BackupSnapshot.fromJson({...json(), 'schema': backupSchema + 1}),
        throwsA(isA<BackupTooNew>()),
      );
    });

    test('an older schema is migrated first, and a missing step refuses', () {
      const next = backupSchema + 1;
      final migrated = BackupSnapshot.fromJson(
        json(),
        schema: next,
        migrations: {
          backupSchema: (m) => {
            ...m,
            'schema': next,
            'prefs': {...m['prefs']! as Map<String, Object?>, 'palette': 'p'},
          },
        },
      );
      expect(migrated.prefs.palette, 'p');
      expect(
        () => BackupSnapshot.fromJson(json(), schema: next, migrations: const {}),
        throwsA(isA<NotABackup>()),
      );
    });

    test('a schema 1 file, from before repeats, still reads: no repeats and '
        'no pig name', () {
      final one = jsonDecode(jsonEncode(json())) as Map<String, Object?>;
      one['schema'] = 1;
      (one['journal']! as Map<String, Object?>).remove('repeats');
      (one['prefs']! as Map<String, Object?>).remove('pig_name');
      final back = BackupSnapshot.fromJson(one);
      expect(back.journal.repeats, isEmpty);
      expect(back.prefs.pigName, isNull);
      expect(back.prefs.localeCode, 'th');
      expect(back.prefs.reminderTime.wire, '21:30');
    });
  });
}
