import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/cupertino.dart' show CupertinoPageTransition, CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cue/cue.dart' as cue;
import 'package:motor/motor.dart' as motor;

import 'motion_tokens.dart';

export 'motion_stack.dart';
export 'motion_tokens.dart';

/// Fades a row in and lifts it [Motion.rise] px into place, one step after
/// the row above: ANT's entrance, used by cards, list rows and sheets.
///
/// With [index] null the row takes its step from the nearest
/// [StaggerScope]: rows that arrive together (a page's first rows, a list
/// that just loaded, a sheet opening) rise in one after another; rows built
/// after the scope's first [Motion.burst] (scrolled into view, a kept tab
/// coming back) just appear. Without a scope a null-index row does not
/// move. A row inside another staggered row does not move either, so a
/// card's own rows do not rise twice. Rows past [Motion.staggerCap] and
/// anything under reduce motion appear at once.
class Stagger extends StatefulWidget {
  const Stagger({super.key, this.index, required this.child, this.rise = true});

  /// Position in the reveal; 0 starts right away. Null: from the scope.
  final int? index;
  final Widget child;

  /// False: fade only, for a block that already slides in with its sheet.
  final bool rise;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  // A motor spring per row, so a row caught mid-entrance just retargets.
  late final motor.SingleMotionController _c;
  Timer? _delay;
  bool _decided = false, _nested = false;

  @override
  void initState() {
    super.initState();
    _c = motor.SingleMotionController(
        motion: Motion.rowSpring, vsync: this, initialValue: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    _nested = context.getInheritedWidgetOfExactType<_InStagger>() != null;
    if (_nested || Motion.reduced(context)) return;
    final explicit = widget.index;
    final scope = context
        .getInheritedWidgetOfExactType<_StaggerScopeMarker>()
        ?.state;
    final int? step;
    if (scope == null || !scope.widget.enabled) {
      step = explicit;
    } else {
      final joined = scope._join();
      step = joined == null ? null : (explicit ?? joined);
    }
    if (step == null || step < 0 || step > Motion.staggerCap) return;
    _c.value = 0;
    final delay = Motion.staggerStep * step;
    if (delay == Duration.zero) {
      _c.animateTo(1);
    } else {
      _delay = Timer(delay, () {
        if (mounted) _c.animateTo(1);
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  // Always the same wrappers, so the row's own subtree (and its state) is
  // never rebuilt when the entrance starts or ends. At rest they are a
  // full opacity and a zero offset, which paint as nothing.
  @override
  Widget build(BuildContext context) {
    if (_nested) return widget.child;
    return _InStagger(
        child: AnimatedBuilder(
            animation: _c,
            child: widget.child,
            builder: (context, child) {
              final v = _c.value.clamp(0.0, 1.0);
              final rest = v >= 0.999;
              return Opacity(
                  alwaysIncludeSemantics: true,
                  opacity: rest ? 1 : v,
                  child: Transform.translate(
                      offset: Offset(0,
                          widget.rise && !rest ? Motion.rise * (1 - v) : 0),
                      child: child));
            }));
  }
}

class _InStagger extends InheritedWidget {
  const _InStagger({required super.child});
  @override
  bool updateShouldNotify(_InStagger oldWidget) => false;
}

/// Groups the rows of one page, tab or sheet for [Stagger]. Like
/// flutter_animate, an entrance plays once per mount: the scope's first
/// burst of rows rises in, and every row built after that just appears.
/// Every pushed page and every shell tab has one.
class StaggerScope extends StatefulWidget {
  const StaggerScope({super.key, this.enabled = true, required this.child});
  final bool enabled;
  final Widget child;

  /// True under an enabled scope (sheets, pages, tabs).
  static bool of(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<_StaggerScopeMarker>()
          ?.state
          .widget
          .enabled ??
      false;

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope> {
  DateTime? _burstStart;
  int _burstCount = 0;

  /// The step a newly built row plays at, or null to just appear.
  int? _join() {
    final now = DateTime.now();
    final start = _burstStart ??= now;
    if (now.difference(start) > Motion.burst) return null;
    return _burstCount++;
  }

  @override
  Widget build(BuildContext context) =>
      _StaggerScopeMarker(state: this, child: widget.child);
}

class _StaggerScopeMarker extends InheritedWidget {
  const _StaggerScopeMarker({required this.state, required super.child});
  final _StaggerScopeState state;
  @override
  bool updateShouldNotify(_StaggerScopeMarker oldWidget) => false;
}

/// The app's bottom sheet, with ANT's account-switcher feel: it settles up
/// on [Motion.settle], its content fades in behind it, list rows inside
/// rise in one by one, and opening it gives a light tap (pass
/// `haptic: false` for a sheet that opens on its own).
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
  bool haptic = true,
}) {
  final reduced = Motion.reduced(context);
  if (haptic) HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
      context: context,
      builder: (context) => StaggerScope(
          enabled: !reduced,
          child: Stagger(
              index: 0, rise: false, child: Builder(builder: builder))),
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

/// Cards shrink a touch under the finger ([Motion.pressScale]) and settle
/// back on release with a hint of spring, instead of a ripple. A quick tap
/// still shows the press briefly, so it never reads as missed; a touch
/// that turns into a scroll lets go at once. Not for full-width list rows.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key,
      this.enabled = true,
      this.scale = Motion.pressScale,
      required this.child});
  final bool enabled;
  final double scale;
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  Timer? _wait, _release;
  Offset? _origin;

  void _set(bool down) {
    if (mounted && down != _pressed) setState(() => _pressed = down);
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || Motion.reduced(context)) return;
    _release?.cancel();
    _origin = e.position;
    _wait?.cancel();
    // A short wait, so a finger that starts a scroll does not squeeze every
    // card it lands on.
    _wait = Timer(Motion.pressDelay, () => _set(true));
  }

  void _move(PointerMoveEvent e) {
    final o = _origin;
    if (o != null && (e.position - o).distance > kTouchSlop) _cancel();
  }

  void _up(PointerUpEvent e) {
    if (_origin == null) return;
    _origin = null;
    if (_wait?.isActive ?? false) {
      // A quick tap: still show the press, briefly.
      _wait!.cancel();
      _set(true);
      _release = Timer(Motion.press, () => _set(false));
    } else {
      _set(false);
    }
  }

  void _cancel([PointerEvent? _]) {
    _origin = null;
    _wait?.cancel();
    _set(false);
  }

  @override
  void dispose() {
    _wait?.cancel();
    _release?.cancel();
    super.dispose();
  }

  // A spring, not a timed tween: quick down, a snappy settle back, and a
  // press-release-press picks up from wherever the card is.
  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: motor.SingleMotionBuilder(
          motion: _pressed ? Motion.quickSpring : Motion.releaseSpring,
          value: _pressed ? widget.scale : 1.0,
          child: widget.child,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child)));
}

