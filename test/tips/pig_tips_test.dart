import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart' show MemorySecretStore;
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/data/models.dart' show ConsentItem, ConsentKind;
import 'package:piggybow/tips/pig_tips.dart';
import 'package:piggybow/tips/tip_request.dart';
import 'package:piggybow/tips/tips.dart' show tipForDay;
import 'package:piggybow/tips/tips_endpoint.dart';
import 'package:piggybow/tips/tips_http.dart';

/// The tips project, faked: answers set per path (with its query), in order.
/// Nothing leaves the test.
class FakeTipsHttp implements TipsHttp {
  final paths = <String>[];
  final headers = <Map<String, String>>[];
  final bodies = <String?>[];
  final _answers = <String, List<Object>>{};

  /// Every call throws, as with no connection.
  bool offline = false;

  void answer(String path, Object answer) => (_answers[path] ??= []).add(answer);

  @override
  Future<TipsResponse> post(
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    final path = url.hasQuery ? '${url.path}?${url.query}' : url.path;
    paths.add(path);
    this.headers.add(headers);
    bodies.add(body);
    if (offline) throw const SocketException('offline');
    final queue = _answers[path];
    if (queue == null || queue.isEmpty) throw StateError('no answer for $path');
    final next = queue.removeAt(0);
    if (next is TipsResponse) return next;
    throw next;
  }
}

