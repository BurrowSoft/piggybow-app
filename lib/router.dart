import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/semantics_id.dart';
import 'features/goal/goal_screens.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screens.dart';
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

/// Onboarding (plan §3.1), on the first open only: O1 Welcome, O2 "What
/// makes your pig happy?" and O3, the optional first goal.
abstract final class OnboardingRoutes {
  static const welcome = '/onboarding';
  static const happy = '/onboarding/happy';
  static const goal = '/onboarding/goal';

  static bool contains(String location) =>
      location == welcome || location.startsWith('$welcome/');
}

/// Where [location] leads while onboarding is [done] or not: everywhere
/// leads to it until it is, and nowhere leads back to it after.
String onboardingGate(String location, {required bool done}) {
  final inOnboarding = OnboardingRoutes.contains(location);
  if (!done && !inOnboarding) return OnboardingRoutes.welcome;
  if (done && inOnboarding) return Routes.home;
  return location;
}

/// The goal screens, over the tabs (they belong to Home).
abstract final class GoalRoutes {
  static const create = '/home/goal/new';
  static String detail(String id) => '/home/goal/$id';
  static String edit(String id) => '/home/goal/$id/edit';
  static String done(String id) => '/home/goal/$id/done';
}

GoRouter buildRouter({
  required AppSession session,
  String initialLocation = Routes.home,
  List<NavigatorObserver> observers = const [],
  ValueListenable<bool>? onboarded,
}) {
  final done = onboarded ?? ValueNotifier(true);
  GoRoute page(String path, Widget child) => GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        NoTransitionPage(key: state.pageKey, child: child),
  );

  final root = GlobalKey<NavigatorState>();
  GoRoute over(
    String path,
    Widget Function(GoRouterState) build, {
    List<GoRoute> routes = const [],
  }) => GoRoute(
    path: path,
    parentNavigatorKey: root,
    // Its own messenger: a SnackBar shown here ("Added") stays here, and
    // never lingers on the tabs' shell over Home's +.
    builder: (context, state) => ScaffoldMessenger(child: build(state)),
    routes: routes,
  );

  return GoRouter(
    navigatorKey: root,
    initialLocation: initialLocation,
    observers: observers,
    refreshListenable: Listenable.merge([session, done]),
    // A location no route matches never shows go_router's debug page: Home,
    // where the usual rules apply.
    onException: (context, state, router) => router.go(Routes.home),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final known =
          AppTab.values.any((t) => t.matches(location)) ||
          location == Routes.start ||
          OnboardingRoutes.contains(location);
      // Anything unknown is treated as Home; never a raw "not found" page.
      final target = known ? location : Routes.home;
      final next = session.redirect(target) ?? target;
      // While the start screen restores, it stays; then onboarding until
      // it is done (plan §3.1).
      final gated = next == Routes.start
          ? next
          : onboardingGate(next, done: done.value);
      return gated == location ? null : gated;
    },
    routes: [
      page(Routes.start, const StartScreen()),
      GoRoute(
        path: OnboardingRoutes.welcome,
        builder: (context, state) =>
            const ScaffoldMessenger(child: WelcomeScreen()),
        routes: [
          GoRoute(
            path: 'happy',
            builder: (context, state) =>
                const ScaffoldMessenger(child: HappyScreen()),
          ),
          GoRoute(
            path: 'goal',
            builder: (context, state) => const ScaffoldMessenger(
              child: GoalEditScreen(onboarding: true),
            ),
          ),
        ],
      ),
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
                      AppTab.home => const HomeScreen(),
                      AppTab.timeline => const TimelineScreen(),
                      _ => PlaceholderTab(tab: tab),
                    },
                  ),
                  routes: [
                    if (tab == AppTab.home) ...[
                      over('goal/new', (_) => const GoalEditScreen()),
                      over(
                        'goal/:id',
                        (s) =>
                            GoalDetailScreen(goalId: s.pathParameters['id']!),
                        routes: [
                          over(
                            'edit',
                            (s) =>
                                GoalEditScreen(goalId: s.pathParameters['id']),
                          ),
                          over(
                            'done',
                            (s) =>
                                GoalDoneScreen(goalId: s.pathParameters['id']!),
                          ),
                        ],
                      ),
                    ],
                  ],
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
