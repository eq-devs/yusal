import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _groups = {
  'draw': ['plan', 'site', 'iss'],
  'view': ['ext', 'walk'],
  'build': ['cost', 'qty', 'build', 'det', 'heat'],
};

/// Opens an editor page: its group first when the page's own button is
/// not on screen (the short-screen bar keeps all ten in one row).
Future<void> openTab(WidgetTester t, String key) async {
  final page = find.byKey(ValueKey('tab-$key'));
  if (page.evaluate().isEmpty) {
    final group = _groups.entries.firstWhere((e) => e.value.contains(key)).key;
    await t.ensureVisible(find.byKey(ValueKey('group-$group')));
    await t.tap(find.byKey(ValueKey('group-$group')));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(page);
  await t.tap(page);
}
