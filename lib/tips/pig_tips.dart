// Pig tips, the app's side: the switch, the anonymous id, one written tip a
// local day, "Report this tip", and turning it all off. The week's summary
// (tip_request.dart) is the only journal data sent; the anonymous id and the
// IP address go with it, as with any connection. Any failure shows the day's
// static tip, and the app asks again only the next local day.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/app_lock.dart' show SecretStore;
import '../core/clock.dart';
import '../data/models.dart' show ConsentItem, ConsentKind;
import 'tip_request.dart' show TipRequest;
import 'tips.dart' show tipForDay;
import 'tips_endpoint.dart';
import 'tips_http.dart';

/// Tips can't be turned on now: the server didn't answer, or refused. The
/// switch stays off; [why] is a short code for the log, never shown.
class PigTipsUnavailable implements Exception {
  const PigTipsUnavailable(this.why);

  final String why;

  @override
  String toString() => 'PigTipsUnavailable: $why';
}

/// "Report this tip": the reasons the server takes.
enum TipReportReason { unhelpful, wrong, upsetting, advice, other }

/// Today's idea: the day's written tip, or the day's static one.
sealed class TipOfDay {
  const TipOfDay();
}

/// A tip the model wrote for [day] (YYYY-MM-DD), with what a report sends
/// back: the [model] that wrote it and the server's signature [sig]. Only
/// [PigTips.tipFor] makes one.
final class WrittenTip extends TipOfDay {
  const WrittenTip({
    required this.day,
    required this.text,
    required this.model,
    required this.sig,
  });

  final String day;
  final String text;
  final String model;
  final String sig;

  /// Longer than any tip the server lets out: a longer one is no tip.
  static const maxText = 400;

  /// The longest model name and signature kept.
  static const maxModel = 64;
  static const maxSig = 100;

  static bool usable(String text, String model, String sig) =>
      text.trim().isNotEmpty &&
      text.length <= maxText &&
      model.isNotEmpty &&
      model.length <= maxModel &&
      sig.isNotEmpty &&
      sig.length <= maxSig;

  Map<String, String> toJson() => {'day': day, 'text': text, 'model': model, 'sig': sig};

  static WrittenTip? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = json['day'], text = json['text'], model = json['model'], sig = json['sig'];
    if (day is! String || text is! String || model is! String || sig is! String) return null;
    if (parseWireDate(day) == null || !usable(text, model, sig)) return null;
    return WrittenTip(day: day, text: text, model: model, sig: sig);
  }

  @override
  bool operator ==(Object other) =>
      other is WrittenTip &&
      other.day == day &&
      other.text == text &&
      other.model == model &&
      other.sig == sig;

  @override
  int get hashCode => Object.hash(day, text, model, sig);

  @override
  String toString() => 'WrittenTip($day, $model)';
}

/// One of the app's own tips (tips.dart): [index], 1 to 20, is the day's.
final class StaticTip extends TipOfDay {
  const StaticTip(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is StaticTip && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'StaticTip($index)';
}

abstract interface class PigTips {
  /// This build asks for tips (AI_TIPS_ENABLED and an endpoint) and the app
  /// is in English: only English is offered tips for now. False: no Me row,
  /// no sheet, the static tips only.
  bool get offered;

  /// On: the consents recorded and an anonymous id on this phone.
  ValueListenable<bool> get on;

  /// After "Yes, turn on tips" on the consent sheet, which says tips are for
  /// adults (18+, a line of the sheet, not a box): records the AI and 18+
  /// consents with these versions, then signs in anonymously.
  /// Throws [PigTipsUnavailable] when the server can't be reached or refuses;
  /// tips stay off.
  Future<void> turnOn({required String aiVersion, required String age18Version});

  /// Off at once, and the AI consent's withdrawal recorded. The anonymous id
  /// is deleted on the server (after any reports still to send), now or, with
  /// no connection, at a later start or resume.
  Future<void> turnOff();

  /// Never throws. When on: the day's written tip (asked once a local day,
  /// and kept for the day), else the day's static tip.
  Future<TipOfDay> tipFor(String todayWire);

