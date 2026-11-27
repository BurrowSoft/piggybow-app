import 'package:flutter/material.dart';

/// [showDialog] without the scrim in the semantics tree (T13, as the
/// safety card's #30 fix): TalkBack's first stop is the dialog's title, not
/// "Dismiss". A tap on the scrim still dismisses (when [barrierDismissible]),
/// and so do Back and the dialog's own buttons.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(
    _AppDialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    super.barrierColor,
    super.barrierDismissible,
    super.barrierLabel,
    super.themes,
  });

  @override
  bool get semanticsDismissible => false;
}

/// [showModalBottomSheet] the same way (T13): no scrim node and no drag
/// handle in the semantics tree, so TalkBack starts on the sheet's title.
/// A scrim tap, a swipe down and Back still close it.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context);
  return navigator.push<T>(
    _AppSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    ),
  );
}

class _AppSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AppSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
  }) : super(isScrollControlled: false);

  @override
  bool get semanticsDismissible => false;
}
