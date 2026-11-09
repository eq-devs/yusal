import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/render3d/scene_view.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'ux_${sequence++}';
  HouseDocument initial({List<List<int>> walls = const []}) {
    var doc = createHouse(
        name: '体验',
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

  Future<void> mount(WidgetTester t, HouseDocument doc, {Size? size}) async {
    if (size != null) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }
    final store = ProjectStore(fileSystem: MemoryFiles()),
        id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
  }

  testWidgets('panning the plan moves the drawing without rebuilding it',
      (t) async {
    await mount(t, initial());
    final g = await t.startGesture(point(t, 3000, 3000));
    // Past the touch slop: the pan has started.
    for (var i = 1; i <= 3; i++) {
      await g.moveBy(const Offset(12, 8));
      await t.pump();
    }
    final before = painter(t);
    for (var i = 1; i <= 6; i++) {
      await g.moveBy(const Offset(12, 8));
      await t.pump();
    }
    expect(identical(painter(t), before), isTrue,
        reason: 'a pure pan keeps the same painter (no editor rebuild)');
    await g.up();
    await t.pump();
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('a wall end lined up with another wall shows a dashed guide',
      (t) async {
    await mount(t, initial(walls: [
      [3000, 7000, 3000, 10000]
    ]));
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    final g = await t.startGesture(point(t, 0, 5000));
    await g.moveTo(point(t, 1500, 5000));
    await t.pump();
    await g.moveTo(point(t, 3060, 5000));
    await t.pump();
    expect(painter(t).draftEnd, const Offset(3000, 5000));
    expect(painter(t).guides, [(const Offset(3000, 0), const Offset(3000, 10000))]);
    await g.moveTo(point(t, 4550, 5000));
    await t.pump();
    expect(painter(t).guides, isEmpty, reason: 'on the grid, not aligned');
    await g.up();
    await t.pumpAndSettle();
    expect(painter(t).guides, isEmpty);
  });

  testWidgets('phones show six tools; the rest open from 更多工具', (t) async {
    await mount(t, initial(), size: const Size(390, 844));
    for (final tip in ['墙体', '拖入门', '家具', '更多工具'])
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    expect(find.byTooltip('拖动划房'), findsNothing);
    await t.tap(find.byTooltip('更多工具'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('拖动划房'));
    await t.pumpAndSettle();
    expect(find.text('更多工具'), findsNothing, reason: 'the sheet closed');
    expect(find.byTooltip('拖动划房'), findsOneWidget,
        reason: 'the active tool shows in the row');
  });

  testWidgets('the phone 3D page gives the stage the screen and folds settings away',
      (t) async {
    await mount(t, initial(), size: const Size(390, 844));
    await t.ensureVisible(find.byKey(const ValueKey('tab-ext')));
    await t.tap(find.byKey(const ValueKey('tab-ext')));
    await t.pumpAndSettle();
    final stage = t.getSize(find.byType(SceneView));
    expect(stage.height, greaterThan(844 * 0.45));
    // The cut height only shows with the cut on.
    expect(find.byKey(const ValueKey('cut-height')), findsNothing);
    await t.tap(find.text('剖切'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cut-height')), findsOneWidget);
    // Sun and north live in a sheet.
    expect(find.text('日照时间'), findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('scene-more')));
    await t.tap(find.byKey(const ValueKey('scene-more')));
    await t.pumpAndSettle();
    expect(find.text('日照时间'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
