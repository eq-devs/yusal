// The GPU renderer against the canvas painter. Flutter GPU needs the
// Impeller engine, so run this with
//
//   flutter test test/gpu --enable-impeller --enable-flutter-gpu
//
// Without those flags there is no GPU in the test runner, and what is
// checked instead is that the view then paints on the canvas as before.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu_frame.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

import '../perf/engine_bench.dart';

const size = Size(480, 360);

/// Where to leave the pictures for a person to look at; nowhere when unset.
final shots = Platform.environment['YUSAL_GPU_SHOTS'];

Camera lookingAt(SceneModel model, double yaw, double pitch, double distance) {
  final c = model.center;
  final dir = Vec3(math.cos(pitch) * math.sin(yaw), math.sin(pitch),
      math.cos(pitch) * math.cos(yaw));
  final eye = c + dir * distance;
  return Camera(eye, (c - eye).unit, 50 * math.pi / 180);
}

Future<Uint8List> pixels(ScenePainter painter, String name) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final image = await recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
  if (shots != null) {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('$shots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
  }
  final raw = (await image.toByteData())!;
  return raw.buffer.asUint8List();
}

/// The share of pixels that differ by more than [by] in some channel.
double differing(Uint8List a, Uint8List b, {int by = 40}) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > by ||
        (a[i + 1] - b[i + 1]).abs() > by ||
        (a[i + 2] - b[i + 2]).abs() > by) {
      n++;
    }
  }
  return n / (a.length / 4);
}

