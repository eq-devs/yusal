import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/messages.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/features/wall_snap.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/render2d/furniture_names.dart';
import 'package:yusal/storage/project_store.dart';

import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'fix_${sequence++}';
  final ctx = CommandContext(newId: next, now: () => '2026-11-17T00:00:00Z');
  HouseDocument house(
      {int width = 12000,
      int depth = 10000,
      List<List<int>> walls = const []}) {
    var doc = createHouse(
        name: '日常',
        width: width,
        depth: depth,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
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
          ctx);
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

  Future<(ProjectStore, String)> mount(
      WidgetTester t, HouseDocument doc) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = ProjectStore(fileSystem: MemoryFiles()),
        id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
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

  Future<void> pickStair(WidgetTester t) async {
    await t.tap(find.byTooltip('更多工具'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('楼梯'));
    await t.tap(find.text('楼梯'));
    await t.pumpAndSettle();
  }

  group('a wall that stops midway knows where the wall ahead is', () {
    test('the crossing wall ahead, in the heading it was drawn', () {
      final doc = house(walls: [
        [8000, 0, 8000, 10000]
      ]);
      final base = deriveFloorBase(doc, doc.floors.first.id);
      expect(wallAhead(base, const Offset(3000, 4000), const Offset(1, 0)),
          const Offset(8000, 4000));
      expect(wallAhead(base, const Offset(3000, 4000), const Offset(-1, 0)),
          const Offset(0, 4000));
      expect(wallAhead(base, const Offset(3000, 4000), const Offset(0, 1)),
          const Offset(3000, 10000));
      expect(wallAhead(base, const Offset(3000, 4000), const Offset(0, -1)),
          const Offset(3000, 0));
    });

    test('nothing ahead once it has arrived', () {
      final doc = house();
      final base = deriveFloorBase(doc, doc.floors.first.id);
      expect(wallAhead(base, const Offset(12000, 4000), const Offset(1, 0)),
          isNull);
    });
  });

  test('an overlap is said in words, never in ids', () {
    expect(
        coreMessage(
            '对象 ba55f0d0-3470-4a51-9d5e-1 与 3f7ac843-11aa-4c0e-8d1f-2 占用重叠'),
        '这里已经被占用了，换个位置试试。');
  });

  test('every room use has a name, a colour and a default size', () {
    for (final type in RoomType.values) {
      expect(roomNames[type], isNotNull, reason: '$type');
      expect(roomColors[type], isNotNull, reason: '$type');
      expect(roomTypeName(type), isNotEmpty, reason: '$type');
    }
    expect(RoomType.values.last, RoomType.custom);
    expect(roomNames[RoomType.hall], '门厅');
    expect(roomNames[RoomType.boiler], '锅炉房');
  });

  testWidgets('a stair on the only floor offers to add the floor above',
      (t) async {
    final session = await mount(
        t,
        house(walls: [
          [3000, 0, 3000, 10000]
        ]));
    await pickStair(t);
    await t.tapAt(point(t, 1500, 5000));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('楼梯要通到上面一层，现在还没有。'), findsOneWidget);
    await t.tap(find.text('加一层并放楼梯'));
    await t.pumpAndSettle();
    final doc = await saved(t, session);
    expect(doc.floors, hasLength(2));
    expect(doc.floors.first.stairs, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('a stair too long for the room becomes one that fits',
      (t) async {
    // 2.6 m wide and 3.7 m deep: a straight flight runs out of the room.
    var doc = house(walls: [
      [2600, 0, 2600, 10000],
      [0, 3700, 2600, 3700]
    ]);
    final added = executeCommand(extractDesignState(doc),
        DesignCommand('AddFloor', {'floorId': doc.floors.first.id}), ctx);
    doc = composeDocument(doc.meta, (added as Applied).newState);
    final session = await mount(t, doc);
    await pickStair(t);
    await t.tapAt(point(t, 1300, 1800));
    await t.pumpAndSettle();
    final after = await saved(t, session);
    final stairs = after.floors.first.stairs;
    expect(stairs, hasLength(1));
    expect(stairs.single.type, isNot(StairType.straight));
    final geometry = deriveHouse(after)
        .floors
        .first
        .stairs
        .firstWhere((s) => s.stairId == stairs.single.id);
    expect(geometry.fits, isTrue);
    // A second stair on the same spot is told so, in words.
    await pickStair(t);
    await t.tapAt(point(t, 1300, 1800));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('这里已经有楼梯了'), findsOneWidget);
    expect((await saved(t, session)).floors.first.stairs, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('a stair that fits nowhere in the room is not placed',
      (t) async {
    var doc = house(walls: [
      [1200, 0, 1200, 10000],
      [0, 1200, 1200, 1200]
    ]);
    final added = executeCommand(extractDesignState(doc),
        DesignCommand('AddFloor', {'floorId': doc.floors.first.id}), ctx);
    doc = composeDocument(doc.meta, (added as Applied).newState);
    final session = await mount(t, doc);
    await pickStair(t);
    await t.tapAt(point(t, 600, 600));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('这里放不下楼梯'), findsOneWidget);
    expect((await saved(t, session)).floors.first.stairs, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('the plan says how many problems the checks found', (t) async {
    // Two rooms and not one door between them.
    await mount(
        t,
        house(walls: [
          [5000, 0, 5000, 10000]
        ]));
    final badge = find.byKey(const Key('plan-issues'));
    expect(badge, findsOneWidget);
    expect(
        t
            .widget<Text>(
                find.descendant(of: badge, matching: find.byType(Text)))
            .data,
        matches(r'^问题 [1-9]\d*$'));
    // It leads to the list, where each finding says where it is.
    await t.tap(badge);
    await t.pumpAndSettle();
    expect(badge, findsNothing);
    expect(find.textContaining('一楼 · '), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
