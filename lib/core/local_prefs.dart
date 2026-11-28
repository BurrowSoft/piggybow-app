import 'package:shared_preferences/shared_preferences.dart';

/// Settings kept on this phone (language, appearance, the device account).
/// Nothing here ever leaves the phone.
abstract interface class LocalPrefs {
  String? get localeCode;
  Future<void> setLocaleCode(String code);

  bool get welcomeSeen;
  Future<void> setWelcomeSeen();

  /// An account was signed in on this phone and not deleted: a signed-out
  /// phone with one opens on Sign in. Whether, never which. (The session's
  /// account flow; v0.1 never signs out.)
  bool get accountOnDevice;
  Future<void> setAccountOnDevice(bool value);

  /// This phone's no-email session ended and nothing has replaced it. A
  /// plain flag, never which account. (The session's account flow.)
  bool get sessionEndedNoEmail;
  Future<void> setSessionEndedNoEmail(bool value);

  /// Me → Appearance: system | light | dark, on this device only. Null = system.
  String? get appearance;
  Future<void> setAppearance(String value);

  /// Delete everything (plan §3.8): every pref Piggybow keeps, the device
  /// account included.
  Future<void> clear();

  /// The Plus theme chosen in Me → Theme, by name (palettes.dart), on this
  /// device only; null: Strawberry, the default.
  String? get palette;
  Future<void> setPalette(String? value);

  /// The device account (DeviceBackend) as JSON: its id and settings. Null
  /// before the first start, and after Delete.
  /// The pig's name (feature 1), this device only; null: none. Not journal
  /// data: never in the export. Delete everything clears it with the rest.
  String? get pigName;
  Future<void> setPigName(String? value);

  String? get deviceAccount;
  Future<void> setDeviceAccount(String? json);

  /// Summary's Plus teaser for Patterns (feature 20) was hidden with "Hide":
  /// for good, on this device only.
  bool get patternsTeaserHidden;
  Future<void> hidePatternsTeaser();
}

class SharedLocalPrefs implements LocalPrefs {
  @override
  Future<void> clear() => _prefs.clear();
  SharedLocalPrefs._(this._prefs);

  static Future<SharedLocalPrefs> load() async =>
      SharedLocalPrefs._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _localeKey = 'device.locale';
  static const _welcomeKey = 'device.welcome_seen';
  static const _appearanceKey = 'device.appearance';
  static const _paletteKey = 'device.palette';
  static const _pigNameKey = 'device.pig_name';
  static const _accountKey = 'device.account_on_device';
  static const _sessionEndedNoEmailKey = 'device.session_ended_no_email';
  static const _deviceAccountKey = 'device.account';
  static const _patternsTeaserKey = 'device.patterns_teaser_hidden';

  @override
  bool get patternsTeaserHidden => _prefs.getBool(_patternsTeaserKey) ?? false;

  @override
  Future<void> hidePatternsTeaser() => _prefs.setBool(_patternsTeaserKey, true);

  @override
  bool get accountOnDevice => _prefs.getBool(_accountKey) ?? false;

  @override
  Future<void> setAccountOnDevice(bool value) =>
      _prefs.setBool(_accountKey, value);

  @override
  bool get sessionEndedNoEmail =>
      _prefs.getBool(_sessionEndedNoEmailKey) ?? false;

  @override
  Future<void> setSessionEndedNoEmail(bool value) =>
      _prefs.setBool(_sessionEndedNoEmailKey, value);

  @override
  String? get localeCode => _prefs.getString(_localeKey);

  @override
  Future<void> setLocaleCode(String code) => _prefs.setString(_localeKey, code);

  @override
  bool get welcomeSeen => _prefs.getBool(_welcomeKey) ?? false;

  @override
  Future<void> setWelcomeSeen() => _prefs.setBool(_welcomeKey, true);

  @override
  String? get appearance => _prefs.getString(_appearanceKey);

  @override
  Future<void> setAppearance(String value) =>
      _prefs.setString(_appearanceKey, value);

  @override
  String? get palette => _prefs.getString(_paletteKey);

  @override
  Future<void> setPalette(String? value) => value == null
      ? _prefs.remove(_paletteKey)
      : _prefs.setString(_paletteKey, value);

  @override
  String? get pigName => _prefs.getString(_pigNameKey);

  @override
  Future<void> setPigName(String? value) => value == null
      ? _prefs.remove(_pigNameKey)
      : _prefs.setString(_pigNameKey, value);

  @override
  String? get deviceAccount => _prefs.getString(_deviceAccountKey);

  @override
  Future<void> setDeviceAccount(String? json) => json == null
      ? _prefs.remove(_deviceAccountKey)
      : _prefs.setString(_deviceAccountKey, json);
}

class MemoryLocalPrefs implements LocalPrefs {
  @override
  Future<void> clear() async {
    localeCode = null;
    welcomeSeen = false;
    accountOnDevice = false;
    sessionEndedNoEmail = false;
    appearance = null;
    palette = null;
    pigName = null;
    deviceAccount = null;
    patternsTeaserHidden = false;
  }
  MemoryLocalPrefs({
    this.localeCode,
    this.welcomeSeen = false,
    this.accountOnDevice = false,
    this.deviceAccount,
  });

  @override
  bool accountOnDevice;

  @override
  Future<void> setAccountOnDevice(bool value) async => accountOnDevice = value;

  @override
  bool sessionEndedNoEmail = false;

  @override
  Future<void> setSessionEndedNoEmail(bool value) async =>
      sessionEndedNoEmail = value;

  @override
  String? appearance;

  @override
  Future<void> setAppearance(String value) async => appearance = value;

  @override
  String? palette;

  @override
  Future<void> setPalette(String? value) async => palette = value;

  @override
  String? pigName;

  @override
  Future<void> setPigName(String? value) async => pigName = value;

  @override
  String? deviceAccount;

  @override
  Future<void> setDeviceAccount(String? json) async => deviceAccount = json;

  @override
  String? localeCode;

  @override
  bool welcomeSeen;

  @override
  Future<void> setLocaleCode(String code) async => localeCode = code;

  @override
  Future<void> setWelcomeSeen() async => welcomeSeen = true;

  @override
  bool patternsTeaserHidden = false;

  @override
  Future<void> hidePatternsTeaser() async => patternsTeaserHidden = true;
}
