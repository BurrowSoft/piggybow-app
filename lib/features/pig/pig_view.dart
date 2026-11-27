import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../pig/pig_mood.dart';

/// The pig's file for [mood]: `design/pig-{mood}.svg`, byte for byte.
String pigAsset(PigMood mood) => 'assets/pig/pig-${mood.name}.svg';

/// The pig (plan §4.1), front-facing, in one of its four moods. Decorative:
/// its line is in text beside it. Delighted hops once when it arrives,
/// except under reduce-motion.
class PigView extends StatefulWidget {
  const PigView({super.key, required this.mood, this.size = 160});

  final PigMood mood;
  final double size;

  @override
  State<PigView> createState() => _PigViewState();
}

class _PigViewState extends State<PigView> with SingleTickerProviderStateMixin {
  late final _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    if (widget.mood == PigMood.delighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hopOnce());
    }
  }

  @override
  void didUpdateWidget(PigView old) {
    super.didUpdateWidget(old);
    if (widget.mood == PigMood.delighted && old.mood != PigMood.delighted) {
      _hopOnce();
    }
  }

  void _hopOnce() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    _hop.forward(from: 0);
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _hop,
      builder: (context, child) => Transform.translate(
        // Up and back down: 12 dp at the top of the hop.
        offset: Offset(0, -12 * math.sin(math.pi * _hop.value)),
        child: child,
      ),
      child: SvgPicture.asset(
        pigAsset(widget.mood),
        width: widget.size,
        height: widget.size,
      ),
    ),
  );
}

/// The text of the pig's line [key] (an ARB key from pigMood or
/// pigBubbleKey), with its [args]. An unknown key shows a calm line rather
/// than nothing (and fails in debug builds).
String pigLineText(
  AppLocalizations l10n,
  String key, [
  Map<String, Object> args = const {},
]) {
  final text = switch (key) {
    'pigFirstDay' => l10n.pigFirstDay,
    'pigCalm1' => l10n.pigCalm1,
    'pigCalm2' => l10n.pigCalm2,
    'pigCalm3' => l10n.pigCalm3,
    'pigCalmMonday' => l10n.pigCalmMonday,
    'pigHappySave' => l10n.pigHappySave,
    'pigHappyPlan' => l10n.pigHappyPlan,
    'pigHappyWorth' => l10n.pigHappyWorth,
    'pigDelightedAll' => l10n.pigDelightedAll,
    'pigDelightedBand' => l10n.pigDelightedBand(args['band'] as int? ?? 1),
    'pigDelightedGoal' => l10n.pigDelightedGoal(
      args['goalName'] as String? ?? '',
    ),
    'pigSleepy1' => l10n.pigSleepy1,
    'pigSleepy2' => l10n.pigSleepy2,
    'pigSleepy3' => l10n.pigSleepy3,
    'pigAfterSpend' => l10n.pigAfterSpend,
    'pigAfterWorth' => l10n.pigAfterWorth,
    'pigAfterNotSure' => l10n.pigAfterNotSure,
    'pigAfterNotReally' => l10n.pigAfterNotReally,
    'pigAfterSave' => l10n.pigAfterSave,
    _ => null,
  };
  assert(text != null, 'no text for the pig line "$key"');
  return text ?? l10n.pigCalm1;
}

/// The pig's line, in a speech bubble under it.
class PigBubble extends StatelessWidget {
  const PigBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
