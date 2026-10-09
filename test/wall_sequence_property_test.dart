import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/geometry/opening_constraints.dart';
import 'package:yusal/features/wall_attachment_points.dart';

/// Random sequences of the wall and door edits the editor issues. Every
/// accepted step must leave a valid document that survives a file round trip,
/// keep working doors working, and never touch the other floor.
void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'seq_${ids++}', now: () => '2026-10-09T00:00:00Z');
  HouseDocument doc(UndoableDesignState s) => composeDocument(
      Meta(name: '序列', createdAt: ctx.now(), updatedAt: ctx.now()), s);

  test('random wall and door edits keep the document consistent', () {
    var accepted = 0, rejected = 0;
    final kinds = <String, int>{};
    for (var seed = 0; seed < 30; seed++) {
      final rng = Random(seed);
      var s = extractDesignState(createHouse(
          name: '序列',
          width: 12000,
          depth: 10000,
          columns: 1,
          rows: 1,
          initialRoom: true,
          timestamp: ctx.now(),
          newId: ctx.newId));
      // A second floor that the edits below must never change.
      s = (executeCommand(
              s,
              DesignCommand('CopyFloor', {'floorId': s.floors.first.id}),
              ctx) as Applied)
          .newState;
      final other = s.floors[1];
      final floorId = s.floors.first.id;
      for (var step = 0; step < 24; step++) {
        final current = doc(s);
        final base = deriveFloorBase(current, floorId);
        final axes = resolveFloorAxes(current, floorId)!;
        final solids =
            s.floors.first.wallOverrides.whereType<SolidWall>().toList();
        int grid(int lo, int hi) =>
            lo + (rng.nextInt(max(1, (hi - lo) ~/ 100 + 1))) * 100;
        late final DesignCommand command;
        final choice = solids.isEmpty ? 0 : rng.nextInt(5);
        if (choice == 0) {
          final points = wallAttachmentPoints(
              base, deriveHouse(current).floors.first.openings);
          final p = points[rng.nextInt(points.length)];
          final horizontal = rng.nextBool();
          final end = horizontal
              ? grid(0, 12000).toDouble()
              : grid(0, 10000).toDouble();
          command = DesignCommand('AddDrawnWall', {
            'floorId': floorId,
            'x0': p.dx.round(),
            'y0': p.dy.round(),
            'x1': horizontal ? end.round() : p.dx.round(),
            'y1': horizontal ? p.dy.round() : end.round()
          });
        } else {
          final wall = solids[rng.nextInt(solids.length)];
          final c = resolveAnchor(axes, wall.anchor).chain!;
          final vertical = c.carrier.dir == AxisDir.V;
          if (choice == 1) {
            command = DesignCommand('MoveDrawnWall', {
              'floorId': floorId,
              'wallId': wall.id,
              'pos': (c.carrier.pos + (rng.nextInt(21) - 10) * 200)
                  .clamp(100, vertical ? 11900 : 9900)
            });
          } else if (choice == 2) {
            final limit = vertical ? 10000 : 12000;
            final lo = rng.nextBool() ? grid(0, c.endPos - 300) : c.startPos;
            final hi = lo == c.startPos ? grid(lo + 300, limit) : c.endPos;
            command = DesignCommand('UpdateDrawnWall', {
              'floorId': floorId,
              'wallId': wall.id,
              'x0': vertical ? c.carrier.pos : lo,
              'y0': vertical ? lo : c.carrier.pos,
              'x1': vertical ? c.carrier.pos : hi,
              'y1': vertical ? hi : c.carrier.pos
            });
          } else if (choice == 3) {
            command = DesignCommand('DeleteDrawnWall', {
              'floorId': floorId,
              'wallId': wall.id,
              'x0': 0,
              'y0': 0,
              'x1': 0,
              'y1': 0,
              'deleteHostedObjects': true
            });
          } else {
            final segment =
                base.wallSegments[rng.nextInt(base.wallSegments.length)];
            command = DesignCommand('AddOpening', {
              'floorId': floorId,
              'anchor': segment.ref.anchor,
              'kind': OpeningKind.values[rng.nextInt(3)],
              'centerAtTap': true,
              'tapT': rng.nextInt(max(1, segment.end.pos - segment.start.pos))
            });
          }
        }
        final result = executeCommand(s, command, ctx);
        if (result is! Applied) {
          rejected++;
          continue;
        }
        accepted++;
        kinds[command.kind] = (kinds[command.kind] ?? 0) + 1;
        final next = doc(result.newState);
        final reason = 'seed $seed step $step ${command.kind}';
        expect(validateHouse(next), isEmpty, reason: reason);
        final encoded = encodeHouse(next);
        expect(loadHouse(utf8.encode(encoded)).document, next, reason: reason);
        expect(encodeHouse(loadHouse(utf8.encode(encoded)).document!), encoded,
            reason: reason);
        final healthyBefore = documentOpenings(current)
            .where((o) => o.status == 'ok')
            .map((o) => o.opening.id)
            .toSet();
        for (final o in documentOpenings(next))
          if (healthyBefore.contains(o.opening.id))
            expect(o.status, 'ok', reason: '$reason opening ${o.opening.id}');
        expect(result.newState.floors[1], other, reason: reason);
        final roomIds = result.newState.floors.first.rooms.map((r) => r.id);
        expect(roomIds.toSet().length, roomIds.length, reason: reason);
        deriveHouse(next);
        s = result.newState;
      }
    }
    // The generator must exercise real edits, not only rejections.
    // ignore: avoid_print
    print('accepted $accepted rejected $rejected $kinds');
    expect(accepted, greaterThan(300));
    for (final kind in [
      'AddDrawnWall',
      'MoveDrawnWall',
      'UpdateDrawnWall',
      'DeleteDrawnWall',
      'AddOpening'
    ]) expect(kinds[kind], greaterThan(10), reason: kind);
    expect(rejected, greaterThan(0));
  });
}
