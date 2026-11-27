import 'package:flutter/widgets.dart';

/// Gives a widget a stable accessibility id for Maestro (`id: <screen-element>`).
///
/// Ids are English, lowercase, hyphenated and never translated
/// (specs/r1-screens-and-copy.md). Widget tests find them with
/// `find.bySemanticsIdentifier`.
///
/// By default the id **merges** with the control below it (checkbox, button,
/// switch, text field), so the id node itself carries checked / enabled /
/// toggled and Maestro can assert them (Mobile Tester, #2). Use
/// [TestId.container] for screen-level ids that wrap many children.
class TestId extends StatelessWidget {
  const TestId(
    this.id, {
    super.key,
    required this.child,
    this.button,
    this.selected,
  }) : _merge = true;

  /// An id on a region (a screen, a slide, a summary) whose children keep
  /// their own nodes.
  const TestId.container(this.id, {super.key, required this.child})
    : button = null,
      selected = null,
      _merge = false;

  final String id;
  final Widget child;
  final bool? button;
  final bool? selected;
  final bool _merge;

  // Keyed by the id: when a slot changes id (welcome-next → welcome-start) the
  // node is rebuilt instead of updated, because Android's accessibility
  // bridge doesn't refresh a live node's resource-id (Mobile Tester, #2).
  @override
  // The key sits on the outermost widget: with MergeSemantics the merged node
  // belongs to it, so that is the one that must be replaced.
  Widget build(BuildContext context) {
    final key = ValueKey('semantics-id:$id');
    if (!_merge) {
      return Semantics(key: key, identifier: id, container: true, child: child);
    }
    return MergeSemantics(
      key: key,
      child: Semantics(
        identifier: id,
        button: button,
        selected: selected,
        child: child,
      ),
    );
  }
}
