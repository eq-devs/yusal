import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  Offset point(WidgetTester t, double x, double y) =>
      t.getTopLeft(canvas) +
      (t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter)
          .point(x, y, t.getSize(canvas));
  final loupe = find.byKey(const ValueKey('plan-loupe'));

  Future<void> mount(WidgetTester t) async {
    final doc = createHouse(
        name: '放大镜',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-10-08T00:00:00Z',
        newId: () => 'loupe_${sequence++}');
    final store = ProjectStore(fileSystem: MemoryFiles()),
        id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
  }

  testWidgets('a finger drawing a wall gets a magnifier; a mouse does not',
      (t) async {
    await mount(t);
    final g = await t.startGesture(point(t, 6000, 10000));
    await t.pump();
    expect(loupe, findsNothing, reason: 'not before the finger moves');
    await g.moveTo(point(t, 6000, 6000));
    await t.pump();
    expect(loupe, findsOneWidget);
    await g.up();
    await t.pumpAndSettle();
    expect(loupe, findsNothing);

    final m = await t.startGesture(point(t, 3000, 10000),
        kind: PointerDeviceKind.mouse);
    await m.moveTo(point(t, 3000, 6000));
    await t.pump();
    expect(loupe, findsNothing);
    await m.up();
    await t.pumpAndSettle();
  });
}
