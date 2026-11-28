import 'package:flutter/material.dart';

/// Tabs of the app shell, in order.
abstract final class ShellTab {
  static const explore = 0;
  static const houses = 1;
  static const messages = 2;
  static const me = 3;
}

/// Lets pages switch shell tabs (e.g. "＋ → design" opens My houses) and
/// open the design tool with its own drafting look.
class ShellNav extends InheritedWidget {
  const ShellNav(
      {super.key,
      required this.go,
      required this.drafting,
      required this.newDesign,
      required super.child});
  final void Function(int tab, {int? exploreSegment}) go;
  final ThemeData drafting;

  /// Opens My houses with the template picker for a new design.
  final VoidCallback newDesign;

  static ShellNav? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => false;
}
