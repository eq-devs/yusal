import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cue/cue.dart' as cue;
import 'package:motor/motor.dart' as motor;

import 'motion_tokens.dart';

export 'motion_tokens.dart';

/// Fades a row in and lifts it [Motion.rise] px, [Motion.staggerStep] after
/// the row before it. Plays once, on first build. Rows past
/// [Motion.staggerCap] and anything under reduce motion appear at once.
class Stagger extends StatefulWidget {
  const Stagger({super.key, required this.index, required this.child});

  /// Position in the reveal; 0 starts right away.
  final int index;
  final Widget child;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _t;
  bool _decided = false, _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final i = widget.index;
    if (i < 0 || i > Motion.staggerCap || Motion.reduced(context)) {
      _done = true;
      return;
    }
    final delay = Motion.staggerStep * i;
    final total = delay + Motion.enter;
    final c = _controller = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(
        parent: c,
        curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1,
            curve: Motion.settle));
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    c.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
            opacity: _t.value,
            child: Transform.translate(
                offset: Offset(0, Motion.rise * (1 - _t.value)),
                child: child)));
  }
}

/// Marks a subtree (a sheet) whose list groups should reveal their rows
/// with [Stagger]. List groups ask [StaggerScope.of].
class StaggerScope extends InheritedWidget {
  const StaggerScope({super.key, this.enabled = true, required super.child});
  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StaggerScope>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(StaggerScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// [showModalBottomSheet] with the settle curve, a content fade, rows that
/// may stagger in. Opening a sheet is not a confirmation, so there is no
/// haptic unless a caller asks with `haptic: true`.
Future<T?> showMotionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
  bool haptic = false,
}) {
  final reduced = Motion.reduced(context);
  if (haptic) HapticFeedback.selectionClick();
  return showModalBottomSheet<T>(
      context: context,
      builder: (context) => StaggerScope(
          enabled: !reduced,
          child: _FadeInOnce(child: Builder(builder: builder))),
      backgroundColor: backgroundColor,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      // Reduce motion: no slide, the sheet is simply there.
      sheetAnimationStyle: sheetAnimationStyle ??
          (reduced ? AnimationStyle.noAnimation : Motion.sheetStyle),
      requestFocus: requestFocus);
}

/// Fades its child in once over [Motion.fadeIn].
class _FadeInOnce extends StatefulWidget {
  const _FadeInOnce({required this.child});
  final Widget child;
  @override
  State<_FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<_FadeInOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.fadeIn)..forward();
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) =>
          _c.isCompleted ? child! : Opacity(opacity: _t.value, child: child));
}

/// Shrinks a card to [Motion.pressScale] while a finger rests on it, and
/// springs it back on release. Not for full-width list rows.
class Pressable extends StatefulWidget {
  const Pressable({super.key, this.enabled = true, required this.child});
  final bool enabled;
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  Timer? _wait;
  Offset? _origin;

  void _down(PointerDownEvent e) {
    if (!widget.enabled || Motion.reduced(context)) return;
    _origin = e.position;
    _wait?.cancel();
    _wait = Timer(Motion.pressDelay, () {
      if (mounted) setState(() => _pressed = true);
    });
  }

  void _move(PointerMoveEvent e) {
    final o = _origin;
    if (o != null && (e.position - o).distance > kTouchSlop) _up();
  }

  void _up([PointerEvent? _]) {
    _origin = null;
    _wait?.cancel();
    _wait = null;
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  // A spring, not a timed tween: a quick press-release-press picks up
  // from wherever the card is, with its velocity.
  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: motor.SingleMotionBuilder(
          motion: Motion.quickSpring,
          value: _pressed ? Motion.pressScale : 1.0,
          child: widget.child,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child)));
}

