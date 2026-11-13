import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Fills the space it is given with [child], however big: the child is laid
/// out at the width (between [minWidth] and [maxWidth]) that gives it the
/// space's own proportions, then drawn as large as that space allows.
///
/// For a unit's page on a tablet. Scaling a phone layout into a big window
/// keeps the phone's proportions, so the window's spare height (or width)
/// becomes one empty band; measuring the real content and matching its shape
/// to the window first spreads every part across all of it. Touch, focus and
/// the screen reader's outlines follow the drawing, as through any transform.
class FitToSpace extends SingleChildRenderObjectWidget {
  const FitToSpace({super.key, required this.minWidth, required this.maxWidth, super.child});

  final double minWidth;
  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFitToSpace(minWidth, maxWidth);

  @override
  void updateRenderObject(BuildContext context, RenderFitToSpace renderObject) {
    renderObject
      ..minWidth = minWidth
      ..maxWidth = maxWidth;
  }
}

class RenderFitToSpace extends RenderProxyBox {
  RenderFitToSpace(this._minWidth, this._maxWidth);

  double _minWidth;
  double _maxWidth;
  Matrix4 _transform = Matrix4.identity();

  set minWidth(double v) {
    if (v == _minWidth) return;
    _minWidth = v;
    markNeedsLayout();
  }

  set maxWidth(double v) {
    if (v == _maxWidth) return;
    _maxWidth = v;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = child;
    if (c == null || size.isEmpty) return;
    double heightAt(double w) {
      c.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
      return c.size.height;
    }

    // The content's height barely depends on its width, so two or three
    // rounds settle the width whose proportions are the space's.
    var w = (_minWidth + _maxWidth) / 2;
    var h = heightAt(w);
    for (var i = 0; i < 3 && h > 0; i++) {
      final next = (h * size.width / size.height).clamp(_minWidth, _maxWidth);
      if ((next - w).abs() < 1) break;
      w = next;
      h = heightAt(w);
    }
    final scale = math.min(size.width / c.size.width, size.height / c.size.height);
    // Filled across with height to spare: the child is laid out once more
    // that much taller, so the spare height is its to share out (a Column
    // spacing its parts evenly) rather than an empty band above and below.
    if (size.height / scale > c.size.height + 0.5) {
      c.layout(BoxConstraints.tightFor(width: w, height: size.height / scale), parentUsesSize: true);
    }
    final dx = (size.width - c.size.width * scale) / 2;
    final dy = (size.height - c.size.height * scale) / 2;
    _transform = Matrix4.translationValues(dx, dy, 0)..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(c, offset),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => c.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_transform);
}
