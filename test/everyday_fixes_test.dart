import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/localization/messages.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/editor/util/wall_snap.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/engine/render2d/furniture_names.dart';
import 'package:yusal/service/storage/project_store.dart';

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

  Future<(ProjectStore, String)> mount(
      WidgetTester t, HouseDocument doc) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    return (store, id);
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
