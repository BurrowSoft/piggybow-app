import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The status bar over a page with no app bar (decision 65): see-through, so
/// the page shows behind it, with icons that read on it, dark in light mode
/// and light in dark. The same fields Material 3's AppBar sets, so a screen
/// with an AppBar looks the same; the navigation bar is left as it is.
SystemUiOverlayStyle pageStatusBar(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android: the icons' own brightness.
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    // iOS: the brightness of what's behind the bar.
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    // No grey scrim behind a see-through bar.
    systemStatusBarContrastEnforced: false,
  );
}

/// [pageStatusBar] for the app's theme under every page. An [AppBar] sets its
/// own style over it.
class PageStatusBar extends StatelessWidget {
  const PageStatusBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: pageStatusBar(Theme.of(context).brightness),
    child: child,
  );
}
