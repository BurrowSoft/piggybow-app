import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/theme.dart';

/// Back on every pushed screen (decision 152): a chevron only, in a round
/// tinted target of 48 dp (≥ 44 pt), spoken as "Back to [to]". [onPressed]
/// defaults to popping this screen.
class PiggybowBack extends StatelessWidget {
  const PiggybowBack({
    super.key,
    required this.id,
    required this.to,
    this.spokenTo,
    this.onPressed,
  });

  final String id;

  /// The screen it returns to, as the user knows it (a tab, a day).
  final String to;

  /// How a screen reader says [to], when it differs (27 Nov: "AI & Insights"
  /// is read "AI and Insights"). Null: [to].
  final String? spokenTo;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final shown = l10n.navBackTo(to);
    final spoken = l10n.navBackTo(spokenTo ?? to);
    final button = IconButton(
      onPressed: onPressed ?? () => context.pop(),
      // The spoken name and the long-press tooltip, when they're the same.
      tooltip: spoken == shown ? shown : null,
      style: IconButton.styleFrom(
        backgroundColor: palette.pillBackground,
        foregroundColor: palette.accent,
        fixedSize: const Size.square(48),
        minimumSize: const Size.square(48),
      ),
      icon: const Icon(Icons.chevron_left_rounded),
    );
    return TestId(
      id,
      button: true,
      child: Center(
        child: spoken == shown
            ? button
            // Else: the tooltip shows the name as written, the screen reader
            // says the spoken form (once: the tooltip stays out of semantics).
            : Tooltip(
                message: shown,
                excludeFromSemantics: true,
                child: Semantics(label: spoken, child: button),
              ),
      ),
    );
  }
}
