import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/house_templates.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'storage_test.dart' show MemoryFiles;

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('the plan shows what the house would cost at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var n = 0;
      final doc =
          createTemplate('three', '2026-11-15T00:00:00Z', () => 'id${n++}');
      await t.pumpWidget(MaterialApp(
          home: HouseEditor(
              entry: ProjectEntry('project', doc),
              store: ProjectStore(fileSystem: MemoryFiles()))));
      await t.pumpAndSettle();
      final chip = find.byKey(const Key('plan-cost'));
      expect(chip, findsOneWidget);
      expect(
          t
              .widget<Text>(
                  find.descendant(of: chip, matching: find.byType(Text)))
              .data,
          matches(r'^≈ \S+ [\d,]+( 万)?$'));
      expect(t.takeException(), isNull);
      // It leads to the budget page.
      await t.tap(chip);
      await t.pumpAndSettle();
      expect(chip, findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
  }
}
