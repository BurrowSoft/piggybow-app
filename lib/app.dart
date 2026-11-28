import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/app_config.dart';
import 'core/services.dart';
import 'core/system_bars.dart';
import 'features/lock/lock_screen.dart';
import 'features/reminder/reminder_sync.dart';
import 'l10n/gen/app_localizations.dart';
import 'session/app_session.dart';
import 'session/session_scope.dart';
import 'theme/theme.dart';

class PiggybowApp extends StatelessWidget {
  const PiggybowApp({
    super.key,
    required this.config,
    required this.session,
    required this.router,
    required this.services,
  });

  final AppConfig config;
  final AppSession session;
  final GoRouter router;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ConfigScope(
      config: config,
      child: ServicesScope(
        services: services,
        child: SessionScope(
          session: session,
          child: ReminderSync(
            session: session,
            services: services,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => MaterialApp.router(
                onGenerateTitle: (context) =>
                    AppLocalizations.of(context).appName,
                debugShowCheckedModeBanner: false,
                scrollBehavior: const AppScrollBehavior(),
                theme: buildTheme(
                  Brightness.light,
                  disableAnimations: config.disableAnimations,
                  plusPalette: session.palette,
                ),
                darkTheme: buildTheme(
                  Brightness.dark,
                  disableAnimations: config.disableAnimations,
                  plusPalette: session.palette,
                ),
                // The user's choice, else the device language if shipped,
                // else English (v0.1 ships English only).
                locale: session.locale,
                // Me → Appearance, this device only.
                themeMode: session.themeMode,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                routerConfig: router,
                // See-through status and navigation bars over every page (the
                // lock screen too); the lock screen and the app-switcher cover.
                builder: (context, child) => PageSystemBars(
                  child: LockGate(
                    lock: services.appLock,
                    session: session,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
