import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../router.dart';

/// "Tap the tab you're on to jump back to its top." (Help, Getting
/// started): the home shell pings the tab tapped again; its first page
/// scrolls to the top ([ScrollsToTopOnTabTap]).
class TabTopScope extends InheritedWidget {
  const TabTopScope({super.key, required this.pings, required super.child});

  /// One counter per tab, bumped on each tap of the tab you're on.
  final Map<AppTab, ValueNotifier<int>> pings;

  static ValueListenable<int>? of(BuildContext context, AppTab tab) =>
      context.dependOnInheritedWidgetOfExactType<TabTopScope>()?.pings[tab];

  @override
  bool updateShouldNotify(TabTopScope oldWidget) => pings != oldWidget.pings;
}

/// A tab's first page: scrolls to the top when [tab] is tapped while it's
/// the current tab. The list is [tabTopController], or else the route's
/// primary scroll controller (the one a vertical list without its own uses).
mixin ScrollsToTopOnTabTap<T extends StatefulWidget> on State<T> {
  AppTab get tab;

  ScrollController? get tabTopController => null;

  ValueListenable<int>? _tabPing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ping = TabTopScope.of(context, tab);
    if (ping == _tabPing) return;
    _tabPing?.removeListener(_toTop);
    _tabPing = ping?..addListener(_toTop);
  }

  @override
  void dispose() {
    _tabPing?.removeListener(_toTop);
    super.dispose();
  }

  void _toTop() {
    if (!mounted) return;
    final c = tabTopController ?? PrimaryScrollController.maybeOf(context);
    // Two lists on one controller (e.g. search open over the calendar):
    // nothing says which one, so neither moves.
    if (c == null || !c.hasClients || c.positions.length != 1) return;
    if (c.offset <= 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      c.jumpTo(0);
    } else {
      unawaited(
        c.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }
}
