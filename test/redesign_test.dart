import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/editor/widgets/dock_sheet.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'storage_test.dart' show MemoryFiles;
import 'tabs.dart';

void main() {
  var sequence = 0;
  String next() => 're_${sequence++}';
  final ctx = CommandContext(newId: next, now: () => '2026-11-17T00:00:00Z');
  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final r =
        executeCommand(extractDesignState(doc), DesignCommand(kind, args), ctx);
    expect(r, isA<Applied>(), reason: '$kind: $r');
    return composeDocument(doc.meta, (r as Applied).newState);
  }

  HouseDocument house({List<List<int>> walls = const []}) {
    var doc = createHouse(
        name: '改版',
        width: 10000,
        depth: 12000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
        newId: next);
    for (final w in walls) {
      doc = run(doc, 'AddDrawnWall', {
        'floorId': doc.floors.first.id,
        'x0': w[0],
        'y0': w[1],
        'x1': w[2],
        'y1': w[3]
      });
    }
    return doc;
  }

  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  FloorPlanPainter painter(WidgetTester t) =>
      t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
  Offset point(WidgetTester t, double x, double y) =>
      t.getTopLeft(canvas) + painter(t).point(x, y, t.getSize(canvas));

  Future<(ProjectStore, String)> mount(
      WidgetTester t, HouseDocument doc) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: HouseEditor(entry: ProjectEntry(id, doc), store: store))));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
      await t.pumpAndSettle();
    });
    return (store, id);
  }

  Future<HouseDocument> saved(
      WidgetTester t, (ProjectStore, String) session) async {
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
    return session.$1.openProject(session.$2);
  }

  testWidgets('a tapped room shows a one-line card that leaves it in view',
      (t) async {
    await mount(
        t,
        house(walls: [
          [0, 5000, 10000, 5000]
        ]));
    // The lower room: the card rises over the bottom of the plan.
    await t.tapAt(point(t, 5000, 1500));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selection-grip')), findsOneWidget);
    expect(find.byKey(const Key('room-use')), findsOneWidget);
    expect(find.byKey(const Key('room-door')), findsOneWidget);
    // Folded: the list of uses is not on screen yet.
    expect(find.widgetWithText(ChoiceChip, '厨房'), findsNothing);
    final card = t.getRect(find.byType(DockSheet));
    expect(card.height, lessThan(160));
    // The room's centre is above the card.
    final p = painter(t);
    final size = t.getSize(canvas);
    final centre = t.getTopLeft(canvas) + p.point(5000, 2500, size);
    final shown = MatrixUtils.transformPoint(
        t
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value,
        centre - t.getTopLeft(canvas));
    expect(shown.dy + t.getTopLeft(canvas).dy, lessThan(card.top));
    // Asking for the uses unfolds it.
    await t.tap(find.byKey(const Key('room-use')));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '厨房'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a figure on the plan is typed over and the wall follows',
      (t) async {
    final session = await mount(
        t,
        house(walls: [
          [4000, 0, 4000, 12000]
        ]));
    final p = painter(t);
    final size = t.getSize(canvas);
    final spans = p.dimensionSpans(size);
    // The left room's clear width along the top.
    final span = spans.firstWhere((s) =>
        s.side == 'top' && !s.overall && s.a < 500 && s.b > 3000 && s.b < 4100);
    final before = span.length.round();
    await t.tapAt(t.getTopLeft(canvas) + span.label);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('dim-field')), findsOneWidget);
    await t.enterText(find.byKey(const Key('dim-field')), '5');
    await t.tap(find.byKey(const Key('dim-ok')));
    await t.pumpAndSettle();
    final doc = await saved(t, session);
    final base = deriveFloorBase(doc, doc.floors.first.id);
    final after = FloorPlanPainter(base, {}, {})
        .dimensionSpans(size)
        .firstWhere((s) =>
            s.side == 'top' && !s.overall && s.a < 500 && s.length > 1000);
    expect(after.length.round(), 5000);
    expect(before, isNot(5000));
    expect(deriveHouse(doc).floors.first.base.roomGeometry, hasLength(2));
    expect(t.takeException(), isNull);
  });

  testWidgets('a room of a set size is slid to a wall and put down', (t) async {
    final session = await mount(t, house());
    await openAdd(t);
    await t.tap(find.byTooltip('加房间'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-room-kitchen')));
    await t.pump();
    await t.tap(find.byKey(const Key('add-room-go')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stamp-place')), findsOneWidget);
    // Starts in the lower left corner; dragged by its middle to the
    // upper right, it stops against both outer walls.
    final g = await t.startGesture(point(t, 1500, 1800));
    await t.pump();
    for (final p in [
      [4000.0, 6000.0],
      [8000.0, 9800.0],
      [8600.0, 10300.0]
    ]) {
      await g.moveTo(point(t, p[0], p[1]));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    // Nothing is built until 放下.
    expect((await saved(t, session)).floors.single.rooms, hasLength(1));
    await t.tap(find.byKey(const Key('stamp-place')));
    await t.pumpAndSettle();
    final doc = await saved(t, session);
    final kitchen =
        doc.floors.single.rooms.singleWhere((r) => r.type == RoomType.kitchen);
    final axes = resolveFloorAxes(doc, doc.floors.single.id)!;
    final r = resolveRect(axes, kitchen.regions.single).rect!;
    expect((r.left, r.bottom, r.right, r.top), (7000, 8400, 10000, 12000));
    // Its folded card is up, ready for a door.
    expect(find.byKey(const Key('room-door')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a wall pulled from the middle of a wall slides along it first',
      (t) async {
    final session = await mount(t, house());
    await openAdd(t);
    await t.tap(find.byTooltip('墙体'));
    await t.pumpAndSettle();
    // Pressed on the top wall's middle, slid left to 4 m, then pulled down
    // to the opposite wall.
    final g = await t.startGesture(point(t, 5000, 12000));
    await t.pump();
    for (final p in [
      [4500.0, 11950.0],
      [4020.0, 11900.0],
      [4020.0, 9000.0],
      [4020.0, 3000.0],
      [4020.0, 60.0]
    ]) {
      await g.moveTo(point(t, p[0], p[1]));
      await t.pump(const Duration(milliseconds: 80));
    }
    await g.up();
    await t.pumpAndSettle();
    final doc = await saved(t, session);
    expect(doc.floors.single.rooms, hasLength(2));
    final base = deriveFloorBase(doc, doc.floors.single.id);
    expect(
        base.wallSegments.any((w) =>
            w.axis.dir == AxisDir.V &&
            w.axis.pos == 4000 &&
            w.start.pos == 0 &&
            w.end.pos == 12000),
        isTrue);
    expect(t.takeException(), isNull);
  });

  Future<void> pickStair(WidgetTester t) async {
    await openAdd(t);
    await t.tap(find.byKey(const ValueKey('add-stair')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a stair is put down like a thing, moved, and taken away',
      (t) async {
    final session = await mount(t, house());
    // One floor only: the stair first asks for the floor it leads to.
    await pickStair(t);
    expect(find.text('楼梯要通到上面一层，现在还没有。'), findsOneWidget);
    await t.tap(find.text('加一层并放楼梯'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stamp-place')), findsOneWidget);
    await t.tap(find.byKey(const Key('stamp-place')));
    await t.pumpAndSettle();
    var doc = await saved(t, session);
    expect(doc.floors, hasLength(2));
    final stair = doc.floors.first.stairs.single;
    expect(doc.floors.first.rooms, hasLength(1));
    var axes = resolveFloorAxes(doc, doc.floors.first.id)!;
    var r = resolveRect(axes, stair.region).rect!;
    expect((r.left, r.bottom, r.right, r.top), (0, 0, 2400, 3600));
    expect(deriveHouse(doc).floors.first.stairs.single.fits, isTrue);
    // Tapped, it offers to move; slid to the far corner and put down.
    ScaffoldMessenger.of(t.element(canvas)).clearSnackBars();
    await t.pumpAndSettle();
    await t.tapAt(point(t, 1200, 1800));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stair-move')));
    await t.pumpAndSettle();
    final g = await t.startGesture(point(t, 1200, 1800));
    await t.pump();
    for (final p in [
      [5000.0, 6000.0],
      [8600.0, 10000.0],
      [8800.0, 10200.0]
    ]) {
      await g.moveTo(point(t, p[0], p[1]));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stamp-place')));
    await t.pumpAndSettle();
    doc = await saved(t, session);
    axes = resolveFloorAxes(doc, doc.floors.first.id)!;
    r = resolveRect(axes, doc.floors.first.stairs.single.region).rect!;
    expect((r.left, r.bottom, r.right, r.top), (7600, 8400, 10000, 12000));
    expect([for (final a in axes.v) a.pos], [0, 7600, 10000]);
    // Deleted, the room is whole again.
    ScaffoldMessenger.of(t.element(canvas)).clearSnackBars();
    await t.pumpAndSettle();
    await t.tapAt(point(t, 8800, 10200));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stair-delete')));
    await t.pumpAndSettle();
    doc = await saved(t, session);
    expect(doc.floors.first.stairs, isEmpty);
    expect(doc.floors.first.rooms.single.regions, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('a floor is added by a button that says so, over the one below',
      (t) async {
    var doc = house(walls: [
      [0, 5000, 10000, 5000]
    ]);
    doc = run(doc, 'AddFloor', {'floorId': doc.floors.first.id});
    doc = run(doc, 'PlaceStair', {
      'floorId': doc.floors.first.id,
      'left': 0,
      'bottom': 0,
      'right': 2400,
      'top': 3600
    });
    final session = await mount(t, doc);
    expect(painter(t).below, isNull, reason: 'nothing under the ground floor');
    // The floors are behind the floor's name in the top bar.
    await t.tap(find.byKey(const Key('floor-pill')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-floor')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-floor-empty')));
    await t.pumpAndSettle();
    final after = await saved(t, session);
    expect(after.floors, hasLength(3));
    // Now on the new top floor, the one under it shows through.
    expect(painter(t).below, isNotNull);
    expect(painter(t).belowOpenings, isEmpty);
    // The second floor shows where the stair comes up.
    await t.tap(find.byKey(const Key('floor-pill')));
    await t.pumpAndSettle();
    await t.tap(find.text('二楼'));
    await t.pumpAndSettle();
    expect(painter(t).belowOpenings, hasLength(1));
    expect(
        painter(t).below!.wallSegments.any((w) => w.axis.pos == 5000), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'on a phone the plan and 3D are one tap apart, the other pages in more',
      (t) async {
    await mount(t, house());
    // The drawing has the page: no rows of tabs over it.
    expect(find.byKey(const ValueKey('tab-cost')), findsNothing);
    expect(find.byKey(const ValueKey('group-build')), findsNothing);
    await t.tap(find.byKey(const Key('editor-more')));
    await t.pumpAndSettle();
    for (final key in [
      'site', 'iss', 'walk', 'cost', 'qty', 'build', 'det', 'heat' //
    ]) {
      expect(find.byKey(ValueKey('tab-$key')), findsOneWidget, reason: key);
    }
    await t.tap(find.byKey(const ValueKey('tab-qty')));
    await t.pumpAndSettle();
    expect(canvas, findsNothing);
    expect(find.text('门窗与工程量'), findsOneWidget, reason: 'the page says what it is');
    // Back returns to the drawing, not out of the design.
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(canvas, findsOneWidget);
    await t.tap(find.byKey(const ValueKey('quick-3d')));
    await t.pumpAndSettle();
    expect(canvas, findsNothing);
    await t.tap(find.byKey(const ValueKey('quick-2d')));
    await t.pumpAndSettle();
    expect(canvas, findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
