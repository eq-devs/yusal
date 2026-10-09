import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/render3d/house_viewer.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'float_test_${sequence++}';
  HouseDocument initial() => createHouse(
      name: '浮层绘墙',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: '2026-10-01T00:00:00Z',
      newId: next);
  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  Offset point(WidgetTester t, double x, double y) {
    final painter = t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    return t.getTopLeft(canvas) + painter.point(x, y, t.getSize(canvas));
  }

  Future<({ProjectStore store, String id, MemoryFiles files})> mount(
      WidgetTester t, HouseDocument doc,
      {double scale = 1, bool reduce = false}) async {
    final files = MemoryFiles();
    // Use the same filesystem for preview isolation and persisted verification.
    final actual = ProjectStore(fileSystem: files),
        id = await actual.createProject(doc);
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduce),
            child: child!),
        home: HouseEditor(entry: ProjectEntry(id, doc), store: actual)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    return (store: actual, id: id, files: files);
  }

  Future<void> drag(
      WidgetTester t, double x0, double y0, double x1, double y1) async {
    final g = await t.startGesture(point(t, x0, y0));
    await g.moveTo(point(t, x1, y1));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
  }

  Future<void> saved(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
  }

  testWidgets(
      'wall mode shows fixed attachments and ignores unrelated blank taps',
      (t) async {
    final doc = initial(), session = await mount(t, doc);
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    FloorPlanPainter painter() =>
        t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    expect(painter().wallSeed, isNull);
    expect(painter().wallAttachments.length, 4);
    final nodes = List<Offset>.of(painter().wallAttachments);
    await t.tapAt(point(t, 4000, 4000));
    await saved(t);
    expect(painter().wallSeed, isNull);
    expect(painter().wallAttachments, nodes);
    expect(await session.store.openProject(session.id), doc);
    final attach = await t.startGesture(point(t, 6000, 0));
    await t.pump();
    expect(painter().wallSeed, const Offset(6000, 0),
        reason: 'outer attachment start');
    await attach.moveTo(point(t, 6000, 4000));
    await t.pump();
    await attach.up();
    await t.pumpAndSettle();
    await saved(t);
    final savedDoc = await session.store.openProject(session.id);
    expect(
        savedDoc.floors.first.wallOverrides.whereType<SolidWall>().length, 1);
    expect(painter().wallSeed, const Offset(6000, 4000));
    await drag(t, 6000, 4000, 8000, 4000);
    await saved(t);
    expect(
        (await session.store.openProject(session.id))
            .floors
            .first
            .wallOverrides
            .whereType<SolidWall>()
            .length,
        2);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'holding a wall opens context actions without saving or creating a wall',
      (t) async {
    final doc = initial(), session = await mount(t, doc);
    final g = await t.startGesture(point(t, 6000, 0));
    await t.pump(const Duration(milliseconds: 600));
    await g.up();
    await t.pumpAndSettle();
    expect(find.textContaining('外墙 12.00 米'), findsOneWidget,
        reason: 'the menu names the pressed wall and its length');
    expect(find.byTooltip('从这里接墙'), findsOneWidget);
    await t.tap(find.byTooltip('从这里接墙'));
    await t.pumpAndSettle();
    final painter = t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    expect(painter.wallSeed, const Offset(6000, 0));
    await saved(t);
    expect(await session.store.openProject(session.id), doc);
    expect(session.files.writeCount, 1);
  });
  testWidgets(
      'adjust mode exposes attachments while tapping still selects a wall',
      (t) async {
    final session = await mount(t, initial());
    await t.tap(find.byTooltip('调整分类'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('墙体调整'));
    await t.pumpAndSettle();
    expect(
        (t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter)
            .wallAttachments
            .length,
        4);
    await drag(t, 6000, 0, 6000, 4000);
    await saved(t);
    expect(
        (await session.store.openProject(session.id))
            .floors
            .first
            .wallOverrides
            .whereType<SolidWall>()
            .length,
        1);
    await t.tap(find.text('结束'));
    await t.pumpAndSettle();
    await t.tapAt(point(t, 6000, 2000));
    await t.pumpAndSettle();
    expect(find.byTooltip('删除墙体'), findsOneWidget);
    final g = await t.startGesture(point(t, 6000, 2000));
    await t.pump(const Duration(milliseconds: 600));
    await g.up();
    await t.pumpAndSettle();
    expect(find.byTooltip('调整长度'), findsOneWidget);
    expect(find.byTooltip('移动墙体'), findsOneWidget);
    expect(find.byTooltip('删除墙体'), findsOneWidget);
    await t.tap(find.byTooltip('修改墙厚'));
    await t.pumpAndSettle();
    expect(find.text('墙厚（米）'), findsOneWidget);
    await t.enterText(find.byType(TextField), '0.18');
    await t.tap(find.text('确定'));
    await saved(t);
    expect(
        (await session.store.openProject(session.id))
            .floors
            .first
            .wallOverrides
            .whereType<SolidWall>()
            .first
            .value,
        180);
  });
  testWidgets(
      'a moving finger cancels wall hold and a blank tap preserves the chosen attachment',
      (t) async {
    final session = await mount(t, initial());
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    // Tapping a plus selects its wall; the menu then sets the start point.
    await t.tapAt(point(t, 6000, 0));
    await t.pumpAndSettle();
    expect(
        (t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter).wallSeed,
        isNull);
    await t.tap(find.byTooltip('从这里接墙'));
    await t.pumpAndSettle();
    await t.tapAt(point(t, 3000, 5000));
    await t.pumpAndSettle();
    expect(
        (t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter).wallSeed,
        const Offset(6000, 0));
    final g = await t.startGesture(point(t, 6000, 0));
    await g.moveTo(point(t, 6000, 4000));
    await t.pump(const Duration(milliseconds: 650));
    expect(find.text('墙体操作'), findsNothing);
    await g.up();
    await saved(t);
    expect(
        (await session.store.openProject(session.id))
            .floors
            .first
            .wallOverrides
            .whereType<SolidWall>()
            .length,
        1);
  });
  testWidgets(
      'plus draws continuous walls, preview never saves, closure and undo are atomic',
      (t) async {
    final session = await mount(t, initial());
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('独立墙'));
    await t.pumpAndSettle();
    final g = await t.startGesture(point(t, 6000, 5000));
    await g.moveTo(point(t, 8000, 5000));
    await t.pump(const Duration(milliseconds: 1600));
    expect(session.files.writeCount, 1);
    expect(
        (await session.store.openProject(session.id))
            .floors
            .first
            .wallOverrides,
        isEmpty);
    await g.up();
    await t.pumpAndSettle();
    await drag(t, 8000, 5000, 8000, 8000);
    await drag(t, 8000, 8000, 6000, 8000);
    await saved(t);
    expect(
        (await session.store.openProject(session.id)).floors.first.rooms.length,
        1);
    await drag(t, 6000, 8000, 6000, 5000);
    await saved(t);
    var doc = await session.store.openProject(session.id);
    expect(doc.schemaVersion, 2);
    expect(doc.floors.first.wallOverrides.whereType<SolidWall>().length, 4);
    expect(doc.floors.first.rooms.length, 2);
    await t.tap(find.byTooltip('撤销'));
    await saved(t);
    doc = await session.store.openProject(session.id);
    expect(doc.floors.first.wallOverrides.whereType<SolidWall>().length, 3);
    expect(doc.floors.first.rooms.length, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'second pointer cancels wall preview without converting or saving the document',
      (t) async {
    final doc = initial(), session = await mount(t, doc);
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('独立墙'));
    await t.pumpAndSettle();
    final a = await t.startGesture(point(t, 6000, 5000), pointer: 1);
    await a.moveTo(point(t, 8000, 5000));
    await t.pump();
    final b = await t.startGesture(point(t, 3000, 3000), pointer: 2);
    await t.pump();
    await b.up();
    await a.up();
    await saved(t);
    expect(await session.store.openProject(session.id), doc);
    expect(session.files.writeCount, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'switching category during a stroke cancels the interrupted preview',
      (t) async {
    final doc = initial(), session = await mount(t, doc);
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('独立墙'));
    await t.pumpAndSettle();
    final g = await t.startGesture(point(t, 6000, 5000), pointer: 1);
    await g.moveTo(point(t, 8000, 5000));
    await t.pump();
    await t.tap(find.byTooltip('查看分类'));
    await t.pumpAndSettle();
    await g.up();
    await saved(t);
    expect(await session.store.openProject(session.id), doc);
    expect(session.files.writeCount, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('existing wall directly selects endpoint and middle handles',
      (t) async {
    final doc = initial();
    final result = executeCommand(
            extractDesignState(doc),
            DesignCommand('AddDrawnWall', {
              'floorId': doc.floors.first.id,
              'x0': 2000,
              'y0': 3000,
              'x1': 6000,
              'y1': 3000
            }),
            CommandContext(newId: next, now: () => '2026-10-01T00:00:00Z'))
        as Applied;
    final session = await mount(t, composeDocument(doc.meta, result.newState));
    await t.tapAt(point(t, 4000, 3000));
    await t.pumpAndSettle();
    expect(find.byTooltip('删除墙体'), findsOneWidget);
    await drag(t, 6000, 3000, 7000, 3000);
    await saved(t);
    var persisted = await session.store.openProject(session.id),
        axes = resolveFloorAxes(persisted, persisted.floors.first.id)!;
    var wall =
        persisted.floors.first.wallOverrides.whereType<SolidWall>().single;
    expect(resolveAnchor(axes, wall.anchor).chain!.endPos, 7000);
    // A mostly sideways drag of the body slides the wall along its line
    // only; it does not drift diagonally.
    await drag(t, 4500, 3000, 5500, 3500);
    await saved(t);
    persisted = await session.store.openProject(session.id);
    axes = resolveFloorAxes(persisted, persisted.floors.first.id)!;
    wall = persisted.floors.first.wallOverrides.whereType<SolidWall>().single;
    var chain = resolveAnchor(axes, wall.anchor).chain!;
    expect(chain.carrier.pos, 3000);
    expect(chain.startPos, 3000);
    expect(chain.endPos, 8000);
    // Dragging anywhere on the body across the wall moves it sideways.
    await drag(t, 7000, 3000, 7100, 4000);
    await saved(t);
    persisted = await session.store.openProject(session.id);
    axes = resolveFloorAxes(persisted, persisted.floors.first.id)!;
    wall = persisted.floors.first.wallOverrides.whereType<SolidWall>().single;
    chain = resolveAnchor(axes, wall.anchor).chain!;
    expect(chain.carrier.pos, 4000);
    expect(chain.startPos, 3000);
    expect(chain.endPos, 8000);
    expect(t.takeException(), isNull);
  });
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets(
        'floating categories and reduced motion fit $size with large text',
        (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await mount(t, initial(), scale: 1.8, reduce: true);
      expect(find.byTooltip('墙体'), findsOneWidget);
      for (final name in ['调整分类', '查看分类', '建造分类']) {
        await t.tap(find.byTooltip(name));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      expect(find.byType(AnimatedSize), findsNothing);
      expect(find.byType(AnimatedSwitcher), findsNothing);
    });
  }
  testWidgets(
      'wall drawing uses the transformed canvas coordinates after zoom and pan',
      (t) async {
    final session = await mount(t, initial());
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('独立墙'));
    await t.pumpAndSettle();
    final viewer = t.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final size = t.getSize(canvas);
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-size.width * 0.25, -size.height * 0.25, 0, 1)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    await t.pump();
    final painter = t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    final box = t.renderObject<RenderBox>(canvas);
    Offset target(double x, double y) =>
        box.localToGlobal(painter.point(x, y, size));
    final g = await t.startGesture(target(6000, 5000));
    await g.moveTo(target(8000, 5000));
    await t.pump();
    await g.up();
    await saved(t);
    final doc = await session.store.openProject(session.id);
    final wall = doc.floors.first.wallOverrides.whereType<SolidWall>().single;
    final axes = resolveFloorAxes(doc, doc.floors.first.id)!;
    final chain = resolveAnchor(axes, wall.anchor).chain!;
    expect(chain.carrier.pos, 5000);
    expect(chain.startPos, 6000);
    expect(chain.endPos, 8000);
    expect(t.takeException(), isNull);
  });
  testWidgets('fixed wall attachment remains hittable after zoom and pan',
      (t) async {
    final session = await mount(t, initial());
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    final viewer = t.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final size = t.getSize(canvas);
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-size.width * 0.25, -size.height * 0.25, 0, 1)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    await t.pump();
    final painter = t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    expect(painter.handleScale, 1.5);
    final box = t.renderObject<RenderBox>(canvas);
    Offset target(double x, double y) =>
        box.localToGlobal(painter.point(x, y, size));
    final g = await t.startGesture(target(0, 5000));
    await g.moveTo(target(3000, 5000));
    await t.pump();
    await g.up();
    await saved(t);
    final doc = await session.store.openProject(session.id);
    final wall = doc.floors.first.wallOverrides.whereType<SolidWall>().single;
    final chain =
        resolveAnchor(resolveFloorAxes(doc, doc.floors.first.id)!, wall.anchor)
            .chain!;
    expect(chain.carrier.pos, 5000);
    expect(chain.startPos, 0);
    expect(chain.endPos, 3000);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'view category reset reaches the 3D renderer and has one gesture hint',
      (t) async {
    await mount(t, initial());
    await t.tap(find.byTooltip('平面 / 3D'));
    await t.pumpAndSettle();
    expect(find.byTooltip('恢复画布视角'), findsOneWidget);
    expect(find.text('单指旋转 · 双指缩放和平移'), findsOneWidget);
    expect(t.widget<HouseViewer>(find.byType(HouseViewer)).resetToken, 0);
    await t.tap(find.byTooltip('恢复画布视角'));
    await t.pumpAndSettle();
    expect(t.widget<HouseViewer>(find.byType(HouseViewer)).resetToken, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('precise length offers a non-drag creation path', (t) async {
    final session = await mount(t, initial());
    expect(t.getSize(canvas), t.getSize(find.byType(SafeArea).first));
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('独立墙'));
    await t.pumpAndSettle();
    await t.tapAt(point(t, 6000, 5000));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('输入墙长'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1.25');
    await t.tap(find.text('向上'));
    await t.tap(find.text('增加墙'));
    await saved(t);
    final doc = await session.store.openProject(session.id),
        axes = resolveFloorAxes(doc, doc.floors.first.id)!;
    final wall = doc.floors.first.wallOverrides.whereType<SolidWall>().single,
        chain = resolveAnchor(axes, wall.anchor).chain!;
    expect(chain.carrier.dir, AxisDir.V);
    expect(chain.nominalLength, 1250);
    expect(chain.startPos, 5000);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'rapid category changes keep the latest mode and interrupt motion safely',
      (t) async {
    await mount(t, initial());
    for (var i = 0; i < 3; i++)
      for (final name in ['调整分类', '查看分类', '建造分类']) {
        await t.tap(find.byTooltip(name));
        await t.pump(const Duration(milliseconds: 20));
      }
    await t.pumpAndSettle();
    expect(find.byTooltip('墙体'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'phone-sized short wall chooses the nearest handle and does not snap back to itself',
      (t) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final doc = initial();
    final result = executeCommand(
            extractDesignState(doc),
            DesignCommand('AddDrawnWall', {
              'floorId': doc.floors.first.id,
              'x0': 6000,
              'y0': 5000,
              'x1': 8000,
              'y1': 5000
            }),
            CommandContext(newId: next, now: () => '2026-10-01T00:00:00Z'))
        as Applied;
    final session = await mount(t, composeDocument(doc.meta, result.newState));
    await t.tap(find.byTooltip('调整分类'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('墙体调整'));
    await t.pumpAndSettle();
    await t.tapAt(point(t, 7000, 5000));
    await t.pumpAndSettle();
    expect(find.byTooltip('删除墙体'), findsOneWidget);
    await drag(t, 7000, 5000, 7000, 4500);
    await saved(t);
    final persisted = await session.store.openProject(session.id),
        axes = resolveFloorAxes(persisted, persisted.floors.first.id)!;
    final wall =
        persisted.floors.first.wallOverrides.whereType<SolidWall>().single;
    final chain = resolveAnchor(axes, wall.anchor).chain!;
    expect(chain.carrier.pos, 4500);
    expect(chain.startPos, 6000);
    expect(chain.endPos, 8000);
    expect(t.takeException(), isNull);
  });
}