/// The app's one bounce: when [active] turns true (saved), the child hops
/// 1 → [Motion.popScale] → 1 once. Un-saving stays still. The caller adds
/// `HapticFeedback.lightImpact()`.
class PopOnActive extends StatefulWidget {
  const PopOnActive({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<PopOnActive> createState() => _PopOnActiveState();
}

class _PopOnActiveState extends State<PopOnActive> {
  int _hops = 0;

  @override
  void didUpdateWidget(PopOnActive old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !Motion.reduced(context)) _hops++;
  }

  // Cue's keyframes: up quickly, then a smooth spring back to rest.
  @override
  Widget build(BuildContext context) => cue.Cue.onChange(
      value: _hops,
      skipFirstAnimation: true,
      acts: [
        cue.ScaleAct.keyframed(
            frames: cue.Keyframes<double>.fractional(const [
          cue.FKeyframe(1.0, at: 0),
          cue.FKeyframe(Motion.popScale, at: 0.35, curve: Curves.easeOut),
          cue.FKeyframe(1.0, at: 1, curve: Curves.easeOutCubic),
        ], duration: Motion.pop)),
      ],
      child: widget.child);
}

/// One control changing state (apply → applied): cross-fade with a
/// [Motion.switchScale] → 1 settle. Key the child by its state:
/// `StateSwitcher(child: KeyedSubtree(key: ValueKey(state), child: ...))`.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedSwitcher(
        duration: reduced ? Motion.fast : Motion.base,
        reverseDuration: Motion.fast,
        switchInCurve: Motion.settle,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: reduced
                ? child
                : ScaleTransition(
                    scale: Tween<double>(begin: Motion.switchScale, end: 1)
                        .animate(a),
                    child: child)),
        child: child);
  }
}

/// Skeleton → content: a [Motion.fadeIn] cross-fade, pinned to the top so
/// the page does not jump. Key both sides:
/// `FadeSwitcher(child: loading ? Skeleton(key: ValueKey('loading')) : ...)`.
class FadeSwitcher extends StatelessWidget {
  const FadeSwitcher({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
      duration: Motion.fadeIn,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      // Pass the parent's constraints through, so content lays out exactly
      // as it would without the fade.
      layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          fit: StackFit.passthrough,
          children: [...previous, if (current != null) current]),
      child: child);
}

/// Pending shared-element hand-offs: a source reserves its tag on touch,
/// the next detail page claims it. Unclaimed reservations go stale.
abstract final class _HeroBook {
  static const _ttl = Duration(seconds: 3);
  static final _pending = <String, (Object, DateTime)>{};

  static void reserve(String key, Object tag) =>
      _pending[key] = (tag, DateTime.now());

  /// Tags already claimed by a page, so a target that is rebuilt (a
  /// skeleton giving way to content) keeps the same tag for the flight back.
  static final _claimed = Expando<Map<String, Object>>();

  static Object? claim(String key, ModalRoute<Object?>? route) {
    final owned = route == null ? null : _claimed[route];
    if (owned != null && owned.containsKey(key)) return owned[key];
    final e = _pending.remove(key);
    if (e == null || DateTime.now().difference(e.$2) > _ttl) return null;
    if (route != null) (_claimed[route] ??= {})[key] = e.$1;
    return e.$1;
  }
}

/// A unique hero tag; identity is the point.
class _HeroTag {
  _HeroTag(this.key);
  final String key;
  @override
  String toString() => 'HeroTag($key)#${identityHashCode(this)}';
}

/// A list photo or avatar that can fly into a detail page's [HeroTarget]
/// with the same [heroKey]. Each source has its own tag, so the same item
/// twice on one screen (carousel and list) never collides.
class HeroSource extends StatefulWidget {
  const HeroSource(
      {super.key,
      required this.heroKey,
      required this.child,
      this.borderRadius = BorderRadius.zero});
  final String heroKey;
  final BorderRadius borderRadius;
  final Widget child;
  @override
  State<HeroSource> createState() => _HeroSourceState();
}

class _HeroSourceState extends State<HeroSource> {
  late final _tag = _HeroTag(widget.heroKey);
  _HeroTapAreaState? _area;

  void _reserve() => _HeroBook.reserve(widget.heroKey, _tag);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final area =
        context.dependOnInheritedWidgetOfExactType<_HeroTapAreaScope>()?.state;
    if (area != _area) {
      _area?._sources.remove(this);
      _area = area?.._sources.add(this);
    }
  }

  @override
  void dispose() {
    _area?._sources.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _HeroFrame(radius: widget.borderRadius, child: widget.child);
    if (Motion.reduced(context)) return frame;
    return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reserve(),
        child: Hero(tag: _tag, flightShuttleBuilder: _shuttle, child: frame));
  }
}

/// A whole card that opens a detail page: a touch anywhere on it, not only
/// on the picture, readies its [HeroSource]s to fly.
class HeroTapArea extends StatefulWidget {
  const HeroTapArea({super.key, required this.child});
  final Widget child;
  @override
  State<HeroTapArea> createState() => _HeroTapAreaState();
}

