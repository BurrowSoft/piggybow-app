import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Buttons for one choice, the main one last (decisions 57 and 71): side by
/// side at the end of the line, in [children]' order, when they all fit on
/// it; when they don't, stacked full width, the main one on top and the
/// others under it in reverse, [spacing] apart.
///
/// [OverflowBar] stacks too, but keeps each button its own width and the
/// children's order, so this lays them out itself.
class ButtonRow extends MultiChildRenderObjectWidget {
  const ButtonRow({super.key, required super.children, this.spacing = 8});

  final double spacing;

  @override
  RenderButtonRow createRenderObject(BuildContext context) => RenderButtonRow(
    spacing: spacing,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderButtonRow renderObject) {
    renderObject
      ..spacing = spacing
      ..textDirection = Directionality.of(context);
  }
}

/// Two buttons for one choice: [secondary] first on a line, [primary] on top
/// when stacked.
class ButtonPair extends ButtonRow {
  ButtonPair({
    super.key,
    required Widget secondary,
    required Widget primary,
    super.spacing,
  }) : super(children: [secondary, primary]);
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

/// [ButtonRow]'s layout. The buttons fit on one line when their widest (one
/// line labels) plus the spacing between them is no wider than the line.
class RenderButtonRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  RenderButtonRow({required this._spacing, required this._textDirection});

  double get spacing => _spacing;
  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Whether the last layout stacked them.
  bool get stacked => _stacked;
  bool _stacked = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
  }

  /// In [children]' order.
  List<RenderBox> get _buttons {
    final buttons = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      buttons.add(child);
      child = childAfter(child);
    }
    return buttons;
  }

  double get _gaps => childCount < 2 ? 0 : spacing * (childCount - 1);

  /// All side by side, each on one line.
  double get _rowWidth =>
      _buttons.fold(
        0.0,
        (width, b) => width + b.getMaxIntrinsicWidth(double.infinity),
      ) +
      _gaps;

  bool _stacks(double width) => width.isFinite && _rowWidth > width;

  @override
  double computeMinIntrinsicWidth(double height) => _buttons.fold(
    0.0,
    (width, b) => math.max(width, b.getMinIntrinsicWidth(double.infinity)),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _rowWidth;

  double _height(double width, double Function(RenderBox, double) heightOf) {
    if (_stacks(width)) {
      return _buttons.fold(0.0, (h, b) => h + heightOf(b, width)) + _gaps;
    }
    return _buttons.fold(
      0.0,
      (h, b) => math.max(h, heightOf(b, double.infinity)),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(width, (b, w) => b.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(width, (b, w) => b.getMaxIntrinsicHeight(w));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  /// Lays the buttons out with [layoutChild] and returns the row's size and
  /// each button's offset, in [children]' order.
  (Size, List<Offset>) _arrange(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final buttons = _buttons;
    if (buttons.isEmpty) return (constraints.smallest, const []);
    final width = constraints.maxWidth;
    final offsets = List<Offset>.filled(buttons.length, Offset.zero);
    if (_stacks(width)) {
      final each = BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: constraints.maxHeight,
      );
      // The main one (the last) on top, then the others in reverse.
      var y = 0.0;
      for (var i = buttons.length - 1; i >= 0; i--) {
        offsets[i] = Offset(0, y);
        y += layoutChild(buttons[i], each).height + spacing;
      }
      return (constraints.constrain(Size(width, y - spacing)), offsets);
    }
    final loose = constraints.loosen();
    final sizes = [for (final b in buttons) layoutChild(b, loose)];
    final rowWidth = sizes.fold(0.0, (w, s) => w + s.width) + _gaps;
    final height = sizes.fold(0.0, (h, s) => math.max(h, s.height));
    final size = constraints.constrain(
      Size(width.isFinite ? width : rowWidth, height),
    );
    // At the end of the line: the right in left-to-right text, the left in
    // right-to-left, with the first button nearest the start either way.
    final ltr = textDirection == TextDirection.ltr;
    var x = ltr ? size.width - rowWidth : rowWidth;
    for (var i = 0; i < buttons.length; i++) {
      final s = sizes[i];
      final dy = (height - s.height) / 2;
      if (ltr) {
        offsets[i] = Offset(x, dy);
        x += s.width + spacing;
      } else {
        x -= s.width;
        offsets[i] = Offset(x, dy);
        x -= spacing;
      }
    }
    return (size, offsets);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, ChildLayoutHelper.dryLayoutChild).$1;

  @override
  void performLayout() {
    final (row, offsets) = _arrange(constraints, ChildLayoutHelper.layoutChild);
    size = row;
    _stacked = childCount > 0 && _stacks(constraints.maxWidth);
    final buttons = _buttons;
    for (var i = 0; i < buttons.length; i++) {
      (buttons[i].parentData! as _RowParentData).offset = offsets[i];
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
