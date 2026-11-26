import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// The three heights a [DockSheet] rests at, as on a map's sheet: just its
/// header, about half the page, and nearly all of it.
enum DockDetent { small, medium, large }

/// A sheet that never leaves the bottom of the page. It does not dim or
/// block what is behind it; it follows the finger when dragged and settles
/// on a spring at the nearest of its three [DockDetent]s, with a light
/// click. Whatever it shows ([header] and [body]) can change without the
/// sheet closing: the new content fades in and the sheet springs to its
/// new height.
///
/// The [header] always shows; the [body] is revealed as the sheet rises and
/// scrolls when it is taller than the room it has. At [DockDetent.small]
/// the body is offstage, so nothing in it can be tapped or found.
class DockSheet extends StatefulWidget {
  const DockSheet({
    super.key,
    required this.header,
    this.body,
    required this.detent,
    required this.onDetent,
    required this.maxHeight,
    required this.color,
    required this.gripColor,
    this.contentKey,
    this.gripKey,
    this.bottomPadding = 0,
    this.mediumFraction = 0.46,
    this.largeFraction = 0.88,
    this.reduceMotion = false,
    this.onHeight,
  });

  final Widget header;
  final Widget? body;
  final DockDetent detent;
  final ValueChanged<DockDetent> onDetent;

  /// The tallest the sheet may be: the room between the top bar and the
  /// bottom of the page.
  final double maxHeight;
  final Color color;
  final Color gripColor;

  /// A new value is new content: it cross-fades in, the sheet stays.
  final Object? contentKey;
  final Key? gripKey;

  /// Room under the content for the home indicator.
  final double bottomPadding;
  final double mediumFraction;
  final double largeFraction;
  final bool reduceMotion;

  /// The height the sheet is drawn at, every frame it changes.
  final ValueChanged<double>? onHeight;

  @override
  State<DockSheet> createState() => _DockSheetState();
}

class _DockSheetState extends State<DockSheet>
    with SingleTickerProviderStateMixin {
  static const _grip = 18.0;

  /// iOS's sheet spring: quick, no bounce to speak of.
  static const _spring =
      SpringDescription(mass: 1, stiffness: 520, damping: 46);

  late final AnimationController _c =
      AnimationController.unbounded(vsync: this)..addListener(_moved);

  double _header = 0;
  double _content = 0;
  bool _measured = false;
  bool _dragging = false;

  /// The detent the sheet is on its way to, or resting at.
  late DockDetent _target = widget.detent;

  double get _small => _grip + _header + widget.bottomPadding;

  double _heightOf(DockDetent d) {
    final small = _small;
    if (widget.body == null) return small;
    final all = small + _content;
    final cap = switch (d) {
      DockDetent.small => small,
      DockDetent.medium => widget.maxHeight * widget.mediumFraction,
      DockDetent.large => widget.maxHeight * widget.largeFraction,
    };
    return math.max(small, math.min(all, math.min(cap, widget.maxHeight)));
  }

  void _moved() {
    widget.onHeight?.call(_c.value);
    setState(() {});
  }

  void _settle(DockDetent to, {double velocity = 0}) {
    _target = to;
    final end = _heightOf(to);
    if (!_measured) return;
    if (widget.reduceMotion || !_c.value.isFinite) {
      _c.value = end;
      return;
    }
    if ((_c.value - end).abs() < 0.5 && velocity.abs() < 1) {
      _c.value = end;
      return;
    }
    _c.animateWith(SpringSimulation(_spring, _c.value, end, velocity));
  }

  void _measuredHeader(Object? key, double h) {
    if (key != widget.contentKey) return;
    if ((h - _header).abs() < 0.5 && _measured) return;
    _header = h;
    _remeasured();
  }

  void _measuredContent(Object? key, double h) {
    if (key != widget.contentKey) return;
    if ((h - _content).abs() < 0.5 && _measured) return;
    _content = h;
    _remeasured();
  }

  void _remeasured() {
    if (!_measured) {
      _measured = true;
      _c.value = _heightOf(_target);
      return;
    }
    if (!_dragging) _settle(_target);
  }

  @override
  void didUpdateWidget(DockSheet old) {
    super.didUpdateWidget(old);
    if (old.detent != widget.detent ||
        old.maxHeight != widget.maxHeight ||
        old.bottomPadding != widget.bottomPadding ||
        (old.body == null) != (widget.body == null)) {
      if (!_dragging) _settle(widget.detent);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _dragStart(DragStartDetails _) {
    _c.stop();
    setState(() => _dragging = true);
  }

  void _dragUpdate(DragUpdateDetails d) {
    final lo = _heightOf(DockDetent.small);
    final hi = _heightOf(DockDetent.large);
    var next = _c.value - d.delta.dy;
    // Past either end the sheet gives a little, like rubber.
    if (next < lo) next = _c.value - d.delta.dy * 0.3;
    if (next > hi) next = _c.value - d.delta.dy * 0.3;
    _c.value = next.clamp(lo - 40, hi + 40);
  }

  void _dragEnd(DragEndDetails d) {
    final v = -(d.primaryVelocity ?? 0); // up is positive
    final here = _c.value;
    const stops = DockDetent.values;
    DockDetent pick;
    if (v.abs() > 400) {
      // A fling goes on to the next stop that way.
      final ahead = stops
          .where((s) => v > 0
              ? _heightOf(s) > here + 1
              : _heightOf(s) < here - 1)
          .toList();
      pick = ahead.isEmpty
          ? (v > 0 ? DockDetent.large : DockDetent.small)
          : (v > 0 ? ahead.first : ahead.last);
    } else {
      pick = stops.reduce((a, b) =>
          (_heightOf(a) - here).abs() <= (_heightOf(b) - here).abs() ? a : b);
    }
    // Stops of the same height are one stop: rest on the one asked for
    // last, so a short card does not report "large" when it is medium.
    if (_heightOf(pick) == _heightOf(widget.detent)) pick = widget.detent;
    setState(() => _dragging = false);
    if (pick != widget.detent) {
      HapticFeedback.selectionClick();
      widget.onDetent(pick);
    }
    _settle(pick, velocity: v);
  }

  @override
  Widget build(BuildContext context) {
    // Before the first measure: about the height of a bar.
    final height =
        _measured ? _c.value : _grip + 50 + widget.bottomPadding;
    final small = _small;
    final resting = !_dragging && !_c.isAnimating;
    final hideBody = widget.body == null ||
        (resting && _target == DockDetent.small) ||
        (height <= small + 0.5 && resting);
    final drag = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _dragStart,
        onVerticalDragUpdate: _dragUpdate,
        onVerticalDragEnd: _dragEnd,
        onVerticalDragCancel: () {
          setState(() => _dragging = false);
          _settle(_target);
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // The grip: a tap steps between the small and the middle stop.
          GestureDetector(
              key: widget.gripKey,
              behavior: HitTestBehavior.opaque,
              onTap: widget.body == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      final to = widget.detent == DockDetent.small
                          ? DockDetent.medium
                          : DockDetent.small;
                      widget.onDetent(to);
                    },
              child: SizedBox(
                  height: _grip,
                  width: double.infinity,
                  child: Center(
                      child: Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                              color: widget.gripColor,
                              borderRadius: BorderRadius.circular(3)))))),
        ]));
    final content = _DockContent(
        key: ValueKey(widget.contentKey),
        contentKey: widget.contentKey,
        header: widget.header,
        body: widget.body,
        hideBody: hideBody,
        onHeader: _measuredHeader,
        onContent: _measuredContent,
        onDragStart: _dragStart,
        onDragUpdate: _dragUpdate,
        onDragEnd: _dragEnd);
    final switcher = AnimatedSwitcher(
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [
              for (final p in previous) Positioned.fill(child: p),
              if (current != null) current,
            ]),
        child: content);
    return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        // A Material, so the rows' ink shows on the sheet.
        child: Material(
            color: widget.color,
            child: SizedBox(
                height: height,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      drag,
                      Expanded(child: ClipRect(child: switcher)),
                      SizedBox(height: widget.bottomPadding),
                    ]))));
  }
}