class _HeroTapAreaState extends State<HeroTapArea> {
  final _sources = <_HeroSourceState>{};

  @override
  Widget build(BuildContext context) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (Motion.reduced(context)) return;
        for (final s in _sources) {
          s._reserve();
        }
      },
      child: _HeroTapAreaScope(state: this, child: widget.child));
}

class _HeroTapAreaScope extends InheritedWidget {
  const _HeroTapAreaScope({required this.state, required super.child});
  final _HeroTapAreaState state;
  @override
  bool updateShouldNotify(_HeroTapAreaScope old) => state != old.state;
}

/// The detail page's end of a shared-element flight. Only flies when the
/// page was opened from a touched [HeroSource]; from a notification or a
/// deep link it simply appears.
class HeroTarget extends StatefulWidget {
  const HeroTarget(
      {super.key,
      required this.heroKey,
      required this.child,
      this.borderRadius = BorderRadius.zero});
  final String heroKey;
  final BorderRadius borderRadius;
  final Widget child;
  @override
  State<HeroTarget> createState() => _HeroTargetState();
}

class _HeroTargetState extends State<HeroTarget> {
  Object? _tag;
  bool _claimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_claimed) return;
    _claimed = true;
    final tag = _HeroBook.claim(widget.heroKey, ModalRoute.of(context));
    if (!Motion.reduced(context)) _tag = tag;
  }

  @override
  Widget build(BuildContext context) {
    final frame = _HeroFrame(radius: widget.borderRadius, child: widget.child);
    final tag = _tag;
    return tag == null
        ? frame
        : Hero(tag: tag, flightShuttleBuilder: _shuttle, child: frame);
  }
}

class _HeroFrame extends StatelessWidget {
  const _HeroFrame({required this.radius, required this.child});
  final BorderRadius radius;
  final Widget child;
  @override
  Widget build(BuildContext context) => radius == BorderRadius.zero
      ? child
      : ClipRRect(borderRadius: radius, child: child);
}

/// Flies the detail page's picture, cropped like `BoxFit.cover`, so a 7:5
/// list cover and a wide detail photo morph without stretching.
Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext) {
  final from = (fromContext.widget as Hero).child as _HeroFrame;
  final to = (toContext.widget as Hero).child as _HeroFrame;
  final push = direction == HeroFlightDirection.push;
  final (src, dst) = push ? (from, to) : (to, from);
  final box = (push ? toContext : fromContext).findRenderObject();
  final size = box is RenderBox && box.hasSize ? box.size : null;
  final picture = size == null
      ? dst.child
      : FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox.fromSize(size: size, child: dst.child));
  return AnimatedBuilder(
      animation: animation,
      child: picture,
      builder: (context, child) => ClipRRect(
          borderRadius:
              BorderRadius.lerp(src.radius, dst.radius, animation.value)!,
          child: child));
}

/// iOS and macOS: the native horizontal slide with swipe-back. Under
/// reduce motion it becomes a plain fade.
class MotionPageTransitionsBuilder extends CupertinoPageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (Motion.reduced(context)) {
      return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child);
    }
    return super
        .buildTransitions(route, context, animation, secondaryAnimation, child);
  }
}

/// Android and the rest: the new page fades in while drifting 12px from
/// the right on the spring curve; the page underneath stays still. The
/// full-width iOS slide with parallax felt too strong on Android, whose
/// system back gesture owns the screen edge anyway.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  static const double _shift = 12;

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final reduced = Motion.reduced(context);
    final t = CurvedAnimation(
        parent: animation, curve: Motion.settle, reverseCurve: Curves.easeIn);
    final faded = FadeTransition(opacity: t, child: child);
    if (reduced) return faded;
    return AnimatedBuilder(
        animation: t,
        child: faded,
        builder: (context, child) => t.value >= 1
            ? child!
            : Transform.translate(
                offset: Offset(_shift * (1 - t.value), 0), child: child));
  }
}

/// The page transitions to put in `ThemeData.pageTransitionsTheme`.
final motionPageTransitions = PageTransitionsTheme(builders: {
  for (final p in TargetPlatform.values)
    p: p == TargetPlatform.iOS || p == TargetPlatform.macOS
        ? const MotionPageTransitionsBuilder()
        : const SoftPageTransitionsBuilder(),
});
