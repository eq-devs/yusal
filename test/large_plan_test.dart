import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/geometry/floor_base.dart';

/// A large two-floor plan (6 × 6 rooms, partitions built from separate wall
/// pieces, a door in every piece) used to check that the edits run during a
/// drag stay interactive. Set YUSAL_LARGE_PLAN to a path to also write the
/// plan as a .house file for manual or browser checks.
void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'large_${ids++}', now: () => '2026-10-09T00:00:00Z');

  UndoableDesignState build() {
    var s = extractDesignState(createHouse(
        name: '大户型',
        width: 30000,
        depth: 24000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
        newId: ctx.newId));
    final floorId = s.floors.first.id;
    UndoableDesignState run(String kind, Map<String, dynamic> args) {
      final r = executeCommand(
          s, DesignCommand(kind, {'floorId': floorId, ...args}), ctx);
      expect(r, isA<Applied>(), reason: r is Rejected ? r.message : kind);
      return (r as Applied).newState;
    }

    for (var i = 1; i < 6; i++)
      for (var j = 0; j < 6; j++)
        s = run('AddDrawnWall', {
          'x0': i * 5000,
          'y0': j * 4000,
          'x1': i * 5000,
          'y1': j * 4000 + 4000
        });
    for (var j = 1; j < 6; j++)
      for (var i = 0; i < 6; i++)
        s = run('AddDrawnWall', {
          'x0': i * 5000,
          'y0': j * 4000,
          'x1': i * 5000 + 5000,
          'y1': j * 4000
        });
    final doc = composeDocument(
        Meta(name: '大户型', createdAt: ctx.now(), updatedAt: ctx.now()), s);
    for (final w in deriveFloorBase(doc, floorId).wallSegments) {
      if (w.axis.kind == 'boundary' || w.axis.dir != AxisDir.H) continue;
      s = run('AddOpening', {
        'anchor': w.ref.anchor,
        'kind': OpeningKind.door,
        'centerAtTap': true,
        'tapT': (w.end.pos - w.start.pos) ~/ 2
      });
    }
    return (executeCommand(
                s, DesignCommand('CopyFloor', {'floorId': floorId}), ctx)
            as Applied)
        .newState;
  }

  test('a large plan stays responsive while dragging walls', () {
    final s = build();
    final doc = composeDocument(
        Meta(name: '大户型', createdAt: ctx.now(), updatedAt: ctx.now()), s);
    final floorId = s.floors.first.id;
    expect(s.floors.first.rooms.length, 36);
    expect(s.floors.first.wallOverrides.whereType<SolidWall>().length, 60);
    expect(validateHouse(doc), isEmpty);
    final path = Platform.environment['YUSAL_LARGE_PLAN'];
    if (path != null) File(path).writeAsStringSync(encodeHouse(doc));

    // Warm up, then time what one pointer move costs in each drag.
    final axes = resolveFloorAxes(doc, floorId)!;
    final partition =
        s.floors.first.wallOverrides.whereType<SolidWall>().firstWhere((w) {
      final c = resolveAnchor(axes, w.anchor).chain!;
      return c.carrier.dir == AxisDir.V &&
          c.carrier.pos == 15000 &&
          c.startPos == 8000;
    });
    Duration time(void Function() body, {int runs = 10}) {
      body();
      final watch = Stopwatch()..start();
      for (var i = 0; i < runs; i++) body();
      return watch.elapsed ~/ runs;
    }

    final derive = time(() => deriveHouse(doc));
    final draw = time(() => executeCommand(
        s,
        DesignCommand('AddDrawnWall',
            {'floorId': floorId, 'x0': 2500, 'y0': 0, 'x1': 2500, 'y1': 2000}),
        ctx));
    final move = time(() => executeCommand(
        s,
        DesignCommand('MoveDrawnWall',
            {'floorId': floorId, 'wallId': partition.id, 'pos': 15600}),
        ctx));
    // ignore: avoid_print
    print('large plan: derive ${derive.inMilliseconds} ms, '
        'draw preview ${draw.inMilliseconds} ms, '
        'move preview ${move.inMilliseconds} ms');
    // Generous bounds for a debug VM; they only catch order-of-magnitude
    // regressions. Browser timings are recorded separately.
    expect(draw.inMilliseconds, lessThan(1000));
    expect(move.inMilliseconds, lessThan(2000));
    expect(loadHouse(utf8.encode(encodeHouse(doc))).document, doc);
  });
}