/// The app's press feedback in place of Material's ripple: the whole
/// control takes one even tint, nothing spreads out from the finger. The
/// tint comes up in [Motion.press], holds while the finger rests, and
/// fades in [Motion.fast] once it lifts. A quick tap still reaches the
/// full tint before fading, so it never reads as missed; a press that
/// turns into a scroll just fades from wherever it got to.
///
/// Set once as `ThemeData.splashFactory` (with a transparent
/// `highlightColor`, so the tint is not drawn twice); every [InkWell],
/// list tile and button then uses it. Cards keep [Pressable]'s scale and
/// no tint.
class PressTint extends InteractiveInkFeature {
  PressTint({
    required MaterialInkController controller,
    required super.referenceBox,
    required super.color,
    required TextDirection textDirection,
    bool containedInkWell = true,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    super.customBorder,
    double? radius,
    super.onRemoved,
  })  : _textDirection = textDirection,
        _contained = containedInkWell,
        _rect = rectCallback,
        _borderRadius = borderRadius ?? BorderRadius.zero,
        _radius = radius ?? Material.defaultSplashRadius,
        super(controller: controller) {
    _t = AnimationController(
        vsync: controller.vsync,
        duration: Motion.press,
        reverseDuration: Motion.fast)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_onStatus)
      ..forward();
    controller.addInkFeature(this);
  }

  static const InteractiveInkFeatureFactory splashFactory = _PressTintFactory();

  final TextDirection _textDirection;
  final bool _contained;
  final RectCallback? _rect;
  final BorderRadius _borderRadius;
  final double _radius;
  late final AnimationController _t;
  bool _released = false;

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && _released) _t.reverse();
    if (s == AnimationStatus.dismissed && _released) dispose();
  }

  /// The finger lifted on the control: finish coming up, then fade.
  @override
  void confirm() {
    if (_released) return;
    _released = true;
    if (_t.isCompleted) _t.reverse();
  }

  /// The press became a scroll or left the control: fade from here.
  @override
  void cancel() {
    if (_released) return;
    _released = true;
    _t.reverse();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final v = Curves.easeOut.transform(_t.value);
    if (v == 0) return;
    final paint = Paint()..color = color.withValues(alpha: color.a * v);
    canvas.save();
    canvas.transform(transform.storage);
    if (_contained) {
      final rect = _rect?.call() ?? Offset.zero & referenceBox.size;
      final border = customBorder;
      if (border != null) {
        canvas.drawPath(
            border.getOuterPath(rect, textDirection: _textDirection), paint);
      } else if (_borderRadius != BorderRadius.zero) {
        canvas.drawRRect(_borderRadius.toRRect(rect), paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    } else {
      // An unbounded response (a bare icon): a still disc behind it,
      // centred on the control, not on the finger.
      canvas.drawCircle(referenceBox.size.center(Offset.zero), _radius, paint);
    }
    canvas.restore();
  }
}

class _PressTintFactory extends InteractiveInkFeatureFactory {
  const _PressTintFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) =>
      PressTint(
          controller: controller,
          referenceBox: referenceBox,
          color: color,
          textDirection: textDirection,
          containedInkWell: containedInkWell,
          rectCallback: rectCallback,
          borderRadius: borderRadius,
          customBorder: customBorder,
          radius: radius,
          onRemoved: onRemoved);
}

