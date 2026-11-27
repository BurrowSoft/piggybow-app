import '../data/models.dart';
import '../l10n/gen/app_localizations.dart';

/// The words for a failure the app shows; anything unknown gets the generic
/// line.
String failureText(AppLocalizations l10n, Object error) => switch (error) {
  AppFailure(code: 'offline') => l10n.errOffline,
  _ => l10n.errGeneric,
};
