import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('editor fits $size and renders 2D and 3D', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var sequence = 0;
      final doc = createHouse(
          name: '我的房屋',
          width: 12000,
          depth: 10000,
          columns: 3,
          rows: 2,
          timestamp: '2026-09-30T00:00:00Z',
          newId: () => 'id${sequence++}');
      final store = ProjectStore(fileSystem: MemoryFiles());
      await tester.pumpWidget(MaterialApp(
          home:
              HouseEditor(entry: ProjectEntry('project', doc), store: store)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('我的房屋'), findsOneWidget);
      await tester.tap(find.byTooltip('平面 / 3D'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('平面 / 3D'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设计检查'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有划分成房间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
      'committed paint saves after debounce and undo saves the restored state',
      (tester) async {
    var sequence = 0;
    final doc = createHouse(
        name: '保存测试',
        width: 12000,
        depth: 10000,
        columns: 3,
        rows: 2,
        timestamp: '2026-09-30T00:00:00Z',
        newId: () => 'id${sequence++}');
    final files = MemoryFiles();
    final store = ProjectStore(fileSystem: files);
    final id = await store.createProject(doc);
    await tester.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await tester.pumpAndSettle();
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    final paint =
        (tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter);
    final point = tester.getTopLeft(canvas) +
        paint.point(2000, 2000, tester.getSize(canvas));
    await tester.tapAt(point);
    await tester.pump();
    expect(files.writeCount, 1);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(files.writeCount, 1);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(files.writeCount, 2);
    expect((await store.openProject(id)).floors.first.rooms.length, 1);
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect((await store.openProject(id)).floors.first.rooms, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('axis drag previews are unsaved and commit as one undo step',
      (tester) async {
    var sequence = 0;
    final doc = createHouse(
        name: '拖动测试',
        width: 12000,
        depth: 10000,
        columns: 2,
        rows: 1,
        timestamp: '2026-09-30T00:00:00Z',
        newId: () => 'id${sequence++}');
    final files = MemoryFiles();
    final store = ProjectStore(fileSystem: files);
    final id = await store.createProject(doc);
    await tester.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网格'));
    await tester.pumpAndSettle();
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    final point = tester.getTopLeft(canvas) +
        painter.point(6000, 5000, tester.getSize(canvas));
    final gesture = await tester.startGesture(point);
    await gesture.moveTo(point + const Offset(25, 0));
    await tester.pump(const Duration(milliseconds: 1600));
    expect(files.writeCount, 1, reason: 'Preview must never reach storage');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect((await store.openProject(id)).axes.global.single.pos,
        greaterThan(6000));
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect((await store.openProject(id)).axes.global.single.pos, 6000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('second pointer cancels a grid preview without saving',
      (tester) async {
    var sequence = 0;
    final doc = createHouse(
        name: '取消测试',
        width: 12000,
        depth: 10000,
        columns: 2,
        rows: 1,
        timestamp: '2026-09-30T00:00:00Z',
        newId: () => 'id${sequence++}');
    final files = MemoryFiles();
    final store = ProjectStore(fileSystem: files);
    final id = await store.createProject(doc);
    await tester.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网格'));
    await tester.pumpAndSettle();
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    final point = tester.getTopLeft(canvas) +
        painter.point(6000, 5000, tester.getSize(canvas));
    final first = await tester.startGesture(point, pointer: 1);
    await first.moveTo(point + const Offset(25, 0));
    await tester.pump();
    final second =
        await tester.startGesture(point + const Offset(70, 0), pointer: 2);
    await tester.pump();
    await second.up();
    await first.up();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(files.writeCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
