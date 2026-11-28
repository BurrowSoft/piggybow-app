import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/button_label.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../pig/pig_mood.dart' show PigMood;
import '../../router.dart';
import '../pig/pig_view.dart';
import 'plus_entitlement.dart';
import 'plus_store.dart';

/// Before a Plus feature (more goals, categories, themes): true when Plus
/// is on. Otherwise the paywall opens, and the answer is whether Plus is on
/// once it closes. A build without Plus (PLUS_ENABLED off) has no Plus
/// feature at all: always false, and nothing opens.
Future<bool> requirePlus(BuildContext context) async {
  final plus = context.services.plus;
  if (plus == null) return false;
  if (plus.active) return true;
  await context.push(PlusRoutes.paywall);
  return plus.active;
}

/// A store's price kept whole on its line ("R$ 14,90" never splits).
String wholePrice(String price) =>
    price.replaceAll(' ', String.fromCharCode(0x00A0));

/// The paywall: the pig, what Plus brings, each plan at the store's own
/// price, Restore, the store's cancel line, and the Terms of Use and
/// Privacy Policy links. It opens only from Plus's own places (Me's row, a
/// Plus feature): never at launch, as a pop-up or after a save. With Plus
/// on, it says so and offers the store's subscription page.
class PlusScreen extends StatefulWidget {
  const PlusScreen({super.key});

  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  PlusEntitlement? _plus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final plus = _plus = context.services.plus;
      plus?.addListener(_changed);
      if (plus != null) unawaited(plus.loadPlans());
    });
  }

  @override
  void dispose() {
    _plus?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plus = context.services.plus;
    return TestId.container(
      'plus-screen',
      child: Scaffold(
        appBar: AppBar(title: AppBarTitle(l10n.plusTitle)),
        body: plus == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Center(child: PigView(mood: PigMood.delighted, size: 120)),
                  const SizedBox(height: 16),
                  if (plus.active) ..._on(context, plus) else ..._offer(context, plus),
                ],
              ),
      ),
    );
  }

  List<Widget> _on(BuildContext context, PlusEntitlement plus) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      TestId.container(
        'plus-on',
        child: WholeWordsText(
          l10n.plusOnTitle,
          style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurface),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.plusOnBody,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
      ),
      ?_note(context, plus.note),
      const SizedBox(height: 16),
      TestId(
        'plus-manage',
        button: true,
        child: OutlinedButton(onPressed: plus.manage, child: ButtonLabel(l10n.plusManage)),
      ),
    ];
  }

  List<Widget> _offer(BuildContext context, PlusEntitlement plus) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final config = ConfigScope.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final plans = plus.plans;
    return [
      // Body text: at large sizes the plans stay near the top (UX).
      WholeWordsText(
        l10n.plusIntro,
        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      for (final (id, text) in [
        ('plus-benefit-goals', l10n.plusBenefitGoals),
        ('plus-benefit-categories', l10n.plusBenefitCategories),
        ('plus-benefit-themes', l10n.plusBenefitThemes),
      ])
        TestId.container(
          id,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            title: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      const SizedBox(height: 8),
      if (plans == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: TestId.container(
              'plus-loading',
              child: CircularProgressIndicator(semanticsLabel: l10n.plusLoading),
            ),
          ),
        )
      else if (plans.isEmpty)
        TestId.container(
          'plus-unavailable',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l10n.plusUnavailable, style: muted, textAlign: TextAlign.center),
          ),
        )
      else
        for (final plan in plans)
          _PlanCard(
            plan: plan,
            // While a payment waits for the store, no second one can start
            // (UX). Restore and the links stay; the store's next word (the
            // purchase approved, or Restore's answer) ends the wait.
            busy: plus.busy || plus.note == PlusNote.pending,
            onBuy: () => plus.buy(plan),
          ),
      ?_note(context, plus.note),
      const SizedBox(height: 8),
      TestId(
        'plus-restore',
        button: true,
        child: TextButton(
          onPressed: plus.busy ? null : plus.restore,
          child: ButtonLabel(l10n.plusRestore),
        ),
      ),
      const SizedBox(height: 8),
      TestId.container(
        'plus-cancel',
        child: Text(
          plus.source == PlusSource.apple ? l10n.plusCancelApple : l10n.plusCancelPlay,
          style: muted,
          textAlign: TextAlign.center,
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          if (config.termsUrl.isNotEmpty)
            TestId(
              'plus-terms',
              button: true,
              child: TextButton(
                onPressed: () => _open(config.termsUrl),
                child: ButtonLabel(l10n.plusTerms),
              ),
            ),
          if (config.privacyUrl.isNotEmpty)
            TestId(
              'plus-privacy',
              button: true,
              child: TextButton(
                onPressed: () => _open(config.privacyUrl),
                child: ButtonLabel(l10n.plusPrivacy),
              ),
            ),
        ],
      ),
    ];
  }

  /// The line after a purchase or a restore, read out when it appears.
  Widget? _note(BuildContext context, PlusNote note) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = switch (note) {
      PlusNote.none => null,
      PlusNote.pending => l10n.plusNotePending,
      PlusNote.notThrough => l10n.plusNoteNotThrough,
      PlusNote.unavailable => l10n.plusNoteUnavailable,
      PlusNote.restored => l10n.plusNoteRestored,
      PlusNote.nothingToRestore => l10n.plusNoteNothing,
    };
    if (text == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TestId.container(
        'plus-note',
        child: Semantics(
          liveRegion: true,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// One plan: its name, the store's price for one period, the free week when
/// the store offers it, and its own Start button (no plan is picked for the
/// person).
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.busy, required this.onBuy});

  final PlusPlan plan;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final price = wholePrice(plan.price);
    // Yearly only (decision 85): a plan of another period needs its own
    // strings first.
    final (id, name, trialLine, priceLine, startLabel) = switch (plan.period) {
      PlusPeriod.year => (
        'plus-plan-yearly',
        l10n.plusPlanYearly,
        l10n.plusTrialYearly(price),
        l10n.plusPriceYearly(price),
        l10n.plusStartYearly,
      ),
    };
    return TestId.container(
      id,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WholeWordsText(
                name,
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              // With the free week, its line alone (it names the price);
              // else the price line (UX: the price never shows twice).
              if (plan.trialOffered)
                TestId.container(
                  '$id-trial',
                  child: WholeWordsText(
                    trialLine,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
                  ),
                )
              else
                TestId.container(
                  '$id-price',
                  child: WholeWordsText(
                    priceLine,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
                  ),
                ),
              const SizedBox(height: 12),
              TestId(
                '$id-start',
                button: true,
                child: FilledButton(
                  onPressed: busy ? null : onBuy,
                  child: ButtonLabel(plan.trialOffered ? l10n.plusStartTrial : startLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
