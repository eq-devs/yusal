import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/design_commands.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'direct${sequence++}';
  HouseDocument house({int columns = 1, int rows = 1}) => createHouse(
      name: '直接操作测试',
      width: 12000,
      depth: 10000,
      columns: columns,
      rows: rows,
      initialRoom: columns == 1 && rows == 1,
      timestamp: '2026-09-30T00:00:00Z',
      newId: next);
  // Each test owns its immutable document and in-memory project storage.
  Future<({ProjectStore store, String id})> mount(
      WidgetTester tester, HouseDocument doc,
      {double textScale = 1}) async {
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    return (store: store, id: id);
  }

  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  Offset point(WidgetTester tester, double x, double y) =>
      tester.getTopLeft(canvas) +
      (tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter)
          .point(x, y, tester.getSize(canvas));
  Future<void> saved(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
  }

  HouseDocument doorHouse() {
    final doc = house();
    return executeDocumentCommand(
            doc,
            'AddOpening',
            {
              'floorId': doc.floors.first.id,
              'centerAtTap': true,
              'anchor': const BoundaryAnchor(
                  axisId: '@bottom', startAxisId: '@left', endAxisId: '@right'),
              'tapT': 6000,
              'kind': OpeningKind.door,
            },
            next)
        .document!;
  }

  testWidgets('existing door moves onto another wall and opens into the room',
      (tester) async {
    final session = await mount(tester, doorHouse());
    final gesture = await tester.startGesture(point(tester, 6000, 0));
    await gesture.moveTo(point(tester, 6000, 10000));
    await tester.pump();
    await gesture.up();
    await saved(tester);
    final opening = (await session.store.openProject(session.id))
        .floors
        .first
        .openings
        .single as DoorOpening;
    expect(opening.anchor.axisId, '@top');
    expect(opening.opensTo.name, 'negativeSide');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'dropping an existing door off the wall cancels the earlier valid preview',
      (tester) async {
    final original = doorHouse();
    final session = await mount(tester, original);
    final gesture = await tester.startGesture(point(tester, 6000, 0));
    await gesture.moveTo(point(tester, 7000, 0));
    await tester.pump();
    await gesture.moveTo(point(tester, 6000, 5000));
    await tester.pump();
    await gesture.up();
    await saved(tester);
    expect((await session.store.openProject(session.id)).floors.first.openings,
        original.floors.first.openings);
    expect(tester.takeException(), isNull);
  });
  testWidgets('second pointer cancels rectangle creation', (tester) async {
    final original = house();
    final session = await mount(tester, original);
    await tester.tap(find.byTooltip('拖动划房'));
    await tester.pumpAndSettle();
    final first = await tester.startGesture(point(tester, 0, 0), pointer: 1);
    await first.moveTo(point(tester, 3000, 4000));
    await tester.pump();
    final second =
        await tester.startGesture(point(tester, 8000, 5000), pointer: 2);
    await tester.pump();
    await second.up();
    await first.up();
    await saved(tester);
    final persisted = await session.store.openProject(session.id);
    expect(persisted.floors.first.rooms, original.floors.first.rooms);
    expect(persisted.axes, original.axes);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selected inner wall handle changes one local segment',
      (tester) async {
    var doc = house(columns: 2, rows: 2);
    for (var j = 0; j < 2; j++) {
      for (var i = 0; i < 2; i++)
        doc = paintCells(
            doc, doc.floors.first.id, [Cell(i, j)], RoomType.custom, next);
    }
    final session = await mount(tester, doc);
    await tester.tapAt(point(tester, 6000, 7500));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(point(tester, 6000, 7500));
    await gesture.moveTo(point(tester, 7000, 7500));
    await tester.pump();
    await gesture.up();
    await saved(tester);
    final persisted = await session.store.openProject(session.id);
    expect(persisted.axes.global, doc.axes.global);
    expect(persisted.axes.floor.single.pos, 7000);
    expect(tester.takeException(), isNull);
  });
  testWidgets('large text keeps all primary tools available', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, house(), textScale: 1.8);
    expect(find.byTooltip('拖入门'), findsOneWidget);
    expect(find.byTooltip('更多工具'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'door drop uses model coordinates after canvas zoom and translation',
      (tester) async {
    var doc = house(columns: 2);
    doc = paintCells(
        doc, doc.floors.first.id, [const Cell(0, 0)], RoomType.living, next);
    doc = paintCells(
        doc, doc.floors.first.id, [const Cell(1, 0)], RoomType.bedroom, next);
    final session = await mount(tester, doc);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final size = tester.getSize(canvas);
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-size.width * 0.25, -size.height * 0.25, 0, 1)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    await tester.pump();
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    final box = tester.renderObject<RenderBox>(canvas);
    final target = box.localToGlobal(painter.point(6000, 5000, size));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byTooltip('拖入门')));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    // The dragged door lands at its arrow tip, 28 px above the finger.
    await gesture.moveTo(target + const Offset(0, 28));
    await tester.pump();
    await gesture.up();
    await saved(tester);
    final opening = (await session.store.openProject(session.id))
        .floors
        .first
        .openings
        .single;
    expect(opening.anchor.axisId, doc.axes.global.single.id);
    expect((opening.position as FromStartPosition).d, 4550);
    expect(tester.takeException(), isNull);
  });
}
