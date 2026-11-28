import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/currency.dart';
import '../../session/session_scope.dart';
import '../../settings_rules/settings_rules.dart';

/// [code]'s symbol as the app's amounts show it ("฿" for THB in English).
String currencySymbolOf(String code, String locale) =>
    NumberFormat.simpleCurrency(locale: locale, name: code).currencySymbol;

/// Changes the journal's currency through the picker (plan §3.9). While
/// anything is stored in it (an entry or a goal) it can't change, and
/// "Currency is set" says why (decision 21).
Future<void> changeCurrency(BuildContext context) async {
  final store = context.services.journal;
  final changeable = currencyChangeable(
    entryCount: (await store.entries()).length,
    goalCount: (await store.goals()).length,
  );
  final current = await store.currency() ?? 'USD';
  if (!context.mounted) return;
  if (!changeable) {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.currencyFixedTitle),
        content: Text(l10n.currencyFixedBody),
        actions: [
          TestId(
            'currency-fixed-ok',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.ok),
            ),
          ),
        ],
      ),
    );
    return;
  }
  final picked = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => CurrencyPickerScreen(current: current)),
  );
  if (picked != null && picked != current) await store.setCurrency(picked);
}

/// Every supported currency, the phone's own first, then by name: "Thai baht
/// (฿)". A tap picks one; the current one is ticked.
class CurrencyPickerScreen extends StatelessWidget {
  const CurrencyPickerScreen({super.key, required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final order = currencyOrder(defaultCurrency(locale), l10n.currencyName);
    return TestId.container(
      'currency-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.currencyTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              for (final code in order)
                TestId(
                  'currency-$code',
                  button: true,
                  selected: code == current,
                  child: ListTile(
                    title: Text(
                      l10n.currencyRow(
                        l10n.currencyName(code),
                        currencySymbolOf(code, locale),
                      ),
                    ),
                    trailing: code == current
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(code),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
