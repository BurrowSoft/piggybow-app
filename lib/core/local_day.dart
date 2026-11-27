import 'package:flutter/foundation.dart';

import 'clock.dart';
import 'device.dart';

/// "Today" on this phone: the phone's live time zone, read at start and on
/// every resume, so a trip or a midnight never leaves the wrong day. Never a
/// stored zone, and never UTC.
class LocalDay extends ChangeNotifier {
  LocalDay({required this._clock, required this._device});

  final Clock _clock;
  final DeviceContext _device;
  String _zone = 'UTC';

  /// The IANA zone last read from the phone.
  String get zone => _zone;

  /// Reads the phone's zone again; listeners hear when it changed.
  Future<void> refresh() async {
    final zone = await _device.timeZone();
    if (zone == _zone) return;
    _zone = zone;
    notifyListeners();
  }

  /// Today's date (midnight, no zone).
  DateTime get today => _clock.todayIn(_zone);

  /// Today as stored (`YYYY-MM-DD`).
  String get todayWire => wireDate(today);
}
