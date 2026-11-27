import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../core/semantics_id.dart';

/// One tab of [EvenTabBar].
@immutable
class EvenTab {
  const EvenTab({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.semanticsLabel,
  });

  /// The tab's TestId (`tab-<id>`).
  final String id;
  final IconData icon;
  final IconData selectedIcon;

  /// What the tab shows under its icon.
  final String label;

  /// What a screen reader says (the label without "&", 27 Nov: "AI and
  /// Insights").
  final String semanticsLabel;
}

/// Where each tab goes (27 Nov, the owner via UX: the tabs evenly spaced). The
/// labels are laid out space-evenly: the left margin, each gap between two
/// labels and the right margin are the same [gap]. Each tab's tap area runs
/// from the middle of the gap on its left to the middle of the gap on its
/// right (the outer ones to the screen's edge), so the areas tile the bar
/// with no hole and no overlap.
///
/// Every indicator ([pillWidth], centred on its label) stays on the bar and
/// clear of its neighbours' (the Reviewer, 27 Nov), and no space is under
/// [minGap]. Where equal spaces can't keep that (two short labels side by side
/// on a narrow screen), only the spaces that must widen do, to just what they
/// need, and the others share the rest equally ([even] is then false).
@immutable
class EvenTabLayout {
  const EvenTabLayout._(this.gap, this.gaps, this.centers, this.edges);

  /// The spaces' common width: every margin and gap, except a widened one.
  final double gap;

  /// The n + 1 spaces, left to right: the left margin, the gaps between the
  /// labels, the right margin.
  final List<double> gaps;

  /// Each label's centre, from the bar's left.
  final List<double> centers;

  /// The tap areas' edges, left to right: n + 1 values, 0 … width.
  final List<double> edges;

  double hitWidth(int i) => edges[i + 1] - edges[i];

  /// Whether every space is the same (none widened).
  bool get even => gaps.every((g) => g - gap < 1e-6);

  /// The layout for these label widths in [width], or null when it can't keep
  /// every tap area at least [minHit] wide, every indicator ([pillWidth],
  /// centred on its label) on the bar, no two indicators overlapping, and
  /// every space at least [minGap] (labels never closer than that, nor to the
  /// screen's edges).
  static EvenTabLayout? compute(
    double width,
    List<double> labelWidths, {
    double minHit = kMinInteractiveDimension,
    double pillWidth = 64,
    double minGap = 12,
  }) {
    final n = labelWidths.length;
    if (n == 0) return null;
    final total = labelWidths.fold<double>(0, (a, w) => a + w);
    final room = width - total;
    if (room <= 0) return null;
    // The least each space can be: [minGap]; more where a margin keeps its
    // indicator on the bar, or a gap keeps two neighbouring indicators apart.
    final least = [
      for (var k = 0; k <= n; k++)
        if (k == 0)
          pillWidth / 2 - labelWidths.first / 2
        else if (k == n)
          pillWidth / 2 - labelWidths.last / 2
        else
          pillWidth - (labelWidths[k - 1] + labelWidths[k]) / 2,
    ].map((m) => m < minGap ? minGap : m).toList();
    if (least.fold<double>(0, (a, m) => a + m) > room + 1e-9) return null;
    // Equal spaces, except those that need more: each widened to its least,
    // the others sharing what is left.
    final widened = List.filled(n + 1, false);
    double gap;
    while (true) {
      var left = room;
      var free = 0;
      for (var k = 0; k <= n; k++) {
        if (widened[k]) {
          left -= least[k];
        } else {
          free++;
        }
      }
      gap = free == 0 ? 0 : left / free;
      var changed = false;
      for (var k = 0; k <= n; k++) {
        if (!widened[k] && least[k] > gap + 1e-9) {
          widened[k] = true;
          changed = true;
        }
      }
      if (!changed) break;
    }
    if (gap <= 0) return null;
    final gaps = [for (var k = 0; k <= n; k++) widened[k] ? least[k] : gap];
    final centers = <double>[];
    final edges = <double>[0];
    var x = gaps[0];
    for (var i = 0; i < n; i++) {
      centers.add(x + labelWidths[i] / 2);
      x += labelWidths[i];
      if (i < n - 1) edges.add(x + gaps[i + 1] / 2);
      x += gaps[i + 1];
    }
    edges.add(width);
    final layout = EvenTabLayout._(
      gap,
      List.unmodifiable(gaps),
      List.unmodifiable(centers),
      List.unmodifiable(edges),
    );
    const e = 1e-6;
    for (var i = 0; i < n; i++) {
      if (layout.hitWidth(i) < minHit) return null;
      if (centers[i] - pillWidth / 2 < -e ||
          centers[i] + pillWidth / 2 > width + e) {
        return null;
      }
      if (i > 0 && centers[i] - centers[i - 1] < pillWidth - e) return null;
    }
    return layout;
  }
}

