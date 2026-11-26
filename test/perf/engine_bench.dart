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

/// Mean milliseconds of [body] over [runs], after a warm-up. [body] is told
/// which run it is, so a benchmark of a drag can move a little further each
/// time, as a finger does, instead of asking for the same result again.
double meanMs(void Function(int run) body, {int runs = 100, int warmUp = 20}) {
  for (var i = 0; i < warmUp; i++) {
    body(i);
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    body(warmUp + i);
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
  double ms(void Function(int run) body) =>
      double.parse(meanMs(body, runs: runs, warmUp: warmUp).toStringAsFixed(3));
  CommandResult run(String kind, Map<String, dynamic> args) =>
      executeCommand(s, DesignCommand(kind, args), ctx);
  // Each run asks for a slightly different result, as each pointer move of
  // a drag does.
  double command(String kind, Map<String, dynamic> Function(int run) args) {
    final result = run(kind, args(0));
    if (result is! Applied) {
      throw StateError('$kind was not applied: $result');
    }
    return ms((i) => run(kind, args(i)));
  }

  double dragFrame(String kind, Map<String, dynamic> Function(int run) args) =>
      ms((i) => deriveHouse(composeDocument(
          benchMeta, (run(kind, args(i)) as Applied).newState)));

  final derived = deriveHouse(doc);
  // Tools that redraw rooms and walls as the finger moves. Each is tried
  // over the plan until a place is found where the command applies.
  final base = deriveFloorBase(doc, floor.id);
  final v = base.axes.v;
  final h = base.axes.h;
  final places = [
    for (var a = 0; a < v.length - 1; a++)
      for (var b = 0; b < h.length - 1; b++) (v[a].pos, h[b].pos)
  ];
  final redraws = <String, (String, Map<String, dynamic> Function(int)?)>{};
  void redraw(String name, String kind,
      Iterable<Map<String, dynamic> Function(int)> candidates) {
    redraws[name] = (
      kind,
      candidates
          .where(
              (c) => run(kind, c(0)) is Applied && run(kind, c(39)) is Applied)
          .firstOrNull
    );
  }

  redraw('carveRoom', 'CarveRoom', [
    for (final (x, y) in places)
      (i) => {
            'floorId': floor.id,
            'left': x + 300,
            'bottom': y + 300,
            'right': x + 1800 + i % 40 * 10,
            'top': y + 1800,
            'roomType': RoomType.storage
          }
  ]);
  redraw('splitSpace', 'SplitSpace', [
    for (final (x, y) in places)
      (i) => {
            'floorId': floor.id,
            'dir': AxisDir.V,
            'pos': x + 1500 + i % 40 * 10,
            'x': x + 1000,
            'y': y + 1000
          }
  ]);
  redraw('addOpening', 'AddOpening', [
    for (final w in base.wallSegments)
      (i) => {
            'floorId': floor.id,
            'anchor': w.ref.anchor,
            'kind': OpeningKind.window,
            'centerAtTap': true,
            'tapT': 800 + i % 40
          }
  ]);
  redraw('moveDrawnWall', 'MoveDrawnWall', [
    for (final w in base.wallSegments.where((w) => w.axis.kind != 'boundary'))
      for (final side in const [1, -1])
        (i) => {
              'floorId': floor.id,
              'anchor': w.ref.anchor,
              'pos': w.axis.pos + side * (100 + i % 40)
            }
  ]);
  final opening = floor.openings.first;
  final axis = [
    ...s.axes.global.map((a) => (a.id, a.pos)),
    ...s.axes.floor.map((a) => (a.id, a.pos))
  ].firstOrNull;
  Map<String, dynamic> resize(int i) =>
      {'openingId': opening.id, 'width': opening.width - 1 - i % 100};
  Map<String, dynamic> moveAxis(int i) =>
      {'axisId': axis!.$1, 'pos': axis.$2 + 1 + i % 200};
  return {
    'size': {
      'floors': s.floors.length,
      'rooms': s.floors.fold<int>(0, (n, f) => n + f.rooms.length),
      'openings': s.floors.fold<int>(0, (n, f) => n + f.openings.length),
      'jsonBytes': bytes.length,
      'sceneElements': derived.scene3d.length,
    },
    'ms': {
      'validateHouse': ms((_) => validateHouse(doc)),
      'encodeHouse': ms((_) => encodeHouse(doc)),
      'loadHouse': ms((_) => loadHouse(bytes)),
      // With nothing kept from earlier: what opening a project costs.
      'deriveFloorBase.cold': ms((_) {
        clearDerived();
        deriveFloorBase(doc, floor.id);
      }),
      'deriveHouse.cold': ms((_) {
        clearDerived();
        deriveHouse(doc);
      }),
      'runChecks': ms((_) => runChecks(doc, derived)),
      'estimateCost': ms((_) => estimateCost(doc, derived)),
      'command.AddFurniture': command(
          'AddFurniture',
          (i) => {
                'floorId': floor.id,
                'kind': FurnitureKind.values.first,
                'x': 500 + i,
                'y': 500
              }),
      'command.RenameRoom': command('RenameRoom',
          (i) => {'roomId': floor.rooms.first.id, 'value': 'room $i'}),
      'command.SetFloorHeight': command('SetFloorHeight',
          (i) => {'floorId': floor.id, 'value': floor.height + 1 + i % 100}),
      'command.ResizeOpening': command('ResizeOpening', resize),
      'command.MoveOpening': command(
          'MoveOpening',
          (i) => {
                'openingId': opening.id,
                'position': {'type': 'fromStart', 'd': 100 + i % 100}
              }),
      if (axis != null) 'command.MoveAxis': command('MoveAxis', moveAxis),
      // One pointer move of a drag as the editor runs it: the command, then
      // the geometry of its result.
      'dragFrame.resizeOpening': dragFrame('ResizeOpening', resize),
      if (axis != null) 'dragFrame.moveAxis': dragFrame('MoveAxis', moveAxis),
      for (final MapEntry(key: name, value: (kind, args)) in redraws.entries)
        if (args != null) 'dragFrame.$name': dragFrame(kind, args),
    },
  };
}

String benchTable(Map<String, Object?> report) {
  final out = StringBuffer();
  for (final plan in report.entries) {
    final data = plan.value! as Map;
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
