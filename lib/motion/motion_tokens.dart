import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart' as motor;

/// Motion tokens, after the ANT Community app's motion: short, light,
/// decelerating, and only where something just happened. ANT is a little
/// livelier than the restrained kit it replaces: cards give more under the
/// finger and settle back with a hint of spring, rows rise further, and
/// lists that load rise in the same way as a page's first rows.
///
/// Rules (keep them when adding motion):
/// 1. Animate opacity, scale ([pressScale]–1.0) and at most [rise] px of
///    movement. Nothing else.
/// 2. Durations and springs come from these tokens; the timed curve is
///    [settle].
/// 3. Rows rise in one after another when a page, tab or sheet shows and
///    when a list loads: at most [staggerCap] steps, [staggerStep] apart.
///    Rows built after the first [burst] of a scope (scrolled into view, a
///    tab coming back) just appear.
/// 4. One thing performs at a time. Nothing loops except a skeleton's
///    breathing.
/// 5. Only the saved heart bounces ([popSpring]).
/// 6. With reduce motion on: no offsets, no scale, no shared-element
///    flights; only a short fade or a direct switch.
/// 7. Haptics confirm a choice (select, save, switch tab, open a sheet,
///    press a main button); they never decorate a scroll.
/// 8. No ripples. A pressed control takes one even tint ([PressTint]):
///    up in [press], down in [fast]. A pressed card shrinks to
///    [pressScale] instead. Nothing spreads out from the finger.
abstract final class Motion {
  /// A finger going down on a card; a quick tap's visible press.
  static const press = Duration(milliseconds: 100);

  /// Colour and small state changes.
  static const fast = Duration(milliseconds: 160);

  /// Half a skeleton's breath: full to faint.
  static const breath = Duration(milliseconds: 900);

  /// Skeleton → content.
  static const fadeIn = Duration(milliseconds: 200);

  /// A control changing state; a segment's thumb moving.
  static const base = Duration(milliseconds: 240);

  /// The save heart's bounce.
  static const pop = Duration(milliseconds: 280);

  /// Things arriving: sheets, rows, pages.
  static const enter = Duration(milliseconds: 320);

  /// Sheets leaving: faster than they came.
  static const exit = Duration(milliseconds: 220);

  /// Scrolling back to the top, the bar folding.
  static const slow = Duration(milliseconds: 420);

  /// Arrivals: quick start, long gentle settle (close to iOS's fluid
  /// curve).
  static const Curve settle = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Springs. [quickSpring] for a press going down, [releaseSpring] for it
  /// coming back (snappy, with a hint of bounce), [spring] for things
  /// arriving, [rowSpring] for each staggered row.
  static const motor.Motion quickSpring =
      motor.CupertinoMotion.smooth(duration: Duration(milliseconds: 180));
  static const motor.Motion releaseSpring =
      motor.CupertinoMotion.snappy(duration: Duration(milliseconds: 380));
  static const motor.Motion spring =
      motor.CupertinoMotion.smooth(duration: Duration(milliseconds: 420));
  static const motor.Motion rowSpring =
      motor.CupertinoMotion.smooth(duration: Duration(milliseconds: 420));

  /// The saved heart: dips to [popFrom], then a bouncy spring carries it
  /// past 1 and home.
  static const motor.Motion popSpring =
      motor.CupertinoMotion.bouncy(duration: Duration(milliseconds: 450));
  static const double popFrom = 0.82;

  /// Staggered reveal: step between rows, and how many steps there are.
  static const staggerStep = Duration(milliseconds: 30);
  static const staggerCap = 6;

  /// Rows built this close to a scope's first row rise in as one entrance.
  static const burst = Duration(milliseconds: 500);

  /// How far rows travel, in logical pixels.
  static const double rise = 10;

  /// Pressed cards shrink to this, after a short wait so a scroll that
  /// starts on a card does not squeeze it.
  static const double pressScale = 0.97;
  static const pressDelay = Duration(milliseconds: 60);

  /// Where a switching control starts.
  static const double switchScale = 0.94;

  /// Toasts: settle in, leave quicker.
  static const toastStyle = AnimationStyle(
      duration: base, reverseDuration: fast, curve: settle);

  /// Bottom sheets: settle in, leave quicker.
  static const sheetStyle = AnimationStyle(
      duration: enter,
      reverseDuration: exit,
      curve: settle,
      reverseCurve: Curves.easeInCubic);

  /// True when the system asks for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// A motor spring as a plain [Curve], for Flutter widgets that only take a
/// curve (sheets, toasts, page routes). Always lands exactly on 1.
class SpringCurve extends Curve {
  SpringCurve(motor.Motion motion) : _curve = motor.MotionCurve(motion: motion);
  final motor.MotionCurve _curve;
  @override
  double transformInternal(double t) => _curve.transform(t).clamp(0.0, 1.0);
}
