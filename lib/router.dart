import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/semantics_id.dart';
import 'features/shell/home_shell.dart';
import 'features/start/start_screen.dart';
import 'features/timeline/timeline_screen.dart';
import 'l10n/gen/app_localizations.dart';
import 'session/app_session.dart';

/// The four tabs, in bottom-bar order. [id] is the Semantics id stem
/// (`tab-<id>`, `<id>-screen`) and never changes with the language.
enum AppTab {
  home('/home'),
  timeline('/timeline'),
  summary('/summary'),
  me('/me');

  const AppTab(this.path);
  final String path;

  String get id => name;

  bool matches(String location) =>
      location == path || location.startsWith('$path/');

  /// The tab a location belongs to (Home when none does: a deep link).
  static AppTab of(String location) => AppTab.values.firstWhere(
    (t) => t.matches(location),
    orElse: () => AppTab.home,
  );
}

GoRouter buildRouter({
  required AppSession session,
  String initialLocation = Routes.home,
  List<NavigatorObserver> observers = const [],
}) {
  GoRoute page(String path, Widget child) => GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        NoTransitionPage(key: state.pageKey, child: child),
  );

  return GoRouter(
    initialLocation: initialLocation,
    observers: observers,
    refreshListenable: session,
    // A location no route matches never shows go_router's debug page: Home,
    // where the usual rules apply.
    onException: (context, state, router) => router.go(Routes.home),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final known =
          AppTab.values.any((t) => t.matches(location)) ||
          location == Routes.start;
      // Anything unknown is treated as Home; never a raw "not found" page.
      final target = known ? location : Routes.home;
      if (target != location) return session.redirect(target) ?? target;
      return session.redirect(target);
    },
    routes: [
      page(Routes.start, const StartScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          for (final tab in AppTab.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: tab.path,
                  name: tab.name,
                  // Each tab shows its SnackBars on its own Scaffold, so
                  // the tab's + rides above them instead of under them.
                  builder: (context, state) => ScaffoldMessenger(
                    child: switch (tab) {
                      AppTab.timeline => const TimelineScreen(),
                      _ => PlaceholderTab(tab: tab),
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// A tab's page until its screen lands (the weekend plan's P7, P8 and P9):
/// the tab's name as its title, and nothing else.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final title = tabLabel(AppLocalizations.of(context), tab);
    return TestId.container(
      '${tab.id}-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const SizedBox.expand(),
      ),
    );
  }
}
