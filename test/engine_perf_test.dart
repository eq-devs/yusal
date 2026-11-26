import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/perf/engine_perf.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/widgets/perf_meter.dart';

import 'perf/engine_bench.dart';

void main() {
  final perf = EnginePerf.instance;
  setUp(() {
    EnginePerf.enabled = true;
    perf.reset();
  });
  tearDown(() {
    EnginePerf.enabled = perfBuild;
    perf.reset();
  });

  test('measuring is off in an ordinary build and then records nothing', () {
    expect(perfBuild, isFalse);
    EnginePerf.enabled = false;
    expect(timed('work', () => 7), 7);
    sized('things', () => fail('a size is not worked out when off'));
    expect(perf.timings, isEmpty);
    expect(perf.sizes, isEmpty);
  });

  test('timed work is counted with its mean, longest and last cost', () {
    perf
      ..record('work', 1000)
      ..record('work', 3000);
    final e = perf.timing('work')!;
    expect(e.count, 2);
    expect(e.meanMs, 2);
    expect(e.maxMs, 3);
    expect(e.lastMs, 3);
    expect(timed('other', () => 'done'), 'done');
    expect(perf.timing('other')!.count, 1);
  });

  test('work that throws is still recorded', () {
    expect(() => timed<void>('broken', () => throw StateError('x')),
        throwsStateError);
    expect(perf.timing('broken')!.count, 1);
  });

  test('only work over the slow mark is kept as slow, newest last', () {
    perf.record('quick', EnginePerf.slowMicros - 1);
    for (var i = 0; i < 50; i++) {
      perf.record('slow$i', EnginePerf.slowMicros + i);
    }
    expect(perf.slow, hasLength(40));
    expect(perf.slow.first.name, 'slow10');
    expect(perf.slow.last.name, 'slow49');
  });

  test('a command, the geometry and the scene report under their names', () {
    final s = typicalPlan();
    final floor = s.floors.first;
    final result = executeCommand(
        s,
        DesignCommand(
            'RenameRoom', {'roomId': floor.rooms.first.id, 'value': 'abc'}),
        benchContext);
    expect(result, isA<Applied>());
    expect(perf.timing('command.RenameRoom')!.count, 1);

    final doc = composeDocument(benchMeta, (result as Applied).newState);
    // Nothing kept from the command, so the geometry below is derived.
    clearDerived();
    perf.reset();
    final derived = deriveHouse(doc);
    deriveHouse(doc);
    expect(perf.timing('derive.house')!.count, 1,
        reason: 'the cached answer is not derived again');
    expect(perf.timing('derive.floorBase')!.count, s.floors.length);

    final model = buildScene(doc, derived, const SceneOptions(), (r) => r.name);
    expect(perf.timing('scene3d.build')!.count, 1);
    expect(perf.sizes['scene3d.faces'], model.faces.length);
    expect(perf.sizes['scene3d.vertices'], greaterThan(model.faces.length));
    expect(model.bsp.fragmentCount, perf.sizes['scene3d.bspFragments']);
    expect(perf.timing('scene3d.bsp')!.count, 1);

    final report = perf.toJson();
    expect((report['timings']! as Map).keys, contains('scene3d.build'));
    expect((report['sizes']! as Map)['scene3d.faces'], model.faces.length);
  });

  test('the frame window keeps the newest frames and counts the long ones', () {
    final frames = FrameWindow(3)
      ..add(1000, 1000)
      ..add(2000, 2000)
      ..add(10000, 10000)
      ..add(3000, 3000);
    expect(frames.frames, 3);
    expect(frames.buildMeanMs, 5);
    expect(frames.rasterMaxMs, 10);
    expect(frames.over(16.7), 1);
  });

  test('the meter lists frames, the engine rows and the slowest commands', () {
    perf
      ..record('paint.plan2d', 2000)
      ..record('command.MoveAxis', 9000)
      ..record('command.RenameRoom', 4000)
      ..size('scene3d.faces', 120)
      ..size('scene3d.vertices', 480);
    final lines = perfMeterLines(perf, FrameWindow()..add(4000, 6000));
    expect(lines.first, startsWith('frame'));
    expect(lines[1], startsWith('paint.plan2d'));
    expect(lines[2], startsWith('MoveAxis'));
    expect(lines[3], startsWith('RenameRoom'));
    expect(lines.last, contains('3d faces 120  verts 480'));
  });

  testWidgets('the meter is drawn only when asked for', (tester) async {
    const child = SizedBox(key: Key('page'));
    await tester.pumpWidget(const MaterialApp(home: PerfMeter(child: child)));
    expect(find.byKey(const Key('perf-meter')), findsNothing);
    expect(find.byKey(const Key('page')), findsOneWidget);

    perf.record('paint.plan2d', 2000);
    await tester.pumpWidget(
        const MaterialApp(home: PerfMeter(show: true, child: child)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('perf-meter')), findsOneWidget);
    expect(find.textContaining('paint.plan2d'), findsOneWidget);

    await tester.longPress(find.byKey(const Key('perf-meter')));
    await tester.pump();
    expect(perf.timings, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
