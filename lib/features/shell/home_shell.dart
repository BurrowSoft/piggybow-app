import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/launch_actions.dart';
import '../../core/services.dart';
import '../../journal/entry.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../router.dart';
import '../../session/app_session.dart' show Routes;
import '../add/entry_sheet.dart';
import '../reminder/reminder_scheduler.dart';
import 'even_tab_bar.dart';
import 'tab_top.dart';

/// Bottom tabs: Home · Timeline · Summary · Me.
/// A pushed screen that needs the whole height asks the shell to hide its
/// bottom bar. Back stays. The screen sets it back when it no longer needs
/// it, and on dispose.
final shellBarHidden = ValueNotifier<bool>(false);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _tabTop = {for (final tab in AppTab.values) tab: ValueNotifier(0)};

  ReminderScheduler? _reminders;
  LaunchActions? _launch;

  @override
  void initState() {
    super.initState();
    shellBarHidden.addListener(_barChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reminders = _reminders = context.services.reminders;
      reminders.tapPending.addListener(_reminderTapped);
      // A start from a reminder, waiting since before the tabs were up.
      _reminderTapped();
      final launch = _launch = context.services.launchActions;
      launch.addSpendPending.addListener(_addSpendAsked);
      // A start from the shortcut, the same way.
      _addSpendAsked();
    });
  }

  /// The home-screen shortcut, "Add a spend": Home, then the Add sheet on
  /// Spent, once per use, and none over a sheet already up. With the lock on,
  /// the lock screen covers it until the person unlocks.
  void _addSpendAsked() {
    final launch = _launch;
    if (!mounted || launch == null || !launch.takeAddSpend()) return;
    if (entrySheetOpen) return;
    GoRouter.of(context).go(Routes.home);
    // After the frame that shows Home, so the sheet opens over it.
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted && !entrySheetOpen) showEntrySheet(context, start: EntryType.spent);
    });
  }

  /// A reminder tapped: the Add sheet (plan §3.10), once per tap, so a
  /// shell built later (Delete everything, onboarding, then Home) never
  /// replays it; and none over a sheet already up. With the lock on, the
  /// lock screen covers it until the person unlocks.
  void _reminderTapped() {
    final reminders = _reminders;
    if (!mounted || reminders == null || !reminders.takeTap()) return;
    if (entrySheetOpen) return;
    showEntrySheet(context);
  }

  void _barChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    shellBarHidden.removeListener(_barChanged);
    _reminders?.tapPending.removeListener(_reminderTapped);
    _launch?.addSpendPending.removeListener(_addSpendAsked);
    for (final ping in _tabTop.values) {
      ping.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shell = widget.shell;
    return Scaffold(
      body: TabTopScope(pings: _tabTop, child: shell),
      // Always visible on the tabs and the screens pushed inside them;
      // hidden while the keyboard is up.
      bottomNavigationBar:
          MediaQuery.viewInsetsOf(context).bottom > 0 || shellBarHidden.value
          ? null
          : MediaQuery(
              // This context is outside the Scaffold, so its data still holds the
              // status-bar inset that the Scaffold removes for this slot: left
              // in, the bar grows by it and every tab ends short of the bar.
              data: MediaQuery.of(context).removePadding(removeTop: true),
              child: EvenTabBar(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: (index) {
                  final again = index == shell.currentIndex;
                  // A page open in the tab: this tap only goes back to the
                  // tab's page, which keeps its place.
                  final pagePushed =
                      shell.route.branches[index].navigatorKey.currentState
                          ?.canPop() ??
                      false;
                  shell.goBranch(
                    index,
                    // Tapping the current tab again returns to its first page,
                    initialLocation: again,
                  );
                  // and on that page, to its top.
                  if (again && !pagePushed) {
                    _tabTop[AppTab.values[index]]!.value++;
                  }
                },
                tabs: [
                  for (final tab in AppTab.values)
                    EvenTab(
                      id: tab.id,
                      icon: _icon(tab, selected: false),
                      selectedIcon: _icon(tab, selected: true),
                      label: tabLabel(l10n, tab),
                      semanticsLabel: tabLabel(l10n, tab),
                    ),
                ],
              ),
            ),
    );
  }

  static IconData _icon(AppTab tab, {required bool selected}) => switch (tab) {
    AppTab.home => selected ? Icons.home : Icons.home_outlined,
    AppTab.timeline =>
      selected ? Icons.view_timeline : Icons.view_timeline_outlined,
    AppTab.summary => selected ? Icons.insights : Icons.insights_outlined,
    AppTab.me => selected ? Icons.person : Icons.person_outline,
  };
}

/// A tab's name.
String tabLabel(AppLocalizations l10n, AppTab tab) => switch (tab) {
  AppTab.home => l10n.tabHome,
  AppTab.timeline => l10n.tabTimeline,
  AppTab.summary => l10n.tabSummary,
  AppTab.me => l10n.tabMe,
};
