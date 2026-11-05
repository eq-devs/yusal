import 'package:flutter/widgets.dart';

/// Restrained motion tokens. Motion only answers "what did you just
/// touch, and where are you now": short, light, decelerating, never
/// decorative.
///
/// Rules:
/// 1. Animate only opacity, scale (0.97–1.0) and offsets up to [rise].
/// 2. Durations come from these tokens only.
/// 3. Staggered reveal only on a sheet or list's first appearance, at most
///    [staggerCap] rows, [staggerStep] apart. Rows loaded later just appear.
/// 4. One thing moves on a screen at a time.
/// 5. No loops, except a skeleton's breathing.
/// 6. One bounce in the whole app: confirming a save ([PopOnActive]).
/// 7. With reduce motion on: no offsets, no scale, no shared-element
///    flights; only a short fade or a direct switch.
/// 8. Haptics only confirm something: a selection, a save, a successful
///    application, an account switch. Never decoration.
abstract final class Motion {
  /// A finger presses a card.
  static const press = Duration(milliseconds: 100);

  /// Color and small state changes.
  static const fast = Duration(milliseconds: 160);

  /// Skeleton → content.
  static const fadeIn = Duration(milliseconds: 200);

  /// A control's state switch; a card springing back on release.
  static const base = Duration(milliseconds: 240);

  /// The save heart's one hop.
  static const pop = Duration(milliseconds: 280);

  /// Sheets, rows and pages coming in.
  static const enter = Duration(milliseconds: 320);

  /// Sheets leaving: quicker than they came.
  static const exit = Duration(milliseconds: 220);

  /// Entry curve: quick start, long soft finish.
  static const Curve settle = Cubic(0.22, 1, 0.36, 1);

  /// Staggered reveal: step between rows, and how many rows take part.
  static const staggerStep = Duration(milliseconds: 40);
  static const staggerCap = 6;

  /// How far rows and toasts travel, in logical pixels.
  static const double rise = 12;

  /// Pressed cards shrink to this, after a short wait so a scroll that
  /// starts on a card does not squeeze it.
  static const double pressScale = 0.97;
  static const pressDelay = Duration(milliseconds: 60);

  /// Toasts: settle in, leave quicker.
  static const toastStyle =
      AnimationStyle(duration: enter, reverseDuration: exit, curve: settle);

  /// Bottom sheets: settle in, leave quicker.
  static const sheetStyle =
      AnimationStyle(duration: enter, reverseDuration: exit, curve: settle);

  /// True when the system asks for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