void main() {
  final doc = composeDocument(benchMeta, typicalPlan());
  final model =
      buildScene(doc, deriveHouse(doc), const SceneOptions(), (r) => r.name);

  ScenePainter painter(Camera camera, SceneSettings settings,
          {SceneGpu? gpu, bool walk = false, bool fast = false}) =>
      ScenePainter(
          model: model,
          camera: camera,
          settings: settings,
          northAngleDeg: 0,
          walk: walk,
          labels: false,
          fast: fast,
          gpu: gpu);

  final views = <String, (Camera, SceneSettings)>{
    'front': (lookingAt(model, 0.6, 0.5, 26), const SceneSettings()),
    'back': (lookingAt(model, 3.6, 0.35, 30), const SceneSettings()),
    'above': (lookingAt(model, 1.2, 1.2, 28), const SceneSettings()),
    'cut': (
      lookingAt(model, 0.6, 0.9, 24),
      const SceneSettings(cut: true, maxFloor: 0)
    ),
    'no roof': (
      lookingAt(model, 2.2, 0.8, 24),
      const SceneSettings(roof: false)
    ),
    'night': (lookingAt(model, 0.6, 0.5, 26), const SceneSettings(dark: true)),
    'white': (
      lookingAt(model, 0.6, 0.5, 26),
      const SceneSettings(style: SceneStyle.white)
    ),
    'lines': (
      lookingAt(model, 0.6, 0.5, 26),
      const SceneSettings(style: SceneStyle.lines)
    ),
    'lines cut': (
      lookingAt(model, 0.6, 0.9, 24),
      const SceneSettings(cut: true, maxFloor: 0, style: SceneStyle.lines)
    ),
    'white no roof': (
      lookingAt(model, 2.2, 0.8, 24),
      const SceneSettings(roof: false, style: SceneStyle.white)
    ),
  };

  testWidgets('the GPU draws what the canvas paints', (t) async {
    await t.runAsync(() async {
      SceneGpu.reset();
      await SceneGpu.prepare();
      final gpu = SceneGpu.instance;
      if (gpu == null) {
        // No GPU here: the painter is the canvas painter, untouched.
        final (camera, settings) = views['front']!;
        final p = painter(camera, settings);
        await pixels(p, 'canvas only');
        expect(p.drewOnGpu, isFalse);
        expect(p.itemCount, greaterThan(100));
        return;
      }
      for (final MapEntry(key: name, value: (camera, settings))
          in views.entries) {
        final onCanvas = painter(camera, settings);
        final onGpu = painter(camera, settings, gpu: gpu);
        final a = await pixels(onCanvas, '$name canvas');
        final b = await pixels(onGpu, '$name gpu');
        expect(SceneGpu.reason, isNull, reason: name);
        expect(onGpu.drewOnGpu, isTrue, reason: name);
        expect(onCanvas.drewOnGpu, isFalse, reason: name);
        // Edges are smoothed differently and a few faces that the canvas
        // orders by hand fall where depth puts them; the picture is the
        // same house from the same place.
        expect(differing(a, b), lessThan(0.04), reason: name);
      }
    });
  });

  testWidgets('the GPU shades what the sun does not reach, and the corners',
      (t) async {
    await t.runAsync(() async {
      SceneGpu.reset();
      await SceneGpu.prepare();
      final gpu = SceneGpu.instance;
      if (gpu == null) return;
      addTearDown(() => SceneGpu.effects = true);
      // The renderer tried a shadow on a small scene when it started.
      expect(gpu.shades, isTrue);
      final (camera, settings) = views['white no roof']!;
      SceneGpu.effects = false;
      final flat = painter(camera, settings, gpu: gpu);
      final a = await pixels(flat, 'flat');
      expect(flat.gpuFrame!.effects, isNull);
      SceneGpu.effects = true;
      final shaded = painter(camera, settings, gpu: gpu);
      final b = await pixels(shaded, 'shaded');
      expect(shaded.drewOnGpu, isTrue);
      final effects = shaded.gpuFrame!.effects!;
      expect(effects.count, greaterThan(1000));
      expect(effects.sun, 1);
      // Nothing gets lighter, and a fair part of the house gets darker.
      var darker = 0;
      var lighter = 0;
      for (var i = 0; i < a.length; i += 4) {
        final d = (a[i] + a[i + 1] + a[i + 2]) - (b[i] + b[i + 1] + b[i + 2]);
        if (d > 24) darker++;
        if (d < -24) lighter++;
      }
      expect(darker / (a.length / 4), greaterThan(0.03));
      expect(lighter / (a.length / 4), lessThan(0.002));

      // The solids are gathered once and kept while the house shows the
      // same; turning the view draws no new shadows, moving the sun does.
      final (other, _) = views['front']!;
      final turned = painter(other, settings, gpu: gpu);
      await pixels(turned, 'shaded turned');
      final again = turned.gpuFrame!.effects!;
      expect(identical(again.solids, effects.solids), isTrue);
      expect(again.lightKey, effects.lightKey);
      final later =
          painter(camera, const SceneSettings(roof: false, hour: 16), gpu: gpu);
      await pixels(later, 'shaded later');
      expect(later.gpuFrame!.effects!.lightKey, isNot(effects.lightKey));
      expect(SceneGpu.reason, isNull);

      // No sun at night, and nothing on a line drawing.
      final night = painter(camera, const SceneSettings(dark: true), gpu: gpu);
      await pixels(night, 'shaded night');
      expect(night.gpuFrame!.effects!.sun, 0);
      final lines = painter(
          camera, const SceneSettings(style: SceneStyle.lines),
          gpu: gpu);
      await pixels(lines, 'shaded lines');
      expect(lines.gpuFrame!.effects, isNull);
    });
  });

  testWidgets('a tap finds the same thing on the GPU as on the canvas',
      (t) async {
    await t.runAsync(() async {
      SceneGpu.reset();
      await SceneGpu.prepare();
      final gpu = SceneGpu.instance;
      if (gpu == null) return;
      final (camera, settings) = views['no roof']!;
      final onCanvas = painter(camera, settings);
      final onGpu = painter(camera, settings, gpu: gpu);
      await pixels(onCanvas, 'pick canvas');
      await pixels(onGpu, 'pick gpu');
      var same = 0;
      var found = 0;
      var tried = 0;
      for (var x = 20.0; x < size.width; x += 23) {
        for (var y = 20.0; y < size.height; y += 19) {
          final a = onCanvas.pick(Offset(x, y));
          final b = onGpu.pick(Offset(x, y));
          tried++;
          if (a != null) found++;
          if (a == b) same++;
        }
      }
      expect(found, greaterThan(20));
      // On an edge between two faces the two may answer differently.
      expect(same / tried, greaterThan(0.93));
    });
  });

  testWidgets('walking and the foundation view stay on the canvas', (t) async {
    await t.runAsync(() async {
      SceneGpu.reset();
      await SceneGpu.prepare();
      final gpu = SceneGpu.instance;
      final (camera, settings) = views['front']!;
      final walking = painter(camera, settings, gpu: gpu, walk: true);
      final footing =
          painter(camera, const SceneSettings(foundation: true), gpu: gpu);
      await pixels(walking, 'walk');
      await pixels(footing, 'foundation');
      expect(walking.drewOnGpu, isFalse);
      expect(footing.drewOnGpu, isFalse);
    });
  });

  testWidgets('a GPU that fails hands the frame to the canvas', (t) async {
    await t.runAsync(() async {
      SceneGpu.reset();
      final (camera, settings) = views['front']!;
      final p = painter(camera, settings, gpu: _Broken());
      final a = await pixels(p, 'after failure');
      expect(p.drewOnGpu, isFalse);
      expect(SceneGpu.reason, contains('lost'));
      expect(SceneGpu.instance, isNull);
      final plain = await pixels(painter(camera, settings), 'plain');
      expect(differing(a, plain, by: 0), 0);
      SceneGpu.reset();
    });
  });

  test('the camera matrix puts a point where the painter projects it', () {
    final (camera, settings) = views['front']!;
    final p = painter(camera, settings);
    final m = gpuCameraMatrix(camera, size);
    final focal = size.height / 2 / math.tan(camera.fov / 2);
    for (final f in model.faces.take(200)) {
      for (final q in f.points) {
        final c = camera.toCamera(q);
        if (c.z < 1) continue;
        final at = p.project(c, size, focal)!;
        double row(int i) =>
            m[i] * q.x + m[4 + i] * q.y + m[8 + i] * q.z + m[12 + i];
        final w = row(3);
        expect(size.width / 2 * (1 + row(0) / w), closeTo(at.dx, 0.05));
        expect(size.height / 2 * (1 - row(1) / w), closeTo(at.dy, 0.05));
        expect(row(2) / w, inInclusiveRange(0, 1));
      }
    }
  });
}

class _Broken extends SceneGpu {
  @override
  ui.Image draw(GpuFrame frame, int width, int height) =>
      throw StateError('device lost');
}