  /// "Report this tip": its text, its model, its signature and the reason.
  /// The reported tip gives way to its day's static tip for the rest of that
  /// day, after a restart too. Never throws: with no answer, the report is
  /// sent at a later start or resume.
  Future<void> report(WrittenTip tip, TipReportReason reason);

  /// Delete everything, before the phone's secure storage is erased: tips
  /// off, and the anonymous id's server delete (its reports first) tried
  /// now. Returns what's still to send, for [eraseEnd].
  Future<String?> eraseBegin();

  /// Delete everything, after the erase: what [eraseBegin] couldn't send yet
  /// is kept again, and sent at a later start or resume. The promise to
  /// delete the id outlives the erase.
  Future<void> eraseEnd(String? pending);
}

/// The tips client: the tips project through [TipsHttp], the anonymous
/// session and the day's answer in [SecretStore] (never in a backup).
class PigTipsService implements PigTips {
  PigTipsService({
    required this._enabled,
    required this._endpoint,
    required this._http,
    required this._store,
    required this._clock,
    required this._language,
    required this._requestFor,
    required this._recordConsents,
  });

  final bool _enabled;
  final TipsEndpoint? _endpoint;
  final TipsHttp _http;
  final SecretStore _store;
  final Clock _clock;
  final String Function() _language;
  final Future<TipRequest> Function(String todayWire) _requestFor;
  final Future<void> Function(List<ConsentItem> consents) _recordConsents;

  /// The anonymous session: its tokens, when the access token runs out, and
  /// the AI consent's version (for its withdrawal).
  static const sessionKey = 'pig_tips_session';

  /// The day's answer: a written tip, or none (the static tip).
  static const dayKey = 'pig_tips_day';

  /// A turned-off session whose server delete is still to send.
  static const forgetKey = 'pig_tips_forget';

  /// Reports with no answer yet, oldest first.
  static const reportsKey = 'pig_tips_reports';

  /// The last local day a tip was asked on this phone: only a date, tied to
  /// no id, and kept when tips are turned off and on, so that day is never
  /// asked again (one written tip a phone a day, whatever the toggles).
  static const askedKey = 'pig_tips_asked_day';

  /// The most reports kept to send later; older ones go first.
  static const maxQueuedReports = 20;

  /// A tip waits for the model (the server allows it about half a minute).
  static const tipTimeout = Duration(seconds: 40);
  static const shortTimeout = Duration(seconds: 15);

  final _on = ValueNotifier<bool>(false);

  /// The day being asked, so a second call that day waits for the first.
  String? _askingDay;
  Future<TipOfDay>? _asking;

  /// Queue and delete work, one at a time.
  Future<void>? _tail;

  @override
  bool get offered => _enabled && _endpoint != null && _language() == 'en';

  @override
  ValueListenable<bool> get on => _on;

  /// At start: on when there's a session on the phone; then what's still to
  /// send.
  Future<void> load() async {
    _on.value = await _readSession(sessionKey) != null;
    unawaited(resumePending());
  }

  /// What's still to send, best effort: a turned-off id's delete (after its
  /// reports), and reports that couldn't go when made. Never throws.
  Future<void> resumePending() => _oneAtATime(() async {
    try {
      await _resumeForget();
      if (await _readSession(sessionKey) != null) await _sendQueued(sessionKey);
    } on Object {
      // Tried again at the next start or resume.
    }
  });

  @override
  Future<void> turnOn({required String aiVersion, required String age18Version}) async {
    if (!offered) throw const PigTipsUnavailable('not_offered');
    if (await _readSession(sessionKey) != null) {
      _on.value = true;
      return;
    }
    // An earlier id still to delete goes first.
    await resumePending();
    final language = _language();
    await _recordConsents([
      ConsentItem(ConsentKind.ai, aiVersion, locale: language),
      ConsentItem(ConsentKind.age18, age18Version, locale: language),
    ]);
    final TipsResponse res;
    try {
      res = await _auth('/auth/v1/signup', const {});
    } on Object {
      throw const PigTipsUnavailable('no_answer');
    }
    final session = res.status == 200 ? _Session.fromAuth(res.body, _clock.nowUtc(), aiVersion) : null;
    if (session == null) throw PigTipsUnavailable('signup_${res.status}');
    await _store.write(sessionKey, jsonEncode(session.toJson()));
    await _store.delete(dayKey);
    _askingDay = null;
    _asking = null;
    _on.value = true;
  }

