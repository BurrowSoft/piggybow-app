import 'package:flutter/material.dart';

import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/theme.dart';

/// Shown instead of the app when the journal on the phone was written by a
/// newer Piggybow, in a later format (JournalTooNew): it's never opened, so
/// never half-read, and nothing of it shows. The person updates the app.
class JournalTooNewApp extends StatelessWidget {
  const JournalTooNewApp({super.key, this.locale, this.themeMode = ThemeMode.system});

  /// The person's language, as the app would use it.
  final Locale? locale;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appName,
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: themeMode,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TestId.container(
                'journal-too-new',
                child: Text(
                  AppLocalizations.of(context).journalTooNew,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
