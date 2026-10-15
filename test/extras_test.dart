import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/history/design_history.dart';

void main() {
  var sequence = 0;
  String next() => 'ex_${sequence++}';
  HouseDocument initial() => createHouse(
      name: '资料',
      width: 10000,
      depth: 13000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: '2026-10-01T00:00:00Z',
      newId: next);
  UndoableDesignState run(UndoableDesignState s, String kind,
      Map<String, dynamic> args) {
    final result = executeCommand(s, DesignCommand(kind, args),
        CommandContext(newId: next, now: () => '2026-10-01T00:00:00Z'));
    expect(result, isA<Applied>(),
        reason: result is Rejected ? result.message : '$kind');
    return (result as Applied).newState;
  }

  HouseDocument doc(UndoableDesignState s) => composeDocument(
      const Meta(
          name: '资料',
          createdAt: '2026-10-01T00:00:00Z',
          updatedAt: '2026-10-01T00:00:00Z'),
      s);

  test('documents without extras keep their schema version and bytes', () {
    final d = initial();
    expect(d.schemaVersion, 1);
    final text = encodeHouse(d);
    expect(text.contains('extras'), false);
    expect(loadHouse(utf8.encode(text)).document, d);
  });

  test('furniture round-trips through a version 3 file', () {
    var s = extractDesignState(initial());
    s = run(s, 'AddFurniture', {
      'floorId': s.floors.first.id,
      'kind': FurnitureKind.bed,
      'x': 1000,
      'y': 2000
    });
    s = run(s, 'SetRoomInfo',
        {'roomId': s.floors.first.rooms.first.id, 'note': '朝南', 'labelArea': 1700});
    s = run(s, 'SetFoundation', {'field': 'width', 'value': 500});
    s = run(s, 'AddIssue', {
      'title': '检查冻深',
      'level': IssueLevel.warn,
      'areas': [(0, 0, 10000, 400)]
    });
    final d = doc(s);
    expect(d.schemaVersion, 3);
    expect(validateHouse(d), isEmpty);
    final loaded = loadHouse(utf8.encode(encodeHouse(d)));
    expect(loaded.isSuccess, true,
        reason: loaded.failure?.errors.map((e) => e.message).join());
    expect(loaded.document, d);
    final item = loaded.document!.extras.furniture.single;
    expect((item.width, item.depth, item.height), (2000, 1600, 500));
    expect(loaded.document!.extras.foundation.width, 500);
    expect(loaded.document!.extras.issues.single.areas.single,
        (0, 0, 10000, 400));
  });

  test('geometry commands keep extras; removed rooms drop their notes', () {
    var s = extractDesignState(initial());
    final floor = s.floors.first.id, room = s.floors.first.rooms.first.id;
    s = run(s, 'AddFurniture',
        {'floorId': floor, 'kind': FurnitureKind.sofa, 'x': 500, 'y': 500});
    s = run(s, 'SetRoomInfo', {'roomId': room, 'note': '客厅'});
    s = run(s, 'AddDrawnWall',
        {'floorId': floor, 'x0': 0, 'y0': 6000, 'x1': 10000, 'y1': 6000});
    expect(s.extras.furniture, hasLength(1));
    s = run(s, 'AddFloor', {'floorId': floor});
    expect(s.extras.furniture, hasLength(1));
    final upper = s.floors.last.id;
    s = run(s, 'AddFurniture',
        {'floorId': upper, 'kind': FurnitureKind.table, 'x': 0, 'y': 0});
    expect(s.extras.furniture, hasLength(2));
    s = run(s, 'DeleteFloor', {'floorId': upper, 'deleteStairs': true});
    final d = doc(s);
    expect(d.extras.furniture, hasLength(1),
        reason: 'furniture on a deleted floor goes with it');
    expect(validateHouse(d), isEmpty);
  });

  test('furniture edits are undoable and invalid sizes are rejected', () {
    final start = initial();
    final history = DesignHistory(start);
    var s = extractDesignState(start);
    s = run(s, 'AddFurniture', {
      'floorId': s.floors.first.id,
      'kind': FurnitureKind.wardrobe,
      'x': 0,
      'y': 0
    });
    history.commit(doc(s));
    final id = s.extras.furniture.single.id;
    s = run(s, 'UpdateFurniture', {'furnitureId': id, 'x': 3000, 'y': 1000});
    history.commit(doc(s));
    s = run(s, 'RotateFurniture', {'furnitureId': id});
    expect((s.extras.furniture.single.width, s.extras.furniture.single.depth),
        (600, 1200));
    history.commit(doc(s));
    history.undo();
    expect(history.present.extras.furniture.single.x, 3000);
    history.undo();
    expect(history.present.extras.furniture.single.x, 0);
    history.undo();
    expect(history.present.extras.isEmpty, true);
    expect(history.present.schemaVersion, 1);
    final rejected = executeCommand(
        s,
        DesignCommand('UpdateFurniture', {'furnitureId': id, 'width': 0}),
        CommandContext(newId: next, now: () => ''));
    expect(rejected, isA<Rejected>());
  });

  test('extras with structural problems do not load', () {
    var s = extractDesignState(initial());
    s = run(s, 'AddFurniture', {
      'floorId': s.floors.first.id,
      'kind': FurnitureKind.bed,
      'x': 0,
      'y': 0
    });
    final raw = jsonDecode(encodeHouse(doc(s))) as Map<String, dynamic>;
    ((raw['extras'] as Map)['furniture'] as List).first['width'] = -5;
    expect(loadHouse(utf8.encode(jsonEncode(raw))).isSuccess, false);
    raw['schemaVersion'] = 2;
    ((raw['extras'] as Map)['furniture'] as List).first['width'] = 100;
    expect(loadHouse(utf8.encode(jsonEncode(raw))).isSuccess, false,
        reason: 'extras need version 3');
    (raw['extras'] as Map)['unknown'] = 1;
    raw['schemaVersion'] = 3;
    expect(loadHouse(utf8.encode(jsonEncode(raw))).isSuccess, false);
  });
}