class _DockContent extends StatelessWidget {
  const _DockContent(
      {super.key,
      required this.contentKey,
      required this.header,
      required this.body,
      required this.hideBody,
      required this.onHeader,
      required this.onContent,
      required this.onDragStart,
      required this.onDragUpdate,
      required this.onDragEnd});
  final Object? contentKey;
  final Widget header;
  final Widget? body;
  final bool hideBody;
  final void Function(Object?, double) onHeader;
  final void Function(Object?, double) onContent;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    // A drag on the header moves the sheet; the body keeps its scroll.
    final head = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: onDragStart,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: _SizeReport(
            onSize: (s) => onHeader(contentKey, s.height), child: header));
    final b = body;
    // The header at its own height, the body in what is left: while the
    // sheet is still on its way to a new height, the rest is clipped.
    return CustomMultiChildLayout(delegate: _DockLayout(), children: [
      LayoutId(id: #head, child: head),
      if (b != null)
        LayoutId(
            id: #body,
            child: Offstage(
                offstage: hideBody,
                child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (n) {
                      if (n.depth == 0) {
                        final m = n.metrics;
                        onContent(
                            contentKey, m.maxScrollExtent + m.viewportDimension);
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(), child: b)))),
    ]);
  }
}

class _DockLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final head = layoutChild(
        #head, BoxConstraints(minWidth: size.width, maxWidth: size.width));
    positionChild(#head, Offset.zero);
    if (hasChild(#body)) {
      layoutChild(
          #body,
          BoxConstraints.tightFor(
              width: size.width,
              height: math.max(0, size.height - head.height)));
      positionChild(#body, Offset(0, head.height));
    }
  }

  @override
  bool shouldRelayout(_DockLayout old) => false;
}

/// Tells [onSize] the size its child was laid out at, after the frame.
class _SizeReport extends SingleChildRenderObjectWidget {
  const _SizeReport({required this.onSize, super.child});
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReport(onSize);
  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport r) =>
      r.onSize = onSize;
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}