  @override
  Future<void> turnOff() async {
    _on.value = false;
    _askingDay = null;
    _asking = null;
    final session = await _readSession(sessionKey);
    await _store.delete(dayKey);
    if (session == null) return;
    await _recordConsents([
      ConsentItem(ConsentKind.ai, session.aiVersion, granted: false, locale: _language()),
    ]);
    // The id's reports, then its delete: kept until the server has them.
    await _store.write(forgetKey, jsonEncode(session.toJson()));
    await _store.delete(sessionKey);
    await resumePending();
  }

  @override
  Future<String?> eraseBegin() async {
    await turnOff();
    final forget = await _store.read(forgetKey);
    if (forget == null) return null;
    return jsonEncode({'forget': forget, 'reports': await _store.read(reportsKey)});
  }

  @override
  Future<void> eraseEnd(String? pending) async {
    final json = _decode(pending);
    if (json is! Map) return;
    final forget = json['forget'], reports = json['reports'];
    if (forget is! String) return;
    await _store.write(forgetKey, forget);
    if (reports is String) await _store.write(reportsKey, reports);
    unawaited(resumePending());
  }

  @override
  Future<TipOfDay> tipFor(String todayWire) {
    final asking = _asking;
    if (asking != null && _askingDay == todayWire) return asking;
    _askingDay = todayWire;
    return _asking = _tipFor(todayWire);
  }

  Future<TipOfDay> _tipFor(String todayWire) async {
    final day = parseWireDate(todayWire);
    final fallback = StaticTip(tipForDay(day ?? DateTime(2001)));
    try {
      if (day == null || !offered || !_on.value) return fallback;
      final answered = await _readDay(todayWire);
      if (answered != null) return answered.tip ?? fallback;
      // At most once a local day on this phone, whatever comes back and
      // whatever happened since (tips off and on again, a new id).
      if (await _store.read(askedKey) == todayWire) return fallback;
      await _store.write(askedKey, todayWire);
      await _writeDay(todayWire, null);
      final tip = await _ask(todayWire);
      if (tip == null) return fallback;
      await _writeDay(todayWire, tip);
      return tip;
    } on Object {
      return fallback;
    }
  }

  Future<WrittenTip?> _ask(String todayWire) async {
    final request = await _requestFor(todayWire);
    final res = await _call(sessionKey, '/functions/v1/pig-tip', jsonEncode(request.toJson()), tipTimeout);
    if (res == null || res.status != 200) return null;
    final json = _decode(res.body);
    if (json is! Map) return null;
    final text = json['tip'], sig = json['sig'], model = res.headers['x-tip-model'];
    if (text is! String || sig is! String || model == null) return null;
    if (!WrittenTip.usable(text, model, sig)) return null;
    return WrittenTip(day: todayWire, text: text, model: model, sig: sig);
  }

  @override
  Future<void> report(WrittenTip tip, TipReportReason reason) => _oneAtATime(() async {
    final item = {'tip': tip.text, 'reason': reason.name, 'model': tip.model, 'sig': tip.sig};
    try {
      await _setAside(tip);
      if (await _sendReport(sessionKey, item)) return;
      final queue = [...await _readQueue(), item];
      await _writeQueue(queue.length > maxQueuedReports ? queue.sublist(queue.length - maxQueuedReports) : queue);
    } on Object {
      // Never thrown at the person: the report screen says thanks either way.
    }
  });

  /// A reported tip: its day keeps no written tip any more, so the day's
  /// static tip shows for the rest of it, and that day is never asked again.
  Future<void> _setAside(WrittenTip tip) async {
    final answered = await _readDay(tip.day);
    if (answered?.tip == tip) await _writeDay(tip.day, null);
    if (_askingDay == tip.day) {
      _askingDay = null;
      _asking = null;
    }
  }

