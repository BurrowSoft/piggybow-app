import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/button_label.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../router.dart';
import '../plus/plus_screen.dart';

/// Me → Categories: what the Add sheet offers for a spend. The built-ins can
/// be hidden and shown again, by everyone, and never renamed. Your own (Plus,
/// decision 79) can be added, renamed, given another icon, hidden and shown.
/// None is ever deleted: a hidden one stays on its past spends. One always
/// stays showing.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  Set<SpendCategory>? _hidden;
  List<CustomCategory> _customs = const [];
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final services = _services = context.services;
      services.journal.addListener(_load);
      services.plus?.addListener(_plusChanged);
      _load();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    _services?.plus?.removeListener(_plusChanged);
    super.dispose();
  }

  /// Your own show their Plus line, and can be edited, as Plus is on or off.
  void _plusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final store = _services?.journal;
    if (store == null) return;
    final hidden = await store.hiddenBuiltIns();
    final customs = await store.customCategories();
    if (!mounted) return;
    setState(() {
      _hidden = hidden;
      _customs = customs;
    });
  }

  /// Whether the Add sheet would still offer a category with [builtIn] or
  /// [custom] hidden too.
  bool _leavesOne({SpendCategory? builtIn, String? custom}) =>
      usableCategories(
        hidden: {..._hidden!, ?builtIn},
        customs: [
          for (final c in _customs)
            c.id == custom ? c.copyWith(hidden: true) : c,
        ],
        plus: _services?.plus?.active ?? false,
      ).isNotEmpty;

  Future<void> _setBuiltIn(SpendCategory category, bool hidden) async {
    if (hidden && !_leavesOne(builtIn: category)) {
      _keepOne();
      return;
    }
    await _services!.journal.setBuiltInHidden(category, hidden);
  }

  Future<void> _setCustom(CustomCategory category, bool hidden) async {
    if (hidden && !_leavesOne(custom: category.id)) {
      _keepOne();
      return;
    }
    await _services!.journal.setCustomHidden(category.id, hidden);
  }

  /// The last category showing stays: it says so instead.
  void _keepOne() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).categoryKeepOne)),
    );
  }

  /// A new category of your own, or another name or icon for one: Plus's.
  Future<void> _open(String location) async {
    if (!await requirePlus(context) || !mounted) return;
    await context.push<String>(location);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hidden = _hidden;
    final plus = context.services.plus;
    final plusOn = plus?.active ?? false;
    return TestId.container(
      'categories-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.categoriesTitle)),
        body: hidden == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _Header(l10n.categoriesBuiltIn),
                  for (final c in SpendCategory.values)
                    _CategoryRow(
                      id: 'categories-${c.id}',
                      icon: c.icon,
                      name: c.label(l10n),
                      hidden: hidden.contains(c),
                      onToggle: (hide) => _setBuiltIn(c, hide),
                    ),
                  // Yours: in builds with Plus, and wherever you have some.
                  if (plus != null || _customs.isNotEmpty) ...[
                    _Header(l10n.categoriesYours),
                    if (!plusOn && _customs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TestId.container(
                          'categories-plus-ended',
                          child: Text(
                            l10n.categoriesPlusEnded,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    for (final (i, c) in _customs.indexed)
                      _CategoryRow(
                        id: 'categories-custom-${i + 1}',
                        icon: c.icon.icon,
                        name: c.name,
                        hidden: c.hidden,
                        onToggle: (hide) => _setCustom(c, hide),
                        onTap: plus == null
                            ? null
                            : () => _open(CategoryRoutes.edit(c.id)),
                      ),
                    if (plus != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TestId(
                            'categories-add',
                            button: true,
                            child: OutlinedButton.icon(
                              onPressed: () => _open(CategoryRoutes.create),
                              icon: const Icon(Icons.add),
                              label: ButtonLabel(l10n.categoryAdd),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// A section's title, as in Me.
class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// One category: its icon, its name, "Hidden" when it is, and Hide or Show.
/// A row of your own opens its editor ([onTap]).
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.id,
    required this.icon,
    required this.name,
    required this.hidden,
    required this.onToggle,
    this.onTap,
  });

  final String id;
  final IconData icon;
  final String name;
  final bool hidden;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return TestId.container(
      id,
      child: ListTile(
        leading: Icon(
          icon,
          color: hidden ? theme.colorScheme.onSurfaceVariant : null,
        ),
        // Each word whole beside Hide or Show, smaller only if it must.
        title: WholeWordsText(name),
        subtitle: hidden ? Text(l10n.categoryHidden) : null,
        onTap: onTap,
        trailing: TestId(
          '$id-toggle',
          button: true,
          child: TextButton(
            onPressed: () => onToggle(!hidden),
            child: ButtonLabel(hidden ? l10n.categoryShow : l10n.categoryHide),
          ),
        ),
      ),
    );
  }
}
