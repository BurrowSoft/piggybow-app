import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/export/csv_export.dart';
import 'package:piggybow/money/rate.dart';

/// A small RFC 4180 reader for the tests: quoted cells, doubled quotes, CRLF records.
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      i += 2;
      continue;
    } else {
      cell.write(c);
    }
    i++;
  }
  if (cell.isNotEmpty || row.isNotEmpty) rows.add([...row, cell.toString()]);
  return rows;
}

/// The file without its BOM, read back.
List<List<String>> roundTrip(List<CsvRow> rows) => readCsv(buildCsv(rows).substring(1));

CsvRow spend({String note = 'Lunch', String date = '2026-12-02'}) => CsvRow(
  localDate: date,
  type: 'spent',
  amountMinor: 12050,
  currency: 'THB',
  category: 'food',
  feeling: 'worth_it',
  note: note,
  homeMinor: 12050,
  homeCurrency: 'THB',
);

const header = 'date,type,amount,currency,category,feeling,note,goal,home_amount,home_currency,rate';

void main() {
  test('an empty export is the BOM and the header, ending in CRLF', () {
    expect(buildCsv(const []), '\uFEFF$header\r\n');
  });

  test('the file starts with the UTF-8 BOM bytes EF BB BF', () {
    expect(utf8.encode(buildCsv(const [])).take(3), [0xEF, 0xBB, 0xBF]);
  });

  test('a spend and a save, exactly', () {
    final csv = buildCsv([
      spend(),
      const CsvRow(
        localDate: '2026-12-03',
        type: 'saved',
        amountMinor: 50000,
        currency: 'THB',
        note: '',
        goalName: 'Trip to Chiang Mai',
        homeMinor: 50000,
        homeCurrency: 'THB',
      ),
      const CsvRow(
        localDate: '2026-12-04',
        type: 'saved',
        amountMinor: 1200,
        currency: 'JPY',
        note: 'Coins',
        homeMinor: 1200,
        homeCurrency: 'JPY',
      ),
    ]);
    expect(
      csv,
      '\uFEFF$header\r\n'
      '2026-12-02,spent,120.50,THB,food,worth_it,Lunch,,120.50,THB,\r\n'
      '2026-12-03,saved,500.00,THB,,,,Trip to Chiang Mai,500.00,THB,\r\n'
      '2026-12-04,saved,1200,JPY,,,Coins,,1200,JPY,\r\n',
    );
  });

  test('every line ends in CRLF; no bare LF outside a quoted note', () {
    final csv = buildCsv([spend(), spend(note: 'Bus')]);
    expect(csv.replaceAll('\r\n', '').contains('\n'), isFalse);
    expect(csv.endsWith('\r\n'), isTrue);
  });

  test('rows keep the order they are given in', () {
    final rows = roundTrip([spend(date: '2026-12-09'), spend(date: '2026-12-01'), spend(date: '2026-12-05')]);
    expect(rows.skip(1).map((r) => r.first), ['2026-12-09', '2026-12-01', '2026-12-05']);
  });

  group('RFC 4180: notes come back exactly', () {
    for (final note in [
      'Coffee, cake',
      'The "big" shop',
      'Line one\nline two',
      'Line one\r\nline two',
      '"',
      ',',
      '',
      '  spaces kept  ',
    ]) {
      test(note.replaceAll('\n', r'\n').replaceAll('\r', r'\r'), () {
        final rows = roundTrip([spend(note: note)]);
        expect(rows.length, 2);
        expect(rows[1].length, 11);
        expect(rows[1][6], note);
      });
    }
  });

  group('formula starts get one apostrophe', () {
    for (final start in ['=', '+', '-', '@', '\t', '\r']) {
      test('a note starting with ${start == '\t' ? 'a tab' : start == '\r' ? 'a CR' : start}', () {
        final note = '${start}SUM(A1:A9)';
        expect(roundTrip([spend(note: note)])[1][6], "'$note");
      });
    }

    test('"=" in the middle of a note is left alone', () {
      expect(roundTrip([spend(note: 'a=b')])[1][6], 'a=b');
    });

    test('apostrophes already there are counted, so one removal restores the note', () {
      expect(roundTrip([spend(note: "'=x")])[1][6], "''=x");
      expect(roundTrip([spend(note: "it's fine")])[1][6], "it's fine");
      expect(roundTrip([spend(note: "'hello")])[1][6], "'hello");
    });

    test("the goal's name is protected the same way", () {
      const row = CsvRow(
        localDate: '2026-12-03',
        type: 'saved',
        amountMinor: 100,
        currency: 'USD',
        note: '',
        goalName: '=HYPERLINK("x")',
        homeMinor: 100,
        homeCurrency: 'USD',
      );
      expect(roundTrip([row])[1][7], '\'=HYPERLINK("x")');
    });
  });

  test('80-character notes made of multi-part characters come back exactly', () {
    // Each unit is one character as people see it, made of several code points.
    for (final unit in ['👨\u200D👩\u200D👧', 'ก้', '🇹🇭', 'e\u0301', '👍🏽']) {
      final note = List.filled(80, unit).join();
      expect(roundTrip([spend(note: note)])[1][6], note, reason: unit);
    }
  });

  test('amounts use "." and no grouping, whatever the currency', () {
    final rows = roundTrip([
      for (final (minor, currency) in [(999999999999, 'EUR'), (5, 'USD'), (1500000, 'VND')])
        CsvRow(
          localDate: '2026-12-02',
          type: 'spent',
          amountMinor: minor,
          currency: currency,
          category: 'other',
          note: '',
          homeMinor: minor,
          homeCurrency: currency,
        ),
    ]);
    expect(rows.skip(1).map((r) => r[2]), ['9999999999.99', '0.05', '1500000']);
  });

  test('a malformed date, an unknown type or a negative amount throws', () {
    expect(() => buildCsv([spend(date: '2026-12-2')]), throwsArgumentError);
    expect(() => buildCsv([spend(date: '02/12/2026')]), throwsArgumentError);
    expect(
      () => buildCsv([
        const CsvRow(
          localDate: '2026-12-02',
          type: 'spend',
          amountMinor: 1,
          currency: 'USD',
          note: '',
          homeMinor: 1,
          homeCurrency: 'USD',
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => buildCsv([
        const CsvRow(
          localDate: '2026-12-02',
          type: 'spent',
          amountMinor: -1,
          currency: 'USD',
          note: '',
          homeMinor: -1,
          homeCurrency: 'USD',
        ),
      ]),
      throwsArgumentError,
    );
  });

  group('the home currency (feature 19): the last three columns', () {
    CsvRow trip({
      int amountMinor = 1234,
      String currency = 'EUR',
      int homeMinor = 48274,
      String homeCurrency = 'THB',
      String rateText = '1 EUR = 39.12 THB',
    }) => CsvRow(
      localDate: '2026-12-02',
      type: 'spent',
      amountMinor: amountMinor,
      currency: currency,
      category: 'food',
      note: '',
      homeMinor: homeMinor,
      homeCurrency: homeCurrency,
      rateText: rateText,
    );

    test('a spend in another currency: as spent, then at home, with its rate', () {
      final rows = roundTrip([
        trip(),
        trip(amountMinor: 1000, currency: 'JPY', homeMinor: 23010, rateText: '1 JPY = 0.2301 THB'),
        trip(rateText: '1 THB = 0.0256 EUR'),
      ]);
      expect(rows[1], ['2026-12-02', 'spent', '12.34', 'EUR', 'food', '', '', '', '482.74', 'THB', '1 EUR = 39.12 THB']);
      expect(rows[2].sublist(2, 4), ['1000', 'JPY']);
      expect(rows[2].sublist(8), ['230.10', 'THB', '1 JPY = 0.2301 THB']);
      expect(rows[3].last, '1 THB = 0.0256 EUR');
    });

    test('a rate typed with a comma is written with "." (the file reads the same everywhere)', () {
      final typed = parseRate('39,12', RateDirection.toHome, mark: ',').rate!;
      final text = rateText(typed, currency: 'EUR', home: 'THB');
      expect(text, '1 EUR = 39.12 THB');
      expect(roundTrip([trip(rateText: text)])[1].last, '1 EUR = 39.12 THB');
    });

    test('no home currency throws', () {
      expect(() => buildCsv([trip(homeCurrency: '')]), throwsArgumentError);
    });

    test('a home-currency row with a rate, or another amount at home, throws', () {
      expect(
        () => buildCsv([trip(currency: 'THB', amountMinor: 48274, homeMinor: 48274)]),
        throwsArgumentError,
        reason: 'a rate in the home currency',
      );
      expect(
        () => buildCsv([trip(currency: 'THB', amountMinor: 48274, homeMinor: 48275, rateText: '')]),
        throwsArgumentError,
        reason: 'home_amount must be the amount',
      );
    });

    test('a row in another currency without its rate throws', () {
      expect(() => buildCsv([trip(rateText: '')]), throwsArgumentError);
    });
  });

  test('the file name uses the local date', () {
    expect(csvFileName(DateTime(2026, 11, 28, 23, 59)), 'piggybow-2026-11-28.csv');
    expect(csvFileName(DateTime(2027, 1, 2)), 'piggybow-2027-01-02.csv');
  });
}
