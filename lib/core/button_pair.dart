import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Two buttons for one choice (decision 57): side by side at the end of the
/// line when both fit on it, [secondary] first; when they don't, stacked full
/// width, [primary] on top and [secondary] under it, [spacing] apart.
///
/// [OverflowBar] stacks too, but keeps each button its own width and the
/// children's order, so this lays the two out itself.
class ButtonPair extends MultiChildRenderObjectWidget {
  ButtonPair({
    super.key,
    required Widget secondary,
    required Widget primary,
    this.spacing = 8,
  }) : super(children: [secondary, primary]);

  final double spacing;

  @override
  RenderButtonPair createRenderObject(BuildContext context) => RenderButtonPair(
    spacing: spacing,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderButtonPair renderObject) {
    renderObject
      ..spacing = spacing
      ..textDirection = Directionality.of(context);
  }
}

class _PairParentData extends ContainerBoxParentData<RenderBox> {}

/// [ButtonPair]'s layout. The two fit on one line when their widest (one-line
/// labels) plus [spacing] is no wider than the line.
class RenderButtonPair extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PairParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PairParentData> {
  RenderButtonPair({
    required double spacing,
    required TextDirection textDirection,
  }) : _spacing = spacing,
       _textDirection = textDirection;

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

  /// Whether the last layout stacked the two.
  bool get stacked => _stacked;
  bool _stacked = false;

  RenderBox get _secondary => firstChild!;
  RenderBox get _primary => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PairParentData) {
      child.parentData = _PairParentData();
    }
  }

  /// Both side by side, each on one line.
  double get _rowWidth =>
      _secondary.getMaxIntrinsicWidth(double.infinity) +
      spacing +
      _primary.getMaxIntrinsicWidth(double.infinity);

  bool _stacks(double width) => width.isFinite && _rowWidth > width;

  void _checkTwo() {
    assert(childCount == 2, 'ButtonPair takes exactly two buttons');
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _checkTwo();
    return math.max(
      _secondary.getMinIntrinsicWidth(double.infinity),
      _primary.getMinIntrinsicWidth(double.infinity),
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _checkTwo();
    return _rowWidth;
  }

  double _height(double width, double Function(RenderBox, double) heightOf) {
    if (_stacks(width)) {
      return heightOf(_primary, width) + spacing + heightOf(_secondary, width);
    }
    return math.max(
      heightOf(_secondary, double.infinity),
      heightOf(_primary, double.infinity),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _checkTwo();
    return _height(width, (c, w) => c.getMinIntrinsicHeight(w));
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    _checkTwo();
    return _height(width, (c, w) => c.getMaxIntrinsicHeight(w));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  /// Lays the two out with [layoutChild] and returns the pair's size and
  /// each one's offset: (size, secondary, primary).
  (Size, Offset, Offset) _arrange(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final width = constraints.maxWidth;
    if (_stacks(width)) {
      final each = BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: constraints.maxHeight,
      );
      final p = layoutChild(_primary, each);
      final s = layoutChild(_secondary, each);
      final size = constraints.constrain(
        Size(width, p.height + spacing + s.height),
      );
      return (size, Offset(0, p.height + spacing), Offset.zero);
    }
    final loose = constraints.loosen();
    final s = layoutChild(_secondary, loose);
    final p = layoutChild(_primary, loose);
    final rowWidth = s.width + spacing + p.width;
    final height = math.max(s.height, p.height);
    final size = constraints.constrain(
      Size(width.isFinite ? width : rowWidth, height),
    );
    // At the end of the line: the right in left-to-right text, the left in
    // right-to-left, with the secondary nearer the start either way.
    final ltr = textDirection == TextDirection.ltr;
    final start = ltr ? size.width - rowWidth : 0.0;
    final sx = ltr ? start : start + p.width + spacing;
    final px = ltr ? start + s.width + spacing : start;
    return (
      size,
      Offset(sx, (height - s.height) / 2),
      Offset(px, (height - p.height) / 2),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _checkTwo();
    return _arrange(constraints, ChildLayoutHelper.dryLayoutChild).$1;
  }

  @override
  void performLayout() {
    _checkTwo();
    final (pair, secondary, primary) = _arrange(
      constraints,
      ChildLayoutHelper.layoutChild,
    );
    size = pair;
    _stacked = _stacks(constraints.maxWidth);
    (_secondary.parentData! as _PairParentData).offset = secondary;
    (_primary.parentData! as _PairParentData).offset = primary;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
