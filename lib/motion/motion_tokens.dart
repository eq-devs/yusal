import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart' as motor;

/// Restrained motion tokens. Motion only answers "what did you just
/// touch, and where are you now": short, light, decelerating, never
/// decorative.
///
/// Every curve comes from a critically damped motor spring, so things glide
/// to rest with no overshoot, and press feedback is a real spring that can
/// be interrupted mid-way. Values sit at the quiet end of the spec's ranges:
/// on a phone the top values read as too strong.
///
/// Rules:
/// 1. Animate only opacity, scale ([pressScale]–1.0) and offsets up to
///    [rise]. The spec allows 0.97 and 12px; we stay quieter.
/// 2. Durations and springs come from these tokens only.
/// 3. Staggered reveal only on a sheet or list's first appearance, at most
///    [staggerCap] rows, [staggerStep] apart. Rows loaded later just appear.
/// 4. One thing moves on a screen at a time.
/// 5. No loops, except a skeleton's breathing.
/// 6. One bounce in the whole app: confirming a save ([popScale]).
/// 7. With reduce motion on: no offsets, no scale, no shared-element
///    flights; only a short fade or a direct switch.
/// 8. Haptics only confirm something: a selection, a save, a successful
///    application, an account switch. Never decoration, never on open.
abstract final class Motion {
  /// A finger presses a card.
  static const press = Duration(milliseconds: 100);

  /// Color and small state changes.
  static const fast = Duration(milliseconds: 160);

  /// Half a skeleton's breath: full to faint.
  static const breath = Duration(milliseconds: 900);

  /// Skeleton → content.
  static const fadeIn = Duration(milliseconds: 200);

  /// A control's state switch.
  static const base = Duration(milliseconds: 220);

  /// The save heart's one hop.
  static const pop = Duration(milliseconds: 260);

  /// Sheets, rows and pages coming in.
  static const enter = Duration(milliseconds: 300);

  /// Sheets leaving: quicker than they came.
  static const exit = Duration(milliseconds: 200);

  /// Springs (no bounce). [quickSpring] for press and release, [spring]
  /// for things arriving.
  static const motor.Motion quickSpring =
      motor.CupertinoMotion.smooth(duration: Duration(milliseconds: 260));
  static const motor.Motion spring =
      motor.CupertinoMotion.smooth(duration: Duration(milliseconds: 420));

  /// Entry curve: a smooth spring's shape. Quick start, long soft finish.
  static final Curve settle = SpringCurve(const motor.CupertinoMotion.smooth(
      duration: Duration(milliseconds: 600)));

  /// Staggered reveal: step between rows, and how many rows take part.
  static const staggerStep = Duration(milliseconds: 30);
  static const staggerCap = 5;

  /// How far rows and pages travel, in logical pixels.
  static const double rise = 6;

  /// Pressed cards shrink to this, after a short wait so a scroll that
  /// starts on a card does not squeeze it.
  static const double pressScale = 0.985;
  static const pressDelay = Duration(milliseconds: 60);

  /// The save heart's peak; where a switching control starts.
  static const double popScale = 1.1;
  static const double switchScale = 0.98;

  /// Toasts: settle in, leave quicker.
  static final toastStyle =
      AnimationStyle(duration: enter, reverseDuration: exit, curve: settle);

  /// Bottom sheets: settle in, leave quicker.
  static final sheetStyle =
      AnimationStyle(duration: enter, reverseDuration: exit, curve: settle);

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
