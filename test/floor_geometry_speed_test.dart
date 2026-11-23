import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/drawn_wall_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

import 'floor_shape_cache_test.dart' show describe;
import 'perf/engine_bench.dart';

/// Commands that redraw rooms and walls, spread over the plan of [doc].
List<(String, Map<String, dynamic>)> spatialCommands(HouseDocument doc) {
  final out = <(String, Map<String, dynamic>)>[];
  for (final floor in doc.floors) {
    final axes = resolveFloorAxes(doc, floor.id)!;
    final v = axes.v;
    final h = axes.h;
    for (var a = 0; a < v.length - 1; a += 2) {
      for (var b = 0; b < h.length - 1; b += 2) {
        final x = v[a].pos;
        final y = h[b].pos;
        out
          ..add((
            'CarveRoom',
            {
              'floorId': floor.id,
              'left': x + 300,
              'bottom': y + 300,
              'right': x + 1900,
              'top': y + 1700,
              'roomType': RoomType.storage
            }
          ))
          ..add((
            'CarveRoom',
            {
              'floorId': floor.id,
              'left': x,
              'bottom': y,
              'right': x + 1500,
              'top': h[b + 1].pos
            }
          ))
          ..add((
            'SplitSpace',
            {
              'floorId': floor.id,
              'dir': AxisDir.V,
              'pos': x + 1500,
              'x': x + 800,
              'y': y + 800
            }
          ))
          ..add((
            'SplitSpace',
            {
              'floorId': floor.id,
              'dir': AxisDir.H,
              'pos': y + 1300,
              'x': x + 800,
              'y': y + 800
            }
          ))
          ..add((
            'PlaceStair',
            {
              'floorId': floor.id,
              'left': x + 200,
              'bottom': y + 200,
              'right': x + 1400,
              'top': y + 3600
            }
          ))
          ..add((
            'EraseCells',
            {
              'floorId': floor.id,
              'cells': [Cell(a, b)]
            }
          ))
          ..add((
            'PaintCells',
            {
              'floorId': floor.id,
              'cells': [Cell(a, b), Cell(a + 1 < axes.nx ? a + 1 : a, b)],
              'roomType': RoomType.hall
            }
          ));
      }
    }
    for (var i = 0; i + 1 < floor.rooms.length; i += 3) {
      out
        ..add((
          'MergeRooms',
          {'roomIdA': floor.rooms[i].id, 'roomIdB': floor.rooms[i + 1].id}
        ))
        ..add((
          'MergeRooms',
          {
            'roomIdA': floor.rooms[i].id,
            'roomIdB': floor.rooms[i + 1].id,
            'deleteHostedObjects': true
          }
        ));
    }
  }
  out
    ..add(('CutOutline', {'corner': 'tr', 'width': 2500, 'depth': 2500}))
    ..add((
      'CutOutline',
      {
        'corner': 'bl',
        'width': 3000,
        'depth': 2000,
        'floorIds': [doc.floors.first.id]
      }
    ));
  return out;
}

void main() {
  HouseDocument fixture(String name) =>
      loadHouse(File('test/fixtures/$name').readAsBytesSync()).document!;

  /// A plan whose floors are all made of drawn walls.
  UndoableDesignState drawn(UndoableDesignState s) {
    var state = s;
    for (final f in s.floors) {
      final r = executeCommand(state,
          DesignCommand('EnableWallDrawing', {'floorId': f.id}), benchContext);
      if (r is Applied) state = r.newState;
    }
    return state;
  }

  final houses = <String, HouseDocument>{
    for (final f in Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.house')))
      f.uri.pathSegments.last: fixture(f.uri.pathSegments.last),
    'typical': composeDocument(benchMeta, typicalPlan()),
    'typical, drawn walls': composeDocument(benchMeta, drawn(typicalPlan())),
    'large': composeDocument(benchMeta, largePlan()),
  };

  tearDown(() {
    wallsNearSpaceOnly = true;
    skipUnchangedFloors = true;
  });

  String geometry(HouseDocument doc, {required bool near}) {
    wallsNearSpaceOnly = near;
    clearDerived();
    return [for (final f in doc.floors) describe(deriveFloorBase(doc, f.id))]
        .join('\n');
  }

  /// What [kind] makes of [doc], as text, with the ids it drew made the
  /// same from run to run.
  String outcome(HouseDocument doc, String kind, Map<String, dynamic> args) {
    var n = 0;
    clearDerived();
    final r = executeCommand(extractDesignState(doc), DesignCommand(kind, args),
        CommandContext(newId: () => 'new-${n++}', now: () => 'now'));
    return switch (r) {
      Applied(:final newState) =>
        encodeHouse(composeDocument(benchMeta, newState)),
      Rejected(:final reason, :final message) => 'rejected $reason $message',
      NeedsResolution(:final conflict) =>
        'resolve ${conflict.message} ${conflict.choices}',
    };
  }

  /// [house] with each floor's rooms and wall pieces in a fixed order.
  /// Bringing a floor's walls in line also lists its rooms largest first
  /// and its walls along the grid; a floor left alone keeps the order it
  /// had, which is the one difference allowed.
  String inOrder(String house) {
    if (!house.startsWith('{')) return house;
    final json = jsonDecode(house) as Map<String, dynamic>;
    for (final f in (json['floors'] as List).cast<Map<String, dynamic>>()) {
      for (final part in const ['rooms', 'wallOverrides']) {
        f[part] = [for (final e in f[part] as List? ?? const []) jsonEncode(e)]
          ..sort();
      }
    }
    return jsonEncode(json);
  }

  for (final house in houses.entries) {
    test(
        '${house.key}: rooms measured against nearby walls come out as '
        'against every wall', () {
      final doc = house.value;
      expect(geometry(doc, near: true), geometry(doc, near: false));
      // And for what the plan becomes after being redrawn.
      var compared = 0;
      for (final (kind, args) in spatialCommands(doc).take(40)) {
        final r = executeCommand(
            extractDesignState(doc), DesignCommand(kind, args), benchContext);
        if (r is! Applied) continue;
        final next = composeDocument(benchMeta, r.newState);
        expect(geometry(next, near: true), geometry(next, near: false),
            reason: '$kind $args');
        compared++;
      }
      expect(compared, greaterThan(0));
    });

    test(
        '${house.key}: leaving unchanged floors alone changes only the order they list things in',
        () {
      final doc = house.value;
      var applied = 0;
      for (final (kind, args) in spatialCommands(doc)) {
        skipUnchangedFloors = true;
        final quick = outcome(doc, kind, args);
        skipUnchangedFloors = false;
        expect(inOrder(quick), inOrder(outcome(doc, kind, args)),
            reason: '$kind $args');
        if (quick.startsWith('{')) applied++;
      }
      expect(applied, greaterThan(0));
    });
  }
}
