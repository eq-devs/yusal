import 'package:flutter/material.dart';
import 'package:indexd_stack_dev/indexd_stack_dev.dart';

import 'motion_tokens.dart';

/// Every indexed page switch in the app (bottom tabs, segments, tab bars)
/// goes through this: a lazy [LazyLoadIndexedStack] that builds a page the
/// first time it is shown, keeps it alive afterwards, and switches with the
/// package's quiet `scaleIn` (fade plus a 0.992 ↔ 1 settle). Under reduce
/// motion it is a short plain fade.
class MotionIndexedStack extends StatefulWidget {
  const MotionIndexedStack(
      {super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<MotionIndexedStack> createState() => _MotionIndexedStackState();
}

class _MotionIndexedStackState extends State<MotionIndexedStack> {
  // Cache every page, as IndexedStack did: switching back keeps its scroll
  // and state.
  late final LazyStackController _controller = LazyStackController(
      initialIndex: widget.index, maxCachedPages: widget.children.length);

  @override
  void didUpdateWidget(MotionIndexedStack old) {
    super.didUpdateWidget(old);
    if (widget.index != _controller.currentIndex) {
      _controller.switchTo(widget.index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    // Opaque pages, so the outgoing one never ghosts through the incoming.
    // A Material (not a ColoredBox) so list tiles keep their ink.
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return LazyLoadIndexedStack(
        controller: _controller,
        animation:
            reduced ? IndexdAnimationType.fade : IndexdAnimationType.scaleIn,
        animationDuration: reduced ? Motion.fast : Motion.enter,
        paintOrder: IndexdPaintOrder.incomingOnTop,
        children: [
          for (final page in widget.children) Material(color: bg, child: page),
        ]);
  }
}

/// A [TabBarView] replacement driven by the tab bar's [TabController]
/// (or the nearest [DefaultTabController]), switching through
/// [MotionIndexedStack].
class MotionTabView extends StatefulWidget {
  const MotionTabView({super.key, this.controller, required this.children});
  final TabController? controller;
  final List<Widget> children;

  @override
  State<MotionTabView> createState() => _MotionTabViewState();
}

class _MotionTabViewState extends State<MotionTabView> {
  TabController? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(MotionTabView old) {
    super.didUpdateWidget(old);
    _bind();
  }

  void _bind() {
    final tabs = widget.controller ?? DefaultTabController.of(context);
    if (identical(tabs, _tabs)) return;
    _tabs?.removeListener(_changed);
    _tabs = tabs..addListener(_changed);
  }

  int _shown = -1;
  void _changed() {
    if (_tabs!.index != _shown) setState(() {});
  }

  @override
  void dispose() {
    _tabs?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _shown = _tabs!.index;
    return MotionIndexedStack(index: _shown, children: widget.children);
  }
}
