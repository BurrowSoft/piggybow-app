import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/journal_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/money.dart';
import '../../pig/pig_mood.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../settings_rules/settings_rules.dart';
import '../../theme/theme.dart';
import '../currency/currency_picker.dart';
import '../goal/rainbow.dart';
import '../pig/pig_view.dart';

/// Whether onboarding is done, at start. It shows only over a blank journal:
/// one with notes (a phone from before onboarding, or one stopped between
/// O2 and the end of O3) counts as onboarded, and says so from then on, so
/// onboarding never overwrites picks or adds a second goal.
Future<bool> onboardedAtStart(JournalStore journal) async {
  if (await journal.onboarded()) return true;
  if (await journal.isBlank()) return false;
  await journal.setOnboarded();
  return true;
}

/// O1 Welcome (plan §3.1): the pig, happy, under a full rainbow; what the
/// app is; that nothing leaves the phone; the currency, which can change
/// here; and Get started.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String? _currency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final code = await context.services.journal.currency() ?? 'USD';
    if (mounted) setState(() => _currency = code);
  }

  Future<void> _change() async {
    await changeCurrency(context);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final currency = _currency;
    final muted = theme.colorScheme.onSurfaceVariant;
    return TestId.container(
      'onb-welcome',
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              const Center(
                child: SizedBox(width: 240, child: Rainbow(percent: 100)),
              ),
              const SizedBox(height: 8),
              const Center(child: PigView(mood: PigMood.happy)),
              const SizedBox(height: 24),
              Text(
                l10n.onbWelcomeTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.onbWelcomeBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.onbWelcomePrivacy,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 24),
              if (currency != null)
                Row(
                  children: [
                    Expanded(
                      child: TestId(
                        'onb-currency',
                        child: Text(
                          l10n.onbCurrencyLine(
                            l10n.currencyName(currency),
                            currencySymbolOf(currency, locale),
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TestId(
                      'onb-currency-change',
                      button: true,
                      child: TextButton(
                        onPressed: _change,
                        child: Text(l10n.onbCurrencyChange),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              TestId(
                'onb-start',
                button: true,
                child: FilledButton(
                  onPressed: () => context.push(OnboardingRoutes.happy),
                  child: Text(l10n.onbStart, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O2 "What makes your pig happy?" (plan §3.1): three cards, none picked
/// first; the weekly plan's amount shows under its card once it's picked.
/// Continue is always enabled and says what's missing (settings_rules).
class HappyScreen extends StatefulWidget {
  const HappyScreen({super.key, this.inMe = false, this.removingPlan = false});

  /// Me's picker: the saved picks and plan to start, Done back to Me.
  final bool inMe;

  /// Me → Remove plan with only the plan picked (settings_rules.removePlan):
  /// the plan starts unpicked, and goes once the new picks are saved.
  final bool removingPlan;

  @override
  State<HappyScreen> createState() => _HappyScreenState();
}

class _HappyScreenState extends State<HappyScreen> {
  final _picks = <HappyPick>{};
  final _plan = TextEditingController();
  String? _currency;
  PicksProblem? _problem;
  bool _planTooBig = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final locale = context.readSession.device.localeName;
    final code = await store.currency() ?? 'USD';
    final picks = widget.inMe ? await store.picks() : const <HappyPick>{};
    final plan = widget.inMe ? await store.planMinor() : null;
    if (!mounted) return;
    setState(() {
      _currency = code;
      _picks
        ..clear()
        ..addAll(picks);
      if (widget.removingPlan) _picks.remove(HappyPick.plan);
      if (plan != null) _plan.text = inputAmount(plan, code, locale);
    });
  }

  @override
  void dispose() {
    _plan.dispose();
    super.dispose();
  }

  void _toggle(HappyPick pick, bool on) => setState(() {
    on ? _picks.add(pick) : _picks.remove(pick);
    _problem = null;
    _planTooBig = false;
  });

  Future<void> _continue() async {
    final currency = _currency;
    if (_busy || currency == null) return;
    final withPlan = _picks.contains(HappyPick.plan);
    final parsed = parseAmount(_plan.text, currency);
    if (withPlan && parsed.problem == AmountProblem.tooBig) {
      setState(() => _planTooBig = true);
      return;
    }
    final plan = withPlan ? parsed.minor : null;
    final problem = validatePicks(_picks, planMinor: plan);
    setState(() => _problem = problem);
    if (problem != null) return;
    setState(() => _busy = true);
    final store = context.services.journal;
    await store.setPicks(_picks);
    if (plan != null) await store.setPlanMinor(plan);
    if (widget.removingPlan) await store.setPlanMinor(null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.inMe) {
      context.pop();
    } else {
      unawaited(context.push(OnboardingRoutes.goal));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final planError = _planTooBig
        ? l10n.addAmountTooBig
        : _problem == PicksProblem.planNeeded
        ? l10n.happyPlanNeeded
        : null;
    final inMe = widget.inMe;
    return TestId.container(
      inMe ? 'me-happy' : 'onb-happy',
      child: Scaffold(
        // A plain back bar: the title is the headline below, whole at any size.
        appBar: AppBar(),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(
                inMe ? l10n.meHappy : l10n.onbHappyTitle,
                style: theme.textTheme.headlineSmall,
              ),
              if (!inMe) ...[
                const SizedBox(height: 8),
                Text(l10n.onbHappyBody, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 16),
              for (final pick in HappyPick.values) ...[
                _PickCard(
                  pick: pick,
                  selected: _picks.contains(pick),
                  onChanged: (on) => _toggle(pick, on),
                ),
                if (pick == HappyPick.plan && _picks.contains(HappyPick.plan)) ...[
                  const SizedBox(height: 8),
                  TestId(
                    'onb-plan',
                    child: TextField(
                      controller: _plan,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: context.inputText,
                      onChanged: (_) => setState(() {
                        _problem = null;
                        _planTooBig = false;
                      }),
                      decoration: InputDecoration(
                        // One line, whole: smaller only if it must.
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(l10n.happyPlanField),
                        ),
                        errorText: planError,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
              if (_problem == PicksProblem.pickOne)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.happyPickOne,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TestId(
                inMe ? 'me-happy-done' : 'onb-continue',
                button: true,
                child: FilledButton(
                  onPressed: _busy ? null : _continue,
                  child: Text(
                    inMe ? l10n.done : l10n.onbContinue,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pick on O2 (and in Me later): its title, its hint, a checkbox.
class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.pick,
    required this.selected,
    required this.onChanged,
  });

  final HappyPick pick;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (title, hint) = switch (pick) {
      HappyPick.save => (l10n.happySaveTitle, l10n.happySaveHint),
      HappyPick.plan => (l10n.happyPlanTitle, l10n.happyPlanHint),
      HappyPick.worth => (l10n.happyWorthTitle, l10n.happyWorthHint),
    };
    return TestId(
      'onb-pick-${pick.name}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: CheckboxListTile(
          value: selected,
          onChanged: (v) => onChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          // Whole words at large text: the checkbox leaves the title little room.
          title: WholeWordsText(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: WholeWordsText(
            hint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
