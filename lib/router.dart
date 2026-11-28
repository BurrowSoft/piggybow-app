import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/categories/categories_screen.dart';
import 'features/categories/category_edit_screen.dart';
import 'features/goal/goal_screens.dart';
import 'features/home/home_screen.dart';
import 'features/me/me_screen.dart';
import 'features/me/reached_goals_screen.dart';
import 'features/onboarding/onboarding_screens.dart';
import 'features/plus/plus_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/start/start_screen.dart';
import 'features/summary/summary_screen.dart';
import 'features/timeline/timeline_screen.dart';
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

/// Me's pages, inside the Me tab (plan §3.8).
abstract final class MeRoutes {
  static const happy = '/me/happy';

  /// Remove plan with only the plan picked: the picker, the plan unpicked.
  static const removePlan = '/me/remove-plan';
  static const lock = '/me/lock';
  static const privacy = '/me/privacy';

  /// Reached goals, and one of them (read-only).
  static const reached = '/me/reached';
  static String reachedGoal(String id) => '/me/reached/$id';

  /// Categories: what the Add sheet offers.
  static const categories = '/me/categories';
}

/// A category of your own, made or edited (Plus), over everything: the Add
/// sheet, itself over the tabs, opens it too. The id is encoded ("c:…"),
/// and go_router decodes it.
abstract final class CategoryRoutes {
  static const create = '/category/new';
  static String edit(String id) => '/category/${Uri.encodeComponent(id)}';

  static bool contains(String location) => location.startsWith('/category/');
}

/// The goal screens, over the tabs (they belong to Home).
abstract final class GoalRoutes {
  static const create = '/home/goal/new';
  static String detail(String id) => '/home/goal/$id';
  static String edit(String id) => '/home/goal/$id/edit';
  static String done(String id) => '/home/goal/$id/done';
}

/// Piggybow Plus's paywall, over whichever tab opened it (only in builds
/// with Plus: services.plus).
abstract final class PlusRoutes {
  static const paywall = '/plus';
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
          location == PlusRoutes.paywall ||
          CategoryRoutes.contains(location) ||
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
      GoRoute(
        path: PlusRoutes.paywall,
        builder: (context, state) =>
            const ScaffoldMessenger(child: PlusScreen()),
      ),
      GoRoute(
        path: CategoryRoutes.create,
        builder: (context, state) =>
            const ScaffoldMessenger(child: CategoryEditScreen()),
      ),
      GoRoute(
        path: '/category/:id',
        builder: (context, state) => ScaffoldMessenger(
          child: CategoryEditScreen(categoryId: state.pathParameters['id']),
        ),
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
                      AppTab.summary => const SummaryScreen(),
                      AppTab.me => const MeScreen(),
                    },
                  ),
                  routes: [
                    if (tab == AppTab.me) ...[
                      GoRoute(
                        path: 'happy',
                        builder: (context, state) =>
                            const HappyScreen(inMe: true),
                      ),
                      GoRoute(
                        path: 'remove-plan',
                        builder: (context, state) =>
                            const HappyScreen(inMe: true, removingPlan: true),
                      ),
                      GoRoute(
                        path: 'lock',
                        builder: (context, state) => const MeLockPage(),
                      ),
                      GoRoute(
                        path: 'privacy',
                        builder: (context, state) => const PrivacyScreen(),
                      ),
                      GoRoute(
                        path: 'categories',
                        // Its own messenger: "Keep at least one category
                        // showing" shows on this page.
                        builder: (context, state) =>
                            const ScaffoldMessenger(child: CategoriesScreen()),
                      ),
                      GoRoute(
                        path: 'reached',
                        builder: (context, state) => const ReachedGoalsScreen(),
                        routes: [
                          // A reached goal is read-only (R1), in the Me tab.
                          GoRoute(
                            path: ':id',
                            builder: (context, state) => GoalDetailScreen(
                              goalId: state.pathParameters['id']!,
                            ),
                          ),
                        ],
                      ),
                    ],
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
