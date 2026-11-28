import '../data/models.dart';

/// Legal versions. v0.1 has no consent screen and shows no version anywhere
/// (the legal texts aren't live yet), so privacy and terms are empty and none
/// is required. When a consent screen comes back, each version must match its
/// published text's. The page links are build defines (AppConfig.privacyUrl,
/// AppConfig.supportUrl), empty until each page is live.
abstract final class PolicyVersions {
  static const privacy = '';
  static const terms = '';

  /// The pig tips consent sheet's AI text and its 18+ line, recorded at its
  /// Yes (the only place either is asked today). Set once their words are
  /// final, and bumped whenever they change, so a record always names what
  /// was agreed. Empty until then: a debug build that offers tips records
  /// an empty version.
  static const ai = '';
  static const age18 = '';

  /// Pig tips' texts are final: the consent sheet's AI text and its 18+ line
  /// have their versions. Until then, no release build offers tips
  /// (AppConfig.aiTipsEnabled), whatever its env file says.
  static const aiTextsFinal = ai != '' && age18 != '';

  /// Needed before anything is stored: none in v0.1.
  static const Map<ConsentKind, String> required = {};
}
