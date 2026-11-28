import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/clock.dart';
import 'plus_store.dart';

/// How long the launch hint keeps Plus on without the store's word.
const plusHintMaxAge = Duration(days: 3);

/// Whether a launch hint that lasts until [until] still grants Plus at
/// [now]: before its end, and never further ahead than [plusHintMaxAge]
/// (the app never writes one further out).
bool plusHintGrants(DateTime? until, DateTime now) =>
    until != null && until.isAfter(now) && !until.isAfter(now.add(plusHintMaxAge));

/// The launch hint: when Plus was last seen on, how long it may still be
/// shown before the store answers again. Only ever a hint: the store's
/// answer replaces it at every launch and resume.
abstract interface class PlusHint {
  Future<DateTime?> read();
  Future<void> write(DateTime until);
  Future<void> clear();
}

/// The hint as one small file in the app's cache folder. No backup carries
/// it (Android's backup rules include only the journal and the settings;
/// the iPhone never backs up Caches), so it never reaches another phone,
/// and Delete everything erases it.
class FilePlusHint implements PlusHint {
  FilePlusHint({this.folder = getTemporaryDirectory});

  /// Where the file lives: the app's cache (path_provider).
  final Future<Directory> Function() folder;

  static const fileName = 'plus_hint.json';

  Future<File> _file() async => File('${(await folder()).path}/$fileName');

  @override
  Future<DateTime?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      final until = json is Map ? json['until'] : null;
      return until is String ? DateTime.tryParse(until)?.toUtc() : null;
    } on Object {
      // Unreadable is the same as none.
      return null;
    }
  }

  @override
  Future<void> write(DateTime until) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode({'until': until.toUtc().toIso8601String()}),
      flush: true,
    );
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

/// The hint in memory, for tests.
class MemoryPlusHint implements PlusHint {
  MemoryPlusHint([this.until]);

  DateTime? until;

  @override
  Future<DateTime?> read() async => until;

  @override
  Future<void> write(DateTime until) async => this.until = until;

  @override
  Future<void> clear() async => until = null;
}

/// A line the paywall shows after a purchase or a restore; none while
/// there's nothing to say (a closed purchase sheet says nothing either).
enum PlusNote { none, pending, notThrough, unavailable, restored, nothingToRestore }

/// Whether Plus is on, and the purchase flows (decision 79): what every
/// Plus surface reads. The store's answer is the truth, read at launch and
/// on every resume. Until it answers, or while it can't (no store on the
/// phone, the store app not answering), the launch hint stands until its
/// end, and only the store's own "owned" ever writes a new one. The store's
/// "not owned" ends Plus and erases the hint. Every purchase the store
/// reports is finished at once.
class PlusEntitlement extends ChangeNotifier {
  PlusEntitlement({required this.store, required this.hint, required this.clock});

  final PlusStore store;
  final PlusHint hint;
  final Clock clock;

  /// The store this phone buys from.
  PlusSource get source => store.source;

  /// Plus is on: the store's latest answer, or before it has answered the
  /// launch hint.
  bool get active => _owned ?? _hinted;

  /// The store's latest answer (null: none yet since launch).
  bool? _owned;

  /// The launch hint grants Plus now.
  bool _hinted = false;

  /// The plans as the store offers them (null: not asked yet; empty:
  /// purchases unavailable here).
  List<PlusPlan>? get plans => _plans;
  List<PlusPlan>? _plans;

  /// A purchase or a restore is running.
  bool get busy => _busy;
  bool _busy = false;

  PlusNote get note => _note;
  PlusNote _note = PlusNote.none;

  bool _started = false;
  bool _disposed = false;