  /// True once the server has answered for good (kept, refused, or over the
  /// day's limits): never sent again. False: no answer, so later.
  Future<bool> _sendReport(String key, Map<String, String> item) async {
    try {
      final res = await _call(key, '/functions/v1/pig-tip/report', jsonEncode(item), shortTimeout);
      // No id left to send it with: nothing ever could.
      if (res == null) return true;
      return res.status < 500;
    } on Object {
      return false;
    }
  }

  /// The queued reports through [key]'s session; true when none is left.
  Future<bool> _sendQueued(String key) async {
    final queue = await _readQueue();
    if (queue.isEmpty) return true;
    final left = <Map<String, String>>[];
    for (final item in queue) {
      if (!await _sendReport(key, item)) left.add(item);
    }
    await _writeQueue(left);
    return left.isEmpty;
  }

  Future<void> _resumeForget() async {
    if (await _readSession(forgetKey) == null) return;
    if (!await _sendQueued(forgetKey)) return;
    final res = await _call(forgetKey, '/functions/v1/pig-tip/forget', null, shortTimeout);
    // Deleted, or gone already (no session left, or still refused).
    if (res == null || res.status == 204 || res.status == 401) {
      await _store.delete(forgetKey);
    }
  }

  /// [path] with [key]'s session: its token refreshed first when it has run
  /// out, and once more after a 401. Null when there's no session, or the
  /// server refused its refresh (the session is then gone). Throws with no
  /// answer.
  Future<TipsResponse?> _call(String key, String path, String? body, Duration timeout) async {
    var session = await _readSession(key);
    if (session == null) return null;
    if (!_clock.nowUtc().isBefore(session.expiresAt)) {
      session = await _refresh(key, session);
      if (session == null) return null;
    }
    var res = await _post(path, body, timeout, session.access);
    if (res.status == 401) {
      session = await _refresh(key, session);
      if (session == null) return null;
      res = await _post(path, body, timeout, session.access);
    }
    return res;
  }

  /// A new access token for [session]. Refused (4xx): the session is gone,
  /// and with it tips are off. Throws with no answer or a server error.
  Future<_Session?> _refresh(String key, _Session session) async {
    final res = await _auth('/auth/v1/token?grant_type=refresh_token', {'refresh_token': session.refresh});
    if (res.status == 200) {
      final fresh = _Session.fromAuth(res.body, _clock.nowUtc(), session.aiVersion);
      if (fresh != null) {
        await _store.write(key, jsonEncode(fresh.toJson()));
        return fresh;
      }
    }
    if (res.status >= 400 && res.status < 500) {
      await _store.delete(key);
      if (key == sessionKey) {
        await _store.delete(dayKey);
        _on.value = false;
      }
      return null;
    }
    throw PigTipsUnavailable('refresh_${res.status}');
  }

  Future<TipsResponse> _post(String path, String? body, Duration timeout, String access) {
    final endpoint = _endpoint!;
    return _http.post(
      endpoint.at(path),
      headers: {
        'apikey': endpoint.publishableKey,
        'Authorization': 'Bearer $access',
        if (endpoint.region.isNotEmpty) 'x-region': endpoint.region,
      },
      body: body,
      timeout: timeout,
    );
  }

  Future<TipsResponse> _auth(String path, Map<String, String> body) {
    final endpoint = _endpoint!;
    return _http.post(
      endpoint.at(path),
      headers: {'apikey': endpoint.publishableKey},
      body: jsonEncode(body),
      timeout: shortTimeout,
    );
  }

  Future<_Session?> _readSession(String key) async => _Session.fromJson(_decode(await _store.read(key)));

  Future<({WrittenTip? tip})?> _readDay(String todayWire) async {
    final json = _decode(await _store.read(dayKey));
    if (json is! Map || json['day'] != todayWire) return null;
    final tip = WrittenTip.fromJson(json['tip']);
    return (tip: tip != null && tip.day == todayWire ? tip : null);
  }