class _Clock extends Clock {
  _Clock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

const signupPath = '/auth/v1/signup';
const refreshPath = '/auth/v1/token?grant_type=refresh_token';
const tipPath = '/functions/v1/pig-tip';
const reportPath = '/functions/v1/pig-tip/report';
const forgetPath = '/functions/v1/pig-tip/forget';

final endpoint = TipsEndpoint(
  base: Uri.parse('https://tips.example.test'),
  publishableKey: 'sb_publishable_test',
  region: 'ap-northeast-1',
);

const week = TipRequest(
  language: 'en',
  weekday: 3,
  categoryShares: {'food': 60, 'transport': 40},
  feelings: {'worth_it': 1, 'not_sure': 0, 'not_really': 0, 'none': 1},
  saves: 1,
  planPercent: 40,
  activeGoals: 1,
  picks: ['save'],
);

TipsResponse authAnswer({String access = 'access-1', String refresh = 'refresh-1'}) => TipsResponse(
  200,
  body: jsonEncode({
    'access_token': access,
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': refresh,
    'user': {'id': 'anon-1', 'is_anonymous': true},
  }),
);

TipsResponse tipAnswer({
  String text = 'You could keep one evening for something that feels worth it.',
  String sig = 'sig-1',
  String? model = 'claude-sonnet-5-5',
}) => TipsResponse(
  200,
  headers: {'x-tip-model': ?model},
  body: jsonEncode({'tip': text, 'sig': sig}),
);

const reported = WrittenTip(
  day: '2026-12-02',
  text: 'Maybe a slow morning walk.',
  model: 'claude-sonnet-5-5',
  sig: 'sig-9',
);

/// The pig tips client against a fake tips project: turning on (consents,
/// then an anonymous sign-up), one written tip a local day with the day's
/// static tip for anything else, the token's refresh, Report, and turning
/// off (the server delete, now or later), Delete everything included.
void main() {
  late FakeTipsHttp http;
  late MemorySecretStore store;
  late _Clock clock;
  late List<List<ConsentItem>> consents;
  late List<int> requestsBeforeConsent;
  var language = 'en';
  // Wednesday 2 December 2026, 09:00 in Bangkok.
  final staticToday = StaticTip(tipForDay(DateTime(2026, 12, 2)));

  setUp(() {
    http = FakeTipsHttp();
    store = MemorySecretStore();
    clock = _Clock(DateTime.utc(2026, 12, 2, 2));
    consents = [];
    requestsBeforeConsent = [];
    language = 'en';
  });

  PigTipsService tips({
    bool enabled = true,
    bool noEndpoint = false,
    Future<TipRequest> Function(String todayWire)? requestFor,
  }) => PigTipsService(
    enabled: enabled,
    endpoint: noEndpoint ? null : endpoint,
    http: http,
    store: store,
    clock: clock,
    language: () => language,
    requestFor: requestFor ?? (_) async => week,
    recordConsents: (c) async {
      requestsBeforeConsent.add(http.paths.length);
      consents.add(c);
    },
  );

  /// A client turned on, with what that sent forgotten.
  Future<PigTipsService> turnedOn() async {
    final t = tips();
    http.answer(signupPath, authAnswer());
    await t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1');
    http.paths.clear();
    http.headers.clear();
    http.bodies.clear();
    consents.clear();
    return t;
  }

  test('offered: the build flag, an endpoint, and the app in English', () {
    expect(tips().offered, isTrue);
    expect(tips(enabled: false).offered, isFalse);
    expect(tips(noEndpoint: true).offered, isFalse);
    language = 'th';
    expect(tips().offered, isFalse);
  });

  test('turnOn: the consents first, then an anonymous sign-up with the publishable key; then on', () async {
    final t = tips();
    http.answer(signupPath, authAnswer());
    await t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1');
    expect(consents, [
      [const ConsentItem(ConsentKind.ai, 'ai-1'), const ConsentItem(ConsentKind.age18, 'age-1')],
    ]);
    expect(requestsBeforeConsent, [0], reason: 'nothing is sent before the consents');
    expect(http.paths, [signupPath]);
    expect(http.headers.single, {'apikey': 'sb_publishable_test'});
    expect(http.bodies.single, '{}');
    expect(t.on.value, isTrue);
    expect(store.values.keys, [PigTipsService.sessionKey]);
  });

  test('turnOn with no answer, or a refusal: PigTipsUnavailable, still off, nothing kept', () async {
    final t = tips();
    http.offline = true;
    await expectLater(t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1'), throwsA(isA<PigTipsUnavailable>()));
    http.offline = false;
    http.answer(signupPath, const TipsResponse(429));
    await expectLater(t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1'), throwsA(isA<PigTipsUnavailable>()));
    http.answer(signupPath, const TipsResponse(200, body: '{"user": {}}'));
    await expectLater(t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1'), throwsA(isA<PigTipsUnavailable>()));
    expect(t.on.value, isFalse);
    expect(store.values, isEmpty);
    // Not offered: never asks.
    language = 'th';
    http.paths.clear();
    await expectLater(t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1'), throwsA(isA<PigTipsUnavailable>()));
    expect(http.paths, isEmpty);
  });

  test("off, or not offered: the day's static tip, and nothing is sent", () async {
    expect(await tips().tipFor('2026-12-02'), staticToday);
    final on = await turnedOn();
    language = 'th';
    expect(await on.tipFor('2026-12-02'), staticToday);
    expect(http.paths, isEmpty);
  });

  test('on: the week goes with the publishable key, the token and the region; its tip is kept for the day', () async {
    final t = await turnedOn();
    http.answer(tipPath, tipAnswer());
    final tip = await t.tipFor('2026-12-02');
    expect(
      tip,
      const WrittenTip(
        day: '2026-12-02',
        text: 'You could keep one evening for something that feels worth it.',
        model: 'claude-sonnet-5-5',
        sig: 'sig-1',
      ),
    );
    expect(http.paths, [tipPath]);
    expect(http.headers.single, {
      'apikey': 'sb_publishable_test',
      'Authorization': 'Bearer access-1',
      'x-region': 'ap-northeast-1',
    });
    expect(jsonDecode(http.bodies.single!), week.toJson());
    // Kept for the day: no second ask, even after a new start.
    expect(await t.tipFor('2026-12-02'), tip);
    final restarted = tips();
    await restarted.load();
    expect(await restarted.tipFor('2026-12-02'), tip);
    expect(http.paths, [tipPath]);
    // The next day asks again.
    http.answer(tipPath, tipAnswer(text: 'Maybe a slow morning walk.', sig: 'sig-2'));
    expect((await t.tipFor('2026-12-03') as WrittenTip).text, 'Maybe a slow morning walk.');
    expect(http.paths, [tipPath, tipPath]);
  });

  test("once a local day: a 204, 429 or 503, a timeout or no answer is the day's static tip, never a second ask", () async {
    for (final answer in <Object>[
      const TipsResponse(204),
      const TipsResponse(429),
      const TipsResponse(503),
      TimeoutException('slow'),
      const SocketException('offline'),
    ]) {
      http = FakeTipsHttp();
      store = MemorySecretStore();
      final t = await turnedOn();
      http.answer(tipPath, answer);
      expect(await t.tipFor('2026-12-02'), staticToday, reason: '$answer');
      final restarted = tips();
      await restarted.load();
      expect(restarted.on.value, isTrue);
      expect(await restarted.tipFor('2026-12-02'), staticToday, reason: 'after a new start: $answer');
      expect(http.paths, [tipPath], reason: 'asked once: $answer');
    }
  });

  test('a 200 without a usable tip, signature or model is no tip', () async {
    for (final answer in [
      tipAnswer(sig: ''),
      tipAnswer(sig: 'x' * 101),
      tipAnswer(model: null),
      tipAnswer(text: '  '),
      const TipsResponse(200, body: 'not json'),
    ]) {
      http = FakeTipsHttp();
      store = MemorySecretStore();
      final t = await turnedOn();
      http.answer(tipPath, answer);
      expect(await t.tipFor('2026-12-02'), staticToday, reason: answer.body);
    }
  });

  test("tipFor never throws: a week it can't build is the static tip", () async {
    http.answer(signupPath, authAnswer());
    final t = tips(requestFor: (_) async => throw StateError('no journal'));
    await t.turnOn(aiVersion: 'ai-1', age18Version: 'age-1');
    expect(await t.tipFor('2026-12-02'), staticToday);
  });

  test('two asks at once on a day: one request', () async {
    final t = await turnedOn();
    http.answer(tipPath, tipAnswer());
    final both = await Future.wait([t.tipFor('2026-12-02'), t.tipFor('2026-12-02')]);
    expect(both[0], isA<WrittenTip>());
    expect(both[1], both[0]);
    expect(http.paths, [tipPath]);
  });

  test('a token that ran out is refreshed first; a 401 refreshes once and asks again', () async {
    final t = await turnedOn();
    clock.now = clock.now.add(const Duration(hours: 2));
    http.answer(refreshPath, authAnswer(access: 'access-2', refresh: 'refresh-2'));
    http.answer(tipPath, const TipsResponse(401));
    http.answer(refreshPath, authAnswer(access: 'access-3', refresh: 'refresh-3'));
    http.answer(tipPath, tipAnswer());
    expect(await t.tipFor('2026-12-02'), isA<WrittenTip>());
    expect(http.paths, [refreshPath, tipPath, refreshPath, tipPath]);
    expect(jsonDecode(http.bodies[0]!), {'refresh_token': 'refresh-1'});
    expect(http.headers[0], {'apikey': 'sb_publishable_test'});
    expect(http.headers[1]['Authorization'], 'Bearer access-2');
    expect(jsonDecode(http.bodies[2]!), {'refresh_token': 'refresh-2'});
    expect(http.headers[3]['Authorization'], 'Bearer access-3');
  });

  test('a refresh the server refuses: the session is gone, and tips are off', () async {
    final t = await turnedOn();
    clock.now = clock.now.add(const Duration(hours: 2));
    http.answer(refreshPath, const TipsResponse(400, body: '{"error": "invalid_grant"}'));
    expect(await t.tipFor('2026-12-02'), staticToday);
    expect(t.on.value, isFalse);
    expect(store.values.containsKey(PigTipsService.sessionKey), isFalse);
  });

  test('report: the tip as given, its reason, model and signature; kept for later only with no answer', () async {
    final t = await turnedOn();
    http.answer(reportPath, const TipsResponse(204));
    await t.report(reported, TipReportReason.wrong);
    expect(jsonDecode(http.bodies.single!), {
      'tip': 'Maybe a slow morning walk.',
      'reason': 'wrong',
      'model': 'claude-sonnet-5-5',
      'sig': 'sig-9',
    });
    expect(http.headers.single['Authorization'], 'Bearer access-1');
    // Refused, or over the day's limits: final, never sent again.
    for (final status in [400, 429]) {
      http.answer(reportPath, TipsResponse(status));
      await t.report(reported, TipReportReason.other);
    }
    expect(store.values.containsKey(PigTipsService.reportsKey), isFalse);
    // No answer, or a server error: kept, and sent at the next resume.
    http.offline = true;
    await t.report(reported, TipReportReason.advice);
    http.offline = false;
    http.answer(reportPath, const TipsResponse(503));
    await t.report(reported, TipReportReason.upsetting);
    expect(store.values.containsKey(PigTipsService.reportsKey), isTrue);
    http.paths.clear();
    http.bodies.clear();
    http.answer(reportPath, const TipsResponse(204));
    http.answer(reportPath, const TipsResponse(204));
    await t.resumePending();
    expect([for (final b in http.bodies) jsonDecode(b!)['reason']], ['advice', 'upsetting']);
    expect(store.values.containsKey(PigTipsService.reportsKey), isFalse);
  });

  test("a reported tip gives way to the day's static tip for the rest of the day, after a restart too", () async {
    final t = await turnedOn();
    http.answer(tipPath, tipAnswer());
    final tip = await t.tipFor('2026-12-02') as WrittenTip;
    // Offline: the report waits, but the tip is set aside at once.
    http.offline = true;
    await t.report(tip, TipReportReason.upsetting);
    expect(await t.tipFor('2026-12-02'), staticToday);
    final restarted = tips();
    await restarted.load();
    expect(await restarted.tipFor('2026-12-02'), staticToday);
    expect(http.paths.where((p) => p == tipPath), hasLength(1), reason: 'never asked again that day');
    // The next day's tip is a new one.
    http.offline = false;
    http.answer(reportPath, const TipsResponse(204));
    http.answer(tipPath, tipAnswer(text: 'Maybe a slow morning walk.', sig: 'sig-2'));
    expect(await t.tipFor('2026-12-03'), isA<WrittenTip>());
    // A fake that does the same, for the screens' tests.
    final fake = FakePigTips(on: true, tip: tip);
    await fake.report(tip, TipReportReason.wrong);
    expect(await fake.tipFor('2026-12-02'), staticToday);
  });

  test('turnOff: off at once, the withdrawal recorded, and the id deleted on the server', () async {
    final t = await turnedOn();
    http.answer(forgetPath, const TipsResponse(204));
    await t.turnOff();
    expect(t.on.value, isFalse);
    expect(consents, [
      [const ConsentItem(ConsentKind.ai, 'ai-1', granted: false)],
    ]);
    expect(http.paths, [forgetPath]);
    expect(http.headers.single['Authorization'], 'Bearer access-1');
    expect(http.bodies.single, isNull);
    expect(store.values, isEmpty);
    expect(await t.tipFor('2026-12-02'), staticToday);
  });

  test('turnOff with no connection: the delete waits for a later resume, after its queued report', () async {
    final t = await turnedOn();
    http.offline = true;
    await t.report(reported, TipReportReason.unhelpful);
    await t.turnOff();
    expect(t.on.value, isFalse);
    expect(store.values.keys.toSet(), {PigTipsService.forgetKey, PigTipsService.reportsKey});
    http.offline = false;
    http.paths.clear();
    http.answer(reportPath, const TipsResponse(204));
    http.answer(forgetPath, const TipsResponse(204));
    await t.resumePending();
    expect(http.paths, [reportPath, forgetPath]);
    expect(store.values, isEmpty);
  });

  test("Delete everything: a delete eraseBegin couldn't send outlives the erase", () async {
    final t = await turnedOn();
    http.offline = true;
    final pending = await t.eraseBegin();
    expect(t.on.value, isFalse);
    expect(pending, isNotNull);
    await store.deleteAll();
    await t.eraseEnd(pending);
    expect(store.values.keys, contains(PigTipsService.forgetKey));
    http.offline = false;
    http.answer(forgetPath, const TipsResponse(204));
    await t.resumePending();
    expect(http.paths.last, forgetPath);
    expect(store.values, isEmpty);
  });

  test('Delete everything, online: the id is deleted at once, and nothing is left to keep', () async {
    final t = await turnedOn();
    http.answer(forgetPath, const TipsResponse(204));
    expect(await t.eraseBegin(), isNull);
    expect(http.paths, [forgetPath]);
    await t.eraseEnd(null);
    expect(store.values, isEmpty);
  });

  test('load: on when a session is on the phone', () async {
    await turnedOn();
    final restarted = tips();
    expect(restarted.on.value, isFalse);
    await restarted.load();
    expect(restarted.on.value, isTrue);
  });
}