  /// At launch: the hint first (no free look before the store answers),
  /// then the store.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    store.changes.addListener(_onStoreChange);
    _hinted = plusHintGrants(await _readHint(), clock.nowUtc());
    _notify();
    await refresh();
  }

  /// At launch and on every resume: the store's answer, whatever it is.
  Future<void> refresh() async {
    if (await _ask() == null) await _rereadHint();
    _notify();
  }

  /// The plans, for the paywall.
  Future<void> loadPlans() async {
    List<PlusPlan> plans;
    try {
      plans = await store.plans();
    } on Object {
      plans = const [];
    }
    _plans = plans;
    _notify();
  }

  Future<void> buy(PlusPlan plan) async {
    if (_busy) return;
    _busy = true;
    _note = PlusNote.none;
    _notify();
    PlusBuyOutcome outcome;
    try {
      outcome = await store.buy(plan);
    } on Object {
      outcome = const PlusBuyFailed();
    }
    switch (outcome) {
      case PlusBought(:final proof):
        await _finish(proof);
        await _set(true);
      case PlusPending():
        _note = PlusNote.pending;
      case PlusCancelled():
        _note = PlusNote.none;
      case PlusBuyFailed():
        _note = PlusNote.notThrough;
    }
    _busy = false;
    _notify();
  }

  /// Restore purchases: the store's answer again, said on the paywall.
  Future<void> restore() async {
    if (_busy) return;
    _busy = true;
    _note = PlusNote.none;
    _notify();
    final found = await _ask();
    if (found == null) await _rereadHint();
    _note = found == null
        ? PlusNote.unavailable
        : found.isEmpty
        ? PlusNote.nothingToRestore
        : PlusNote.restored;
    _busy = false;
    _notify();
  }

  /// The store's own subscription page. Whatever the person does there,
  /// the next refresh reads it.
  Future<void> manage() async {
    try {
      await store.manageSubscriptions();
    } on Object {
      // Nothing opened; nothing changed.
    }
  }

  /// Delete everything: the hint goes with the app's data. The store's own
  /// record stays (erasing the app never cancels a subscription), so the
  /// next answer still counts.
  Future<void> forget() async {
    _hinted = false;
    await hint.clear();
    _notify();
  }

  /// The store's answer: finishes what still waits, then sets Plus and the
  /// hint. null: the store couldn't say.
  Future<List<PlusProof>?> _ask() async {
    List<PlusProof>? found;
    try {
      found = await store.owned();
    } on Object {
      found = null;
    }
    if (found == null) return null;
    for (final proof in found) {
      if (proof.needsFinish) await _finish(proof);
    }
    await _set(found.isNotEmpty);
    return found;
  }

  /// The store said on or off: the hint follows (written only from an
  /// "owned", erased by a "not owned").
  Future<void> _set(bool on) async {
    _owned = on;
    _hinted = on;
    try {
      if (on) {
        await hint.write(clock.nowUtc().add(plusHintMaxAge));
      } else {
        await hint.clear();
      }
    } on Object {
      // Only a hint: the next answer writes it again.
    }
  }

  /// The store couldn't say: the hint stands until its own end, never
  /// longer.
  Future<void> _rereadHint() async {
    _hinted = plusHintGrants(await _readHint(), clock.nowUtc());
  }

  Future<DateTime?> _readHint() async {
    try {
      return await hint.read();
    } on Object {
      return null;
    }
  }

  /// Finishing can fail (the store app not answering): the store reports
  /// the purchase again, and the next answer finishes it.
  Future<void> _finish(PlusProof proof) async {
    try {
      await store.finish(proof);
    } on Object {
      // Tried again on the next answer.
    }
  }

  /// A purchase the store reported with nobody waiting (a pending payment
  /// approved, a renewal, one left unfinished): finished, then the store's
  /// answer.
  void _onStoreChange() => unawaited(_claim());

  Future<void> _claim() async {
    final proofs = store.takeUnclaimed();
    if (proofs.isEmpty) return;
    for (final proof in proofs) {
      await _finish(proof);
    }
    if (_note == PlusNote.pending) _note = PlusNote.none;
    await refresh();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    store.changes.removeListener(_onStoreChange);
    super.dispose();
  }
}
