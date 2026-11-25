import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _groups = {
  'draw': ['plan', 'site', 'iss'],
  'view': ['ext', 'walk'],
  'build': ['cost', 'qty', 'build', 'det', 'heat'],
};

/// Opens an editor page. On a phone the plan and the 3D view are the two
/// halves of the bottom switch, and every other page is in "more"; wide
/// screens open the page's group first when its button is not on screen
/// (the short-screen bar keeps all ten in one row).
Future<void> openTab(WidgetTester t, String key) async {
  final page = find.byKey(ValueKey('tab-$key'));
  if (page.evaluate().isNotEmpty) {
    await t.ensureVisible(page);
    await t.tap(page);
    return;
  }
  final group = find.byKey(ValueKey(
      'group-${_groups.entries.firstWhere((e) => e.value.contains(key)).key}'));
  if (group.evaluate().isNotEmpty) {
    await t.ensureVisible(group);
    await t.tap(group);
    await t.pumpAndSettle();
    await t.ensureVisible(page);
    await t.tap(page);
    return;
  }
  // The phone layout.
  if (key == 'plan' || key == 'ext') {
    final half = find.byKey(ValueKey(key == 'plan' ? 'quick-2d' : 'quick-3d'));
    if (half.evaluate().isEmpty) {
      // Another page is open over the drawing: back returns to the plan.
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      if (key == 'plan') return;
    }
    await t.tap(half);
    return;
  }
  await t.tap(find.byKey(const Key('editor-more')));
  await t.pumpAndSettle();
  await t.ensureVisible(page);
  await t.pumpAndSettle();
  await t.tap(page);
}

/// Opens the phone's "add" sheet, where the plan tools are; does nothing
/// where the tools sit in a row on the page.
Future<void> openAdd(WidgetTester t) async {
  final add = find.byKey(const Key('plan-add'));
  if (add.evaluate().isEmpty) return;
  await t.tap(add);
  await t.pumpAndSettle();
}
