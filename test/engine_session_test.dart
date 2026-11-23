import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/checks/rule_catalog.dart';
import 'package:yusal/features/editor/engine/core/commands/object_catalog.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/session/engine_session.dart';

import 'perf/engine_bench.dart';

void main() {
  EngineSession open() {
    var n = 0;
    return EngineSession(composeDocument(benchMeta, typicalPlan()),
        newId: () => 'new-${n++}', now: () => '2026-01-01T00:00:00Z');
  }

  test('a command is carried out, kept in history and undone', () {
    final s = open();
    final floor = s.document.floors.first;
    final before = encodeHouse(s.document);
    final pieces = s.document.extras.furniture.length;
    final r = s.apply('AddFurniture',
        {'floorId': floor.id, 'kind': 'bed', 'x': 500, 'y': 500});
    expect(r.ok, isTrue);
    expect(r.code, 'OK');
    expect(r.created, hasLength(1));
    expect(s.document.extras.furniture.map((f) => f.id),
        contains(r.created.single));
    expect(s.canUndo, isTrue);

    final gone = s.apply('DeleteFurniture', {'furnitureId': r.created.single});
    expect(gone.removed, r.created);

    expect(s.undo(), isTrue);
    expect(s.undo(), isTrue);
    expect(s.undo(), isFalse);
    expect(encodeHouse(s.document), before);
    expect(s.redo(), isTrue);
    expect(s.document.extras.furniture, hasLength(pieces + 1));
  });

  test('a preview answers without changing the house', () {
    final s = open();
    final room = s.document.floors.first.rooms.first;
    final before = s.document;
    final r = s.preview('RenameRoom', {'roomId': room.id, 'value': 'Study'});
    expect(r.ok, isTrue);
    expect(r.document!.floors.first.rooms.first.name, 'Study');
    expect(identical(s.document, before), isTrue);
    expect(s.canUndo, isFalse);
  });

  test('a refusal says why and changes nothing', () {
    final s = open();
    final floor = s.document.floors.first;
    final r = s.apply('SetFloorHeight', {'floorId': floor.id, 'value': 500});
    expect(r.ok, isFalse);
    expect(r.code, 'INVALID_VALUE');
    expect(r.message, isNotEmpty);
    expect(s.canUndo, isFalse);
    expect(s.apply('Fly', {}).code, 'UNKNOWN_COMMAND');
    expect(s.apply('RenameFloor', {'floorId': floor.id}).code, 'BAD_ARGUMENT');
  });

  test('a command that needs a choice says which', () {
    final s = open();
    final floors = s.document.floors;
    // A stair on the floor below the top one stands in the way.
    final top = floors.last;
    final below = floors[floors.length - 2];
    if (below.stairs.isEmpty) return;
    final r = s.apply('DeleteFloor', {'floorId': top.id});
    expect(r.code, 'NEEDS_RESOLUTION');
    expect(r.choices, ['deleteStairs']);
    expect(s.apply('DeleteFloor', {'floorId': top.id, 'deleteStairs': true}).ok,
        isTrue);
  });

  test('a transaction is one step, and all or nothing', () {
    final s = open();
    final floor = s.document.floors.first;
    final rooms = floor.rooms;
    final before = s.document;

    final failed = s.transaction([
      ('RenameRoom', {'roomId': rooms[0].id, 'value': 'One'}),
      ('RenameRoom', {'roomId': 'nowhere', 'value': 'Two'}),
    ]);
    expect(failed.ok, isFalse);
    expect(failed.code, 'NOT_FOUND');
    expect(failed.message, startsWith('command 2 (RenameRoom)'));
    expect(identical(s.document, before), isTrue);

    final done = s.transaction([
      ('RenameRoom', {'roomId': rooms[0].id, 'value': 'One'}),
      ('RenameRoom', {'roomId': rooms[1].id, 'value': 'Two'}),
      ('AddFurniture', {'floorId': floor.id, 'kind': 'table'}),
    ]);
    expect(done.ok, isTrue);
    expect(done.created, hasLength(1));
    expect(s.document.floors.first.rooms.take(2).map((r) => r.name),
        ['One', 'Two']);
    expect(s.undo(), isTrue);
    expect(s.canUndo, isFalse);
    expect(encodeHouse(s.document), encodeHouse(before));
  });

  test('the house is described in plain values', () {
    final s = open();
    final d = s.describe();
    // Plain enough to be sent as text.
    final back = jsonDecode(jsonEncode(d)) as Map;
    expect(back['footprint']['width'], s.document.footprint.width);
    final floor = (back['floors'] as List).first as Map;
    expect(
        (floor['rooms'] as List).length, s.document.floors.first.rooms.length);
    expect(((floor['rooms'] as List).first as Map)['area'], greaterThan(0));
    expect((floor['axes'] as Map)['V'], isNotEmpty);
    // What it names can be used in a command as it is.
    final opening = (floor['openings'] as List).first as Map;
    expect(
        s.preview('MoveOpening', {
          'openingId': opening['id'],
          'anchor': opening['anchor'],
          'position': {'type': 'center'}
        }).ok,
        isTrue);
  });

  test('checks and cost are answered for the house as it stands', () {
    final s = open();
    final known = {for (final r in ruleCatalog) r.id};
    final checks = s.check();
    jsonEncode(checks);
    for (final c in checks) {
      expect(known, contains(c['ruleId']));
    }
    final cost = s.cost();
    jsonEncode(cost);
    expect(cost['total'], greaterThan(0));
    expect(cost['currency'], 'cny');
    expect(s.cost(currency: Currency.kzt)['currency'], 'kzt');
  });

  test('every command sent is in the log', () {
    final s = open();
    final room = s.document.floors.first.rooms.first;
    s
      ..preview('RenameRoom', {'roomId': room.id, 'value': 'A'})
      ..apply('RenameRoom', {'roomId': room.id, 'value': 'B'})
      ..apply('RenameRoom', {'roomId': 'nowhere', 'value': 'C'})
      ..undo();
    expect(s.log.map((e) => e['op']), ['preview', 'apply', 'apply', 'undo']);
    expect((s.log[2]['result']! as Map)['code'], 'NOT_FOUND');
    jsonEncode(s.log);
  });

  test('the rule catalog lists the rules the checks report', () {
    final source =
        File('lib/features/editor/engine/core/checks/check_engine.dart')
            .readAsStringSync();
    final used = {
      for (final m in RegExp(r"'(R\d\d)'").allMatches(source)) m.group(1)!
    };
    expect({for (final r in ruleCatalog) r.id}, used);
    // And each at the level the checks give it.
    for (final r in ruleCatalog) {
      expect(RegExp("'${r.id}',\\s*'${r.level}'").hasMatch(source), isTrue,
          reason: r.id);
    }
  });

  test('the object catalog gives every furniture kind a size', () {
    final objects = describeObjects();
    jsonEncode(objects);
    final furniture = objects['furniture']! as List;
    expect(furniture, hasLength(FurnitureKind.values.length));
    for (final f in furniture) {
      expect((f as Map)['width'], greaterThan(0), reason: '${f['kind']}');
    }
  });
}
