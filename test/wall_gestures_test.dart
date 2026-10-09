import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'gesture_${sequence++}';
  HouseDocument initial({List<List<int>> walls = const []}) {
    var doc = createHouse(
        name: '手势',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-10-08T00:00:00Z',
        newId: next);
    for (final w in walls) {
      final r = executeCommand(
          extractDesignState(doc),
          DesignCommand('AddDrawnWall', {
            'floorId': doc.floors.first.id,
            'x0': w[0],
            'y0': w[1],
            'x1': w[2],
            'y1': w[3]
          }),
          CommandContext(newId: next, now: () => '2026-10-08T00:00:00Z'));
      doc = composeDocument(doc.meta, (r as Applied).newState);
    }
    return doc;
  }

  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  FloorPlanPainter painter(WidgetTester t) =>
      t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
  Offset point(WidgetTester t, double x, double y) =>
      t.getTopLeft(canvas) + painter(t).point(x, y, t.getSize(canvas));

  Future<({ProjectStore store, String id, MemoryFiles files})> mount(
      WidgetTester t, HouseDocument doc) async {
    final files = MemoryFiles();
    final store = ProjectStore(fileSystem: files),
        id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    return (store: store, id: id, files: files);
  }

  Future<void> saved(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
  }

  Future<void> wallTool(WidgetTester t) async {
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
  }

  List<({int carrier, int lo, int hi, AxisDir dir})> walls(HouseDocument doc) {
    final axes = resolveFloorAxes(doc, doc.floors.first.id)!;
    return [
      for (final w in doc.floors.first.wallOverrides.whereType<SolidWall>())
        if (resolveAnchor(axes, w.anchor).chain case final c?)
          (
            carrier: c.carrier.pos,
            lo: c.startPos,
            hi: c.endPos,
            dir: c.carrier.dir
          )
    ];
  }

  testWidgets('a wall dropped near another wall joins it and says so',
      (t) async {
    final session = await mount(t, initial());
    await wallTool(t);
    expect(find.textContaining('按住绿色'), findsOneWidget,
        reason: 'first-wall guide in an empty house');
    final g = await t.startGesture(point(t, 6000, 10000));
    await g.moveTo(point(t, 6000, 5000));
    await t.pump();
    await g.moveTo(point(t, 6050, 300));
    await t.pump();
    expect(find.textContaining('已连到墙'), findsOneWidget);
    expect(painter(t).draftConnected, isTrue);
    await g.up();
    await saved(t);
    final doc = await session.store.openProject(session.id);
    expect(walls(doc), [(carrier: 6000, lo: 0, hi: 10000, dir: AxisDir.V)]);
    expect(doc.floors.first.rooms.length, 2);
    expect(painter(t).wallSeed, isNull,
        reason: 'a T on the outer wall cannot be continued');
    expect(find.textContaining('按住绿色'), findsNothing);
  });

  testWidgets('dragging empty space in the wall tool pans and builds nothing',
      (t) async {
    final doc = initial(), session = await mount(t, doc);
    await wallTool(t);
    final before = t
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .clone();
    final g = await t.startGesture(point(t, 3000, 4000));
    await g.moveBy(const Offset(-40, -30));
    await t.pump();
    await g.moveBy(const Offset(-20, -10));
    await t.pump();
    await g.up();
    await saved(t);
    final after = t
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    expect(
        after.getTranslation().x - before.getTranslation().x, closeTo(-60, 1));
    expect(
        after.getTranslation().y - before.getTranslation().y, closeTo(-40, 1));
    expect(await session.store.openProject(session.id), doc);
  });

  testWidgets('pressing a plus before dragging draws instead of opening a menu',
      (t) async {
    final session = await mount(t, initial());
    await wallTool(t);
    final g = await t.startGesture(point(t, 6000, 10000));
    await t.pump(const Duration(milliseconds: 700));
    expect(find.byTooltip('删除墙体'), findsNothing);
    expect(find.byTooltip('调整房屋长宽'), findsNothing);
    await g.moveTo(point(t, 6000, 6000));
    await t.pump();
    await g.up();
    await saved(t);
    expect(walls(await session.store.openProject(session.id)),
        [(carrier: 6000, lo: 6000, hi: 10000, dir: AxisDir.V)]);
  });

  testWidgets(
      'tapping a wall in the wall tool selects it nearby without leaving the tool',
      (t) async {
    await mount(
        t,
        initial(walls: [
          [6000, 0, 6000, 10000]
        ]));
    await wallTool(t);
    await t.tapAt(point(t, 6000, 3000));
    await t.pumpAndSettle();
    expect(find.byTooltip('删除墙体'), findsOneWidget);
    expect(find.textContaining('内墙 10.00 米'), findsOneWidget);
    expect(find.text('结束'), findsOneWidget, reason: 'still in the wall tool');
    expect(painter(t).editableWall, isNotNull);
    await t.tapAt(point(t, 3000, 5000));
    await t.pumpAndSettle();
    expect(find.byTooltip('删除墙体'), findsNothing);
    expect(painter(t).editableWall, isNull);
  });

  testWidgets('moving a selected wall keeps the wall that ends on it attached',
      (t) async {
    final session = await mount(
        t,
        initial(walls: [
          [6000, 0, 6000, 10000],
          [0, 5000, 6000, 5000]
        ]));
    await wallTool(t);
    await t.tapAt(point(t, 6000, 2500));
    await t.pumpAndSettle();
    final g = await t.startGesture(point(t, 6000, 2500));
    await g.moveTo(point(t, 7000, 2550));
    await t.pump();
    expect(find.textContaining('相连的墙会跟着伸缩'), findsOneWidget);
    await g.up();
    await saved(t);
    final doc = await session.store.openProject(session.id);
    expect(walls(doc).toSet(), {
      (carrier: 7000, lo: 0, hi: 10000, dir: AxisDir.V),
      (carrier: 5000, lo: 0, hi: 7000, dir: AxisDir.H)
    });
    expect(doc.floors.first.rooms.length, 3);
  });

  testWidgets('deleting from the menu can be undone from the message',
      (t) async {
    final doc = initial(walls: [
      [6000, 0, 6000, 10000]
    ]);
    final session = await mount(t, doc);
    await wallTool(t);
    await t.tapAt(point(t, 6000, 3000));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('删除墙体'));
    await t.pumpAndSettle();
    expect(find.text('已删除墙体'), findsOneWidget);
    await t.tap(find.text('撤销'));
    await saved(t);
    final restored = await session.store.openProject(session.id);
    expect(walls(restored), walls(doc));
    expect(find.text('已撤销上一步'), findsOneWidget);
  });

  testWidgets('undo drops a start point that no longer sits on a wall',
      (t) async {
    await mount(t, initial());
    await wallTool(t);
    final g = await t.startGesture(point(t, 6000, 10000));
    await g.moveTo(point(t, 6000, 6000));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(painter(t).wallSeed, const Offset(6000, 6000));
    await t.tap(find.byTooltip('撤销'));
    await t.pumpAndSettle();
    expect(painter(t).wallSeed, isNull);
  });

  testWidgets('keyboard: Ctrl+Z undoes and Esc leaves the wall tool',
      (t) async {
    final doc = initial(), session = await mount(t, doc);
    await wallTool(t);
    final g = await t.startGesture(point(t, 6000, 10000));
    await g.moveTo(point(t, 6000, 6000));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(walls(await session.store.openProject(session.id)), isEmpty,
        reason: 'not saved yet within the debounce');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await saved(t);
    final undone = await session.store.openProject(session.id);
    expect(undone.floors, doc.floors);
    expect(undone.axes, doc.axes);
    expect(find.text('结束'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('结束'), findsNothing);
  });

  testWidgets('a new floor becomes the floor being edited', (t) async {
    await mount(t, initial());
    await t.tap(find.byTooltip('楼层操作').first);
    await t.pumpAndSettle();
    await t.tap(find.text('新增空层'));
    await t.pumpAndSettle();
    expect(find.text('二楼'), findsOneWidget);
    expect(find.textContaining('现在编辑这一层'), findsOneWidget);
  });

  testWidgets('a failed save says so and keeps retrying until it works',
      (t) async {
    final session = await mount(t, initial());
    await wallTool(t);
    session.files.failWrites = true;
    final g = await t.startGesture(point(t, 6000, 10000));
    await g.moveTo(point(t, 6000, 6000));
    await t.pump();
    await g.up();
    await saved(t);
    expect(find.text('保存失败'), findsOneWidget);
    expect(find.textContaining('没能保存到本机'), findsOneWidget);
    session.files.failWrites = false;
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget);
    expect(walls(await session.store.openProject(session.id)),
        [(carrier: 6000, lo: 6000, hi: 10000, dir: AxisDir.V)]);
  });
}
