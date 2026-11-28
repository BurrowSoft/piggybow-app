// Pig tips on screen (A3, decision 90): the consent sheet before anything
// is sent, Me's switch, and Report under a written tip. The words are UX's
// (specs: the AI tips texts, §2 and §3); the client is PigTips (A2).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/button_label.dart';
import '../../core/policy.dart';
import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../tips/pig_tips.dart';

/// Me's "Pig tips" switch. On: the consent sheet first, and tips turn on
/// only after its Yes. Off: at once, said in a snackbar (UX).
Future<void> switchPigTips(BuildContext context, PigTips tips, bool on) async {
  if (on) {
    await showTipsConsent(context, tips);
    return;
  }
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  await tips.turnOff();
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.pigTipsOffNote)));
}

/// The consent sheet (UX's §2): what's sent, to whom, that tips aren't
/// advice and are for adults, and how to turn them off. True when tips were
/// turned on; "Not now", or closing it, changes nothing.
Future<bool> showTipsConsent(BuildContext context, PigTips tips) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TipsConsentSheet(tips: tips),
    ) ??
    false;

class _TipsConsentSheet extends StatefulWidget {
  const _TipsConsentSheet({required this.tips});

  final PigTips tips;

  @override
  State<_TipsConsentSheet> createState() => _TipsConsentSheetState();
}

class _TipsConsentSheetState extends State<_TipsConsentSheet> {
  bool _busy = false;

  /// The server didn't answer, or refused: the sheet stays, says so, and
  /// tips stay off (UX).
  bool _failed = false;

  Future<void> _yes() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      // The versions of this sheet's texts, from one place: the same ones a
      // release build's tips wait for (PolicyVersions.aiTextsFinal).
      await widget.tips.turnOn(
        aiVersion: PolicyVersions.ai,
        age18Version: PolicyVersions.age18,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PigTipsUnavailable {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final config = ConfigScope.of(context);
    final ink = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    return TestId.container(
      'tips-sheet',
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.tipsSheetTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.tipsSheetIntro, style: ink),
              const SizedBox(height: 12),
              for (final line in [
                l10n.tipsSheetSends,
                l10n.tipsSheetWho,
                l10n.tipsSheetAdvice,
                l10n.tipsSheetOff,
              ])
                _Point(line, style: ink),
              if (config.privacyUrl.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TestId(
                    'tips-sheet-how',
                    button: true,
                    child: TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(config.privacyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: ButtonLabel(l10n.tipsSheetHow),
                    ),
                  ),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TestId(
                    'tips-sheet-failed',
                    child: Semantics(
                      liveRegion: true,
                      child: Text(l10n.tipsUnavailable, style: ink),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TestId(
                  'tips-sheet-yes',
                  button: true,
                  child: FilledButton(
                    onPressed: _busy ? null : _yes,
                    child: ButtonLabel(l10n.tipsSheetYes),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TestId(
                  'tips-sheet-not-now',
                  button: true,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: ButtonLabel(l10n.tipsSheetNotNow),
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

/// One point of the sheet's list: a small dot, then its line. The dot sits
/// in a box one first line tall (the same style and text size), so it's at
/// that line's middle at every text size (UX).
class _Point extends StatelessWidget {
  const _Point(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final dot = Theme.of(context).colorScheme.primary;
    final line = TextPainter(
      text: TextSpan(text: text.characters.take(1).toString(), style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final lineHeight = line.height;
    line.dispose();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: SizedBox(
              height: lineHeight,
              child: Center(child: Icon(Icons.circle, size: 6, color: dot)),
            ),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// "Report" under a written tip: the reason, or null for Cancel.
Future<TipReportReason?> showTipReport(BuildContext context) =>
    showModalBottomSheet<TipReportReason>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        return TestId.container(
          'tip-report-sheet',
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.tipReportTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  for (final reason in TipReportReason.values)
                    TestId(
                      'tip-report-${reason.name}',
                      button: true,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        title: Text(tipReportReasonText(l10n, reason)),
                        onTap: () => Navigator.of(context).pop(reason),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: TestId(
                        'tip-report-cancel',
                        button: true,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: ButtonLabel(l10n.cancel),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

/// A report reason's words (UX).
String tipReportReasonText(AppLocalizations l10n, TipReportReason reason) =>
    switch (reason) {
      TipReportReason.unhelpful => l10n.tipReportUnhelpful,
      TipReportReason.wrong => l10n.tipReportWrong,
      TipReportReason.upsetting => l10n.tipReportUpsetting,
      TipReportReason.advice => l10n.tipReportAdvice,
      TipReportReason.other => l10n.tipReportOther,
    };

/// Report: asks the reason, sends it (A2 keeps it to send later when there's
/// no connection, so it's never lost) and thanks at once. [onReported] runs
/// before the thanks, so the tip it was about can go away (UX: a built-in
/// tip for the rest of the day).
Future<void> reportTip(
  BuildContext context,
  PigTips tips,
  WrittenTip tip, {
  required VoidCallback onReported,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final reason = await showTipReport(context);
  if (reason == null) return;
  onReported();
  unawaited(tips.report(tip, reason));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.tipReportThanks)));
}
