import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The system bars over every page: see-through, so the page's own
/// background shows behind them in light and dark, with icons that read on
/// it (dark in light mode, light in dark).
///
/// Status bar (decision 65): the same fields Material 3's AppBar sets, so a
/// screen with an AppBar looks the same.
///
/// Navigation bar: Android 15+ already draws the app behind it (Piggybow
/// targets SDK 36, where edge-to-edge is enforced); older Android showed an
/// opaque black bar there. With [enableEdgeToEdge] every version draws
/// behind it, and these fields keep it see-through: no colour, no divider,
/// and no grey scrim that Android would otherwise add behind three-button
/// navigation. Pages keep their content above it (SafeArea, or the tab bar).
SystemUiOverlayStyle pageSystemBars(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final icons = dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android: the icons' own brightness.
    statusBarIconBrightness: icons,
    // iOS: the brightness of what's behind the bar.
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    // No grey scrim behind a see-through bar.
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

/// [pageSystemBars] for the app's theme under every page. An [AppBar] sets
/// its own status-bar style over it.
class PageSystemBars extends StatelessWidget {
  const PageSystemBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: pageSystemBars(Theme.of(context).brightness),
    child: child,
  );
}

/// The app draws behind the status and navigation bars on every Android
/// version, as Android 15+ already makes it (main() calls this before the
/// first frame). iOS always does.
Future<void> enableEdgeToEdge() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
