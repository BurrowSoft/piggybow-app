import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/app_config.dart';
import 'core/services.dart';
import 'core/system_bars.dart';
import 'features/lock/lock_screen.dart';
import 'features/reminder/reminder_sync.dart';
import 'features/widget/widget_sync.dart';
import 'l10n/gen/app_localizations.dart';
import 'session/app_session.dart';
import 'session/session_scope.dart';
import 'theme/palettes.dart';
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
              // Plus too: a theme shows only while Plus is active.
              listenable: Listenable.merge([
                session,
                if (services.plus != null) services.plus!,
              ]),
              builder: (context, _) => MaterialApp.router(
                onGenerateTitle: (context) =>
                    AppLocalizations.of(context).appName,
                debugShowCheckedModeBanner: false,
                scrollBehavior: const AppScrollBehavior(),
                theme: buildTheme(
                  Brightness.light,
                  disableAnimations: config.disableAnimations,
                  plusPalette: _palette,
                ),
                darkTheme: buildTheme(
                  Brightness.dark,
                  disableAnimations: config.disableAnimations,
                  plusPalette: _palette,
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
                // The home-screen widget kept in step, in builds with Plus.
                builder: (context, child) => WidgetSync(
                  enabled: config.plusEnabled,
                  session: session,
                  services: services,
                  plusActive: const _NoPlus(),
                  child: PageSystemBars(
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
      ),
    );
  }

  /// Me → Theme's choice while Plus is active (the live entitlement, never
  /// the stored choice alone); Strawberry otherwise, and in a build without
  /// Plus.
  PlusPalette? get _palette => appliedPalette(
    session.chosenPalette,
    plusActive: services.plus?.active ?? false,
  );
}

/// Plus can't be active in this version: no entitlement exists yet. The
/// Plus entitlement PR (#45) brings one, and is wired in here when the two
/// meet.
class _NoPlus implements ValueListenable<bool> {
  const _NoPlus();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