  Future<void> _writeDay(String todayWire, WrittenTip? tip) =>
      _store.write(dayKey, jsonEncode({'day': todayWire, 'tip': tip?.toJson()}));

  Future<List<Map<String, String>>> _readQueue() async {
    final json = _decode(await _store.read(reportsKey));
    if (json is! List) return [];
    return [
      for (final item in json)
        if (item is Map && item.values.every((v) => v is String))
          {for (final e in item.entries) '${e.key}': e.value as String},
    ];
  }

  Future<void> _writeQueue(List<Map<String, String>> queue) =>
      queue.isEmpty ? _store.delete(reportsKey) : _store.write(reportsKey, jsonEncode(queue));

  Future<T> _oneAtATime<T>(Future<T> Function() task) {
    final before = _tail;
    final run = before == null ? task() : before.then((_) => task());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }
}

Object? _decode(String? text) {
  if (text == null || text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// An anonymous session, as kept on the phone.
@immutable
class _Session {
  const _Session({
    required this.access,
    required this.refresh,
    required this.expiresAt,
    required this.aiVersion,
  });

  final String access;
  final String refresh;

  /// UTC, a minute before the token really runs out.
  final DateTime expiresAt;
  final String aiVersion;

  Map<String, String> toJson() => {
    'access': access,
    'refresh': refresh,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'ai_version': aiVersion,
  };

  static _Session? fromJson(Object? json) {
    if (json is! Map) return null;
    final access = json['access'], refresh = json['refresh'], expires = json['expires_at'];
    final version = json['ai_version'];
    if (access is! String || refresh is! String || expires is! String || version is! String) return null;
    final at = DateTime.tryParse(expires);
    if (access.isEmpty || refresh.isEmpty || at == null) return null;
    return _Session(access: access, refresh: refresh, expiresAt: at.toUtc(), aiVersion: version);
  }

  /// From an auth answer (sign-up or refresh): its tokens and lifetime.
  static _Session? fromAuth(String body, DateTime now, String aiVersion) {
    final json = _decode(body);
    if (json is! Map) return null;
    final access = json['access_token'], refresh = json['refresh_token'], expiresIn = json['expires_in'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty) return null;
    final seconds = expiresIn is int && expiresIn > 120 ? expiresIn : 3600;
    return _Session(
      access: access,
      refresh: refresh,
      expiresAt: now.toUtc().add(Duration(seconds: seconds - 60)),
      aiVersion: aiVersion,
    );
  }
}

/// For tests and fixtures: answers as set, sends nothing.
class FakePigTips implements PigTips {
  FakePigTips({this.offered = true, bool on = false, TipOfDay? tip, this.unavailable = false})
    : _on = ValueNotifier(on),
      tip = tip ?? const StaticTip(1);

  @override
  final bool offered;

  final ValueNotifier<bool> _on;

  /// What [tipFor] answers.
  TipOfDay tip;

  /// [turnOn] throws [PigTipsUnavailable].
  bool unavailable;

  /// What [turnOn] recorded, and what [report] sent.
  final consents = <String>[];
  final reports = <(WrittenTip, TipReportReason)>[];

  @override
  ValueListenable<bool> get on => _on;

  @override
  Future<void> turnOn({required String aiVersion, required String age18Version}) async {
    if (unavailable) throw const PigTipsUnavailable('fake');
    consents.addAll(['ai $aiVersion', 'age18 $age18Version']);
    _on.value = true;
  }

  @override
  Future<void> turnOff() async {
    _on.value = false;
  }

  @override
  Future<TipOfDay> tipFor(String todayWire) async => tip;

  @override
  Future<void> report(WrittenTip tip, TipReportReason reason) async {
    reports.add((tip, reason));
    // As the service: the reported tip gives way to its day's static tip.
    if (this.tip == tip) this.tip = StaticTip(tipForDay(parseWireDate(tip.day) ?? DateTime(2001)));
  }

  @override
  Future<String?> eraseBegin() async {
    _on.value = false;
    return null;
  }

  @override
  Future<void> eraseEnd(String? pending) async {}
}