/// The bottom tabs (27 Nov, the owner via UX): Material 3's [NavigationBar] look
/// (80 dp, the 64 × 32 indicator, the icon theme, the label 4 dp under it),
/// laid out by [EvenTabLayout] instead of four equal slots, whose gaps
/// between labels of different lengths looked uneven ("Me" further away).
/// The labels' text size is the system's (at most 130 %, as NavigationBar),
/// or as much smaller as it takes for the layout to fit: never truncated.
class EvenTabBar extends StatelessWidget {
  const EvenTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<EvenTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const double height = 80;
  static const double _maxScale = 1.3;
  static const double _minScale = 0.6;

  /// The smallest text the even layout may use (the Reviewer, 27 Nov: no tab
  /// label under 85 % at normal text). Below it, a few spaces widen instead.
  static const double _minEvenScale = 0.85;

  /// The label style, as [NavigationBar] resolves it from the theme, and then
  /// as [Text] completes it (the ambient [DefaultTextStyle] under an
  /// inheriting style, and bold text when the system asks for it), so the
  /// widths measured for the layout are the widths drawn.
  static TextStyle labelStyle(BuildContext context, {required bool selected}) {
    final theme = NavigationBarTheme.of(context);
    final states = {if (selected) WidgetState.selected};
    final own =
        theme.labelTextStyle?.resolve(states) ??
        Theme.of(context).textTheme.labelMedium ??
        const TextStyle();
    var style = own.inherit
        ? DefaultTextStyle.of(context).style.merge(own)
        : own;
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return style;
  }

  /// The text size and layout for [width]: the system's size (clamped at
  /// 130 %), or the largest smaller one down to 85 %, with every space equal;
  /// if none, the system's size or the largest smaller one with a few spaces
  /// widened.
  static ({TextScaler scaler, EvenTabLayout layout})? fit(
    BuildContext context,
    double width,
    List<String> labels,
    int selectedIndex,
  ) {
    final system = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: _maxScale);
    List<double> widths(TextScaler s) => [
      for (var i = 0; i < labels.length; i++)
        (TextPainter(
          text: TextSpan(
            text: labels[i],
            style: labelStyle(context, selected: i == selectedIndex),
          ),
          textDirection: Directionality.of(context),
          // The script's font (Thai's fallback) as Text picks it.
          locale: Localizations.maybeLocaleOf(context),
          textScaler: s,
          maxLines: 1,
        )..layout()).width,
    ];
    // The system's factor at the label's size, then down in 5 % steps.
    final size = labelStyle(context, selected: true).fontSize ?? 12;
    final from = system.scale(size) / size;
    Iterable<TextScaler> sizes(double floor) sync* {
      yield system;
      for (var f = from - 0.05; f >= floor - 1e-9; f -= 0.05) {
        yield TextScaler.linear(f);
      }
    }

