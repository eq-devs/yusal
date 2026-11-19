// Frame cost of the editor's interactive paths, measured on real frames.
//
//   flutter drive --profile -d <device> \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/editor_perf_test.dart
//
// Reports the median and 90th-percentile UI-thread (build + layout + paint)
// and raster time per frame for each scenario.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yusal/app/tokens.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';

import '../test/storage_test.dart' show MemoryFiles;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor frame cost', (t) async {
    var n = 0;
    final doc = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'p${n++}');
    final store = ProjectStore(fileSystem: MemoryFiles()),
        id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();

    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => frames.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final report = <String, dynamic>{};

    Future<void> flush() async {
      // Timings arrive in batches, up to a second late.
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1500)));
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
    }

    Future<void> scenario(String name, Future<void> Function(int i) step,
        {int count = 120}) async {
      for (var i = 0; i < 20; i++) await step(i);
      await flush();
      frames.clear();
      for (var i = 0; i < count; i++) await step(i);
      await flush();
      double ms(Duration d) => d.inMicroseconds / 1000;
      List<double> sorted(double Function(FrameTiming) f) =>
          frames.map(f).toList()..sort();
      final ui = sorted((f) => ms(f.buildDuration)),
          raster = sorted((f) => ms(f.rasterDuration));
      double at(List<double> v, double q) =>
          v.isEmpty ? 0 : v[((v.length - 1) * q).round()];
      report[name] = {
        'frames': frames.length,
        'ui_ms_p50': at(ui, 0.5),
        'ui_ms_p90': at(ui, 0.9),
        'raster_ms_p50': at(raster, 0.5),
        'raster_ms_p90': at(raster, 0.9),
      };
      frames.clear();
    }

    final editor = t.element(find.byType(HouseEditor));
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    final centre = t.getCenter(canvas);

    await scenario('whole editor rebuild', (i) async {
      editor.markNeedsBuild();
      await t.pump();
    });

    {
      final a = await t.startGesture(centre + const Offset(-63, 71), pointer: 11);
      final b = await t.startGesture(centre + const Offset(37, 71), pointer: 12);
      await t.pump();
      await b.moveBy(const Offset(30, 0));
      await t.pump();
      await scenario('pinch zoom', (i) async {
        await b.moveBy(Offset(i.isEven ? 4 : -4, 0));
        await t.pump();
      });
      await a.up();
      await b.up();
      await t.pumpAndSettle();
    }

    {
      final g = await t.startGesture(centre + const Offset(-63, 71));
      await t.pump();
      await scenario('pan', (i) async {
        await g.moveBy(Offset(i.isEven ? 3 : -3, i.isEven ? 2 : -2));
        await t.pump();
      });
      await g.up();
      await t.pumpAndSettle();
    }

    {
      // The plan painter alone, recorded off screen: which layer costs what.
      final g = deriveHouse(doc).floors.first, floor = doc.floors.first;
      final size = t.getSize(canvas);
      double paint({bool labels = true, bool dims = true, bool furniture = true}) {
        FloorPlanPainter make() => FloorPlanPainter(
            g.base, {for (final r in floor.rooms) r.id: r.name}, const {},
            openings: g.openings,
            stairs: g.stairs,
            tokens: Tokens.light,
            furniture: [
              for (final i in doc.extras.furniture)
                if (i.floorId == floor.id) i
            ],
            showLabels: labels,
            showDimensions: dims,
            showFurniture: furniture);
        void once() {
          final r = PictureRecorder();
          make().paint(Canvas(r), size);
          r.endRecording().dispose();
        }

        for (var i = 0; i < 30; i++) once();
        final sw = Stopwatch()..start();
        for (var i = 0; i < 200; i++) once();
        return sw.elapsedMicroseconds / 200 / 1000;
      }

      report['painter ms'] = {
        'full': paint(),
        'no labels': paint(labels: false),
        'no dimensions': paint(dims: false),
        'no furniture': paint(furniture: false),
        'bare': paint(labels: false, dims: false, furniture: false),
        'canvas size': '${size.width.round()}x${size.height.round()}',
      };
    }

    SchedulerBinding.instance.removeTimingsCallback(collect);
    binding.reportData = report;
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 400));
  });
}
