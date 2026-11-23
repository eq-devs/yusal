// The engine's baseline benchmark: what commands, derivation, loading and
// checks cost on a typical and a large plan. Pure Dart, so it also runs
// compiled, which is closer to a release build than `flutter test`:
//
//   dart compile exe test/perf/engine_bench.dart -o build/engine_bench
//   build/engine_bench            # prints a table
//   build/engine_bench out.json   # also writes the numbers
//
// test/perf/baseline_test.dart runs the same plans and adds the 3D scene.
import 'dart:convert';
import 'dart:io';

import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/house_spec.dart';
import 'package:yusal/features/editor/engine/core/commands/house_wish.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

var _ids = 0;
final benchContext = CommandContext(
    newId: () => 'b_${_ids++}', now: () => '2026-10-09T00:00:00Z');
const benchMeta = Meta(
    name: 'bench',
    createdAt: '2026-10-09T00:00:00Z',
    updatedAt: '2026-10-09T00:00:00Z');

/// Mean milliseconds of [body] over [runs], after a warm-up.
double meanMs(void Function() body, {int runs = 100, int warmUp = 20}) {
  for (var i = 0; i < warmUp; i++) {
    body();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    body();
  }
  return watch.elapsedMicroseconds / runs / 1000;
}

/// A 12 × 10 m house of two floors, as the wish form builds it.
UndoableDesignState typicalPlan() {
  final built = buildHouseFromSpec(
      wishSpec(
          name: 'T',
          width: 12000,
          depth: 10000,
          floors: 2,
          bedrooms: 4,
          bathrooms: 2,
          dining: true,
          boiler: true),
      benchContext.now(),
      benchContext.newId);
  return extractDesignState(built.document!);
}

/// A 30 × 24 m plan of two floors, 6 × 6 rooms each, partitions built from
/// separate wall pieces with a door in every horizontal one.
UndoableDesignState largePlan() {
  final ctx = benchContext;
  var s = extractDesignState(createHouse(
      name: 'L',
      width: 30000,
      depth: 24000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: ctx.newId));
  final floorId = s.floors.first.id;
  UndoableDesignState run(String kind, Map<String, dynamic> args) =>
      (executeCommand(
                  s, DesignCommand(kind, {'floorId': floorId, ...args}), ctx)
              as Applied)
          .newState;
  for (var i = 1; i < 6; i++) {
    for (var j = 0; j < 6; j++) {
      s = run('AddDrawnWall', {
        'x0': i * 5000,
        'y0': j * 4000,
        'x1': i * 5000,
        'y1': j * 4000 + 4000
      });
    }
  }
  for (var j = 1; j < 6; j++) {
    for (var i = 0; i < 6; i++) {
      s = run('AddDrawnWall', {
        'x0': i * 5000,
        'y0': j * 4000,
        'x1': i * 5000 + 5000,
        'y1': j * 4000
      });
    }
  }
  final doc = composeDocument(benchMeta, s);
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
          s, DesignCommand('CopyFloor', {'floorId': floorId}), ctx) as Applied)
      .newState;
}

/// The engine's numbers for one plan: its size, then milliseconds per call.
Map<String, Object> measurePlan(UndoableDesignState s,
    {int runs = 100, int warmUp = 20}) {
  final ctx = benchContext;
  final doc = composeDocument(benchMeta, s);
  final floor = s.floors.first;
  final bytes = utf8.encode(encodeHouse(doc));
  // A new document each time, so the derived caches do not answer.
  HouseDocument fresh() => composeDocument(benchMeta, s);
  double ms(void Function() body) =>
      double.parse(meanMs(body, runs: runs, warmUp: warmUp).toStringAsFixed(3));
  double command(String kind, Map<String, dynamic> args) {
    final result = executeCommand(s, DesignCommand(kind, args), ctx);
    if (result is! Applied) {
      throw StateError('$kind was not applied: $result');
    }
    return ms(() => executeCommand(s, DesignCommand(kind, args), ctx));
  }

  final derived = deriveHouse(doc);
  final opening = floor.openings.first;
  final axes = [
    ...s.axes.global.map((a) => (a.id, a.pos)),
    ...s.axes.floor.map((a) => (a.id, a.pos))
  ];
  final resize = {'openingId': opening.id, 'width': opening.width - 100};
  return {
    'size': {
      'floors': s.floors.length,
      'rooms': s.floors.fold<int>(0, (n, f) => n + f.rooms.length),
      'openings': s.floors.fold<int>(0, (n, f) => n + f.openings.length),
      'jsonBytes': bytes.length,
      'sceneElements': derived.scene3d.length,
    },
    'ms': {
      'validateHouse': ms(() => validateHouse(doc)),
      'encodeHouse': ms(() => encodeHouse(doc)),
      'loadHouse': ms(() => loadHouse(bytes)),
      'deriveFloorBase': ms(() => deriveFloorBase(fresh(), floor.id)),
      'deriveHouse': ms(() => deriveHouse(fresh())),
      'runChecks': ms(() => runChecks(doc, derived)),
      'estimateCost': ms(() => estimateCost(doc, derived)),
      'command.AddFurniture': command('AddFurniture', {
        'floorId': floor.id,
        'kind': FurnitureKind.values.first,
        'x': 500,
        'y': 500
      }),
      'command.RenameRoom': command(
          'RenameRoom', {'roomId': floor.rooms.first.id, 'value': 'abc'}),
      'command.SetFloorHeight': command(
          'SetFloorHeight', {'floorId': floor.id, 'value': floor.height + 100}),
      'command.ResizeOpening': command('ResizeOpening', resize),
      if (axes.isNotEmpty)
        'command.MoveAxis': command(
            'MoveAxis', {'axisId': axes.first.$1, 'pos': axes.first.$2 + 100}),
      // One pointer move of a drag as the editor runs it: the command, then
      // the geometry of its result.
      'dragFrame': ms(() {
        final r = executeCommand(s, DesignCommand('ResizeOpening', resize), ctx)
            as Applied;
        deriveHouse(composeDocument(benchMeta, r.newState));
      }),
    },
  };
}

String benchTable(Map<String, Object?> report) {
  final out = StringBuffer();
  for (final plan in report.entries) {
    final data = plan.value as Map;
    out.writeln('== ${plan.key}  ${data['size']}');
    for (final group in data.entries.where((e) => e.key != 'size')) {
      for (final row in (group.value as Map).entries) {
        out.writeln('  ${'${row.key}'.padRight(26)} ${row.value}');
      }
    }
  }
  return out.toString();
}

void main(List<String> args) {
  final report = {
    'typical': measurePlan(typicalPlan()),
    'large': measurePlan(largePlan()),
  };
  stdout.write(benchTable(report));
  if (args.isNotEmpty) {
    File(args.first)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }
}
