import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/button_label.dart';
import '../../core/line_breaks.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/theme.dart';
import '../plus/plus_screen.dart';

/// A category of your own (Plus, decision 79), new or edited: its name (up
/// to [categoryNameMax] characters, and not a name you already have, the
/// built-ins' included, in any case) and one of [CategoryIcon]'s icons.
/// Save goes back with its id (the Add sheet then picks it).
class CategoryEditScreen extends StatefulWidget {
  const CategoryEditScreen({super.key, this.categoryId});

  /// The category to edit; null for a new one.
  final String? categoryId;

  @override
  State<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends State<CategoryEditScreen> {
  final _name = TextEditingController();
  CategoryIcon _icon = CategoryIcon.preset;
  CustomCategory? _category;

  /// Your other categories' names, lower case; null until read.
  Set<String>? _others;
  bool _tried = false;
  bool _busy = false;

  /// The last Save failed in the store.
  bool _failed = false;

  bool get _editing => widget.categoryId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final id = widget.categoryId;
    final customs = await context.services.journal.customCategories();
    if (!mounted) return;
    final category = customs.where((c) => c.id == id).firstOrNull;
    // A category that isn't there (a stale link) has nothing to edit.
    if (id != null && category == null) {
      context.pop();
      return;
    }
    setState(() {
      _category = category;
      _others = {
        for (final c in customs)
          if (c.id != id) c.name.toLowerCase(),
      };
      if (category != null) {
        _name.text = category.name;
        _icon = category.icon;
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Empty (after Save), or a name you already have: one of your others', or
  /// a built-in's in the app's language. A category keeps its own name even
  /// if a built-in's became the same (the app's language changed).
  String? _nameError(AppLocalizations l10n) {
    final name = _name.text.trim();
    if (name.isEmpty) return _tried ? l10n.categoryNameEmpty : null;
    if (name == _category?.name) return null;
    final lower = name.toLowerCase();
    final taken =
        (_others?.contains(lower) ?? false) ||
        SpendCategory.values.any((c) => c.label(l10n).toLowerCase() == lower);
    return taken ? l10n.categoryNameTaken : null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_busy || _others == null) return;
    setState(() => _tried = true);
    if (_nameError(l10n) != null) return;
    // Your own categories are Plus's: the way here asked for it, and Save
    // asks again (Plus may have ended meanwhile).
    if (!await requirePlus(context) || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final services = context.services;
    final store = services.journal;
    final name = _name.text.trim();
    final old = _category;
    final category = old == null
        ? CustomCategory(
            id: store.newCategoryId(),
            name: name,
            icon: _icon,
            createdAt: services.clock.nowUtc(),
          )
        : old.copyWith(name: name, icon: _icon);
    try {
      await store.putCustomCategory(category);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'category edit',
        ),
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
      return;
    }
    if (mounted) context.pop(category.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return TestId.container(
      'category-edit-screen',
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing ? l10n.categoryEditTitle : l10n.categoryNewTitle,
          ),
        ),
        body: _others == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TestId(
                    'category-name',
                    child: TextField(
                      controller: _name,
                      autofocus: !_editing,
                      textCapitalization: TextCapitalization.sentences,
                      // Up to 3 lines, so a long name is seen whole, but one
                      // line of text: Enter is Done; a pasted break becomes
                      // a space.
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [LineBreaksAsSpaces()],
                      maxLength: categoryNameMax,
                      style: context.inputText,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.categoryNameLabel,
                        errorText: _nameError(l10n),
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.categoryIconLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final icon in CategoryIcon.values)
                        TestId(
                          'category-icon-${icon.id}',
                          button: true,
                          selected: icon == _icon,
                          // Read out by its name, and whether it's picked.
                          child: Semantics(
                            label: icon.label(l10n),
                            child: Material(
                              color: icon == _icon
                                  ? context.palette.pillBackground
                                  : theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: icon == _icon
                                      ? accent
                                      : theme.colorScheme.outlineVariant,
                                  width: icon == _icon ? 2 : 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _icon = icon),
                                child: SizedBox.square(
                                  dimension: 48,
                                  child: Icon(
                                    icon.icon,
                                    color: icon == _icon ? accent : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.errGeneric,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  TestId(
                    'category-save',
                    button: true,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: ButtonLabel(l10n.save),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