/// The app's one bounce: when [active] turns true (saved), the child dips
/// to [Motion.popFrom] and a bouncy spring carries it past 1 and home.
/// Un-saving stays still. The caller adds `HapticFeedback.lightImpact()`.
class PopOnActive extends StatefulWidget {
  const PopOnActive({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<PopOnActive> createState() => _PopOnActiveState();
}

class _PopOnActiveState extends State<PopOnActive>
    with SingleTickerProviderStateMixin {
  late final motor.SingleMotionController _c = motor.SingleMotionController(
      motion: Motion.popSpring, vsync: this, initialValue: 1);

  @override
  void didUpdateWidget(PopOnActive old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !Motion.reduced(context)) {
      _c.value = Motion.popFrom;
      _c.animateTo(1);
    }
  }

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
          Transform.scale(scale: _c.value, child: child));
}

/// One control changing state (apply → applied): the new state fades in
/// from [Motion.switchScale] on cue's smooth spring, so it reads as an
/// answer. Key the child by its state:
/// `StateSwitcher(child: KeyedSubtree(key: ValueKey(state), child: ...))`.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.child, this.alignment});
  final Widget child;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return cue.Cue.onChange(
        value: child.key,
        skipFirstAnimation: true,
        motion: const cue.CueMotion.smooth(),
        acts: [
          const cue.OpacityAct.fadeIn(),
          cue.ScaleAct(
              from: Motion.switchScale,
              alignment: alignment ?? AlignmentDirectional.center),
        ],
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
      this.borderRadius = BorderRadius.zero,
      this.cropInFlight = true});
  final String heroKey;
  final BorderRadius borderRadius;
  final Widget child;

  /// True (photos): the flight shows this page's picture at its own size,
  /// cropped like `BoxFit.cover`. False (a drawing contained on its sheet):
  /// the picture is laid out at each frame's size, so it morphs exactly.
  final bool cropInFlight;
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
    final frame = _HeroFrame(
        radius: widget.borderRadius,
        crop: widget.cropInFlight,
        child: widget.child);
    final tag = _tag;
    return tag == null
        ? frame
        : Hero(tag: tag, flightShuttleBuilder: _shuttle, child: frame);
  }
}

class _HeroFrame extends StatelessWidget {
  const _HeroFrame(
      {required this.radius, required this.child, this.crop = true});
  final BorderRadius radius;
  final bool crop;
  final Widget child;
  @override
  Widget build(BuildContext context) => radius == BorderRadius.zero
      ? child
      : ClipRRect(borderRadius: radius, child: child);
}

/// Flies the detail page's picture, cropped like `BoxFit.cover`, so a 7:5
/// list cover and a wide detail photo morph without stretching; or, for a
/// target that asks not to be cropped, laid out at the flight's size.
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
  final picture = size == null || !dst.crop
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

/// One way into a page on every platform, as in ANT: the iOS slide with
/// its swipe back (Android's default zoom read as a different app). Each
/// page gets its own [StaggerScope], so its first rows rise in. Under
/// reduce motion the slide becomes a plain fade.
// Built on CupertinoRouteTransitionMixin rather than
// CupertinoPageTransitionsBuilder, which moved from material to cupertino
// between Flutter releases; the mixin's transition is the same one.
class MotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      CupertinoRouteTransitionMixin.kTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final page = StaggerScope(child: child);
    if (Motion.reduced(context)) {
      return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: page);
    }
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
        route, context, animation, secondaryAnimation, page);
  }
}

/// The page transitions to put in `ThemeData.pageTransitionsTheme`.
const motionPageTransitions = PageTransitionsTheme(builders: {
  TargetPlatform.android: MotionPageTransitionsBuilder(),
  TargetPlatform.iOS: MotionPageTransitionsBuilder(),
  TargetPlatform.macOS: MotionPageTransitionsBuilder(),
  TargetPlatform.linux: MotionPageTransitionsBuilder(),
  TargetPlatform.windows: MotionPageTransitionsBuilder(),
  TargetPlatform.fuchsia: MotionPageTransitionsBuilder(),
});