    for (final s in sizes(_minEvenScale)) {
      final l = EvenTabLayout.compute(width, widths(s));
      if (l != null && l.even) return (scaler: s, layout: l);
    }
    for (final s in sizes(_minScale)) {
      final l = EvenTabLayout.compute(width, widths(s));
      if (l != null) return (scaler: s, layout: l);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: theme.backgroundColor ?? colors.surfaceContainer,
      elevation: theme.elevation ?? 3,
      shadowColor: theme.shadowColor ?? Colors.transparent,
      surfaceTintColor: theme.surfaceTintColor ?? Colors.transparent,
      child: SafeArea(
        child: Semantics(
          role: SemanticsRole.tabBar,
          explicitChildNodes: true,
          container: true,
          child: SizedBox(
            height: theme.height ?? height,
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                final labels = [for (final t in tabs) t.label];
                final fitted = fit(context, width, labels, selectedIndex);
                final rtl = Directionality.of(context) == TextDirection.rtl;
                // Never reached with our labels (the tests check every language at
                // 320 and 360 dp and the largest text); a safe fallback all the same.
                final layout =
                    fitted?.layout ??
                    EvenTabLayout._(
                      0,
                      List.filled(tabs.length + 1, 0),
                      [
                        for (var i = 0; i < tabs.length; i++)
                          width * (i + 0.5) / tabs.length,
                      ],
                      [
                        for (var i = 0; i <= tabs.length; i++)
                          width * i / tabs.length,
                      ],
                    );
                final scaler = fitted?.scaler ?? TextScaler.linear(_minScale);
                return Stack(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: rtl
                            ? width - layout.edges[i + 1]
                            : layout.edges[i],
                        width: layout.hitWidth(i),
                        child: _EvenTabDestination(
                          tab: tabs[i],
                          index: i,
                          count: tabs.length,
                          selected: i == selectedIndex,
                          // The label's centre inside its own tap area.
                          centerX: rtl
                              ? layout.edges[i + 1] - layout.centers[i]
                              : layout.centers[i] - layout.edges[i],
                          scaler: scaler,
                          onTap: () => onDestinationSelected(i),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EvenTabDestination extends StatefulWidget {
  const _EvenTabDestination({
    required this.tab,
    required this.index,
    required this.count,
    required this.selected,
    required this.centerX,
    required this.scaler,
    required this.onTap,
  });

  final EvenTab tab;
  final int index;
  final int count;
  final bool selected;
  final double centerX;
  final TextScaler scaler;
  final VoidCallback onTap;

  @override
  State<_EvenTabDestination> createState() => _EvenTabDestinationState();
}

class _EvenTabDestinationState extends State<_EvenTabDestination>
    with SingleTickerProviderStateMixin {
  // NavigationBar's own timing for the indicator.
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.selected ? 1 : 0,
  );
  final GlobalKey _iconKey = GlobalKey();

  @override
  void didUpdateWidget(_EvenTabDestination old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      widget.selected ? _selection.forward() : _selection.reverse();
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    final states = {if (widget.selected) WidgetState.selected};
    final iconTheme =
        theme.iconTheme?.resolve(states) ??
        IconThemeData(
          size: 24,
          color: widget.selected
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        );
    final tab = widget.tab;
    // The tab's content: the indicator and icon, the label 4 dp under them,
    // centred as one block, its centre at centerX (the layout's).
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: _iconKey,
          width: 64,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              NavigationIndicator(
                animation: _selection,
                color: theme.indicatorColor ?? colors.secondaryContainer,
                shape: theme.indicatorShape ?? const StadiumBorder(),
              ),
              IconTheme.merge(
                data: iconTheme,
                child: Icon(widget.selected ? tab.selectedIcon : tab.icon),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          // The label as written is shown, not read: its spoken form comes
          // below (Insights' "AI and Insights").
          child: ExcludeSemantics(
            child: Text(
              tab.label,
              style: EvenTabBar.labelStyle(context, selected: widget.selected),
              textScaler: widget.scaler,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ],
    );
    // NavigationBar's own order: one merged node per tab, its tab role and
    // selected state, then the TestId (Maestro's id, a button, selected) and,
    // inside, the ink with its tap action, so a screen reader's double-tap
    // opens the tab.
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: widget.selected,
        child: TestId(
          'tab-${tab.id}',
          button: true,
          selected: widget.selected,
          child: Stack(
            children: [
              Positioned.fill(
                child: Tooltip(
                  message: tab.label,
                  verticalOffset: 42,
                  excludeFromSemantics: true,
                  child: _IndicatorInk(
                    iconKey: _iconKey,
                    customBorder: theme.indicatorShape ?? const StadiumBorder(),
                    overlayColor: theme.overlayColor,
                    onTap: widget.onTap,
                    child: CustomSingleChildLayout(
                      delegate: _CenterAt(widget.centerX),
                      child: content,
                    ),
                  ),
                ),
              ),
              // What a screen reader says: the label without "&", then
              // "Tab n of N", as NavigationBar's own destination does.
              Semantics(label: tab.semanticsLabel),
              Semantics(
                label: MaterialLocalizations.of(
                  context,
                ).tabLabel(tabIndex: widget.index + 1, tabCount: widget.count),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centres the child vertically, and horizontally at [x].
class _CenterAt extends SingleChildLayoutDelegate {
  const _CenterAt(this.x);

  final double x;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxHeight: constraints.maxHeight);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(x - childSize.width / 2, (size.height - childSize.height) / 2);

  @override
  bool shouldRelayout(_CenterAt old) => old.x != x;
}

/// NavigationBar's ink: the whole tap area answers, the splash stays on the
/// indicator around the icon.
class _IndicatorInk extends InkResponse {
  const _IndicatorInk({
    required this.iconKey,
    super.customBorder,
    super.overlayColor,
    super.onTap,
    super.child,
  }) : super(containedInkWell: true, highlightColor: Colors.transparent);

  final GlobalKey iconKey;

  @override
  RectCallback? getRectCallback(RenderBox referenceBox) {
    return () {
      final iconBox = iconKey.currentContext!.findRenderObject()! as RenderBox;
      final iconRect = iconBox.localToGlobal(Offset.zero) & iconBox.size;
      return referenceBox.globalToLocal(iconRect.topLeft) & iconBox.size;
    };
  }
}
