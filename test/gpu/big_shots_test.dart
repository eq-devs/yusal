// Larger pictures of the GPU's shadows and corners, for a person to look
// at; made only when YUSAL_GPU_SHOTS says where to leave them.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

void main() {
  final shots = Platform.environment['YUSAL_GPU_SHOTS'];
  testWidgets('large pictures', (t) async {
    await t.runAsync(() async {
      SceneGpu.reset();
      await SceneGpu.prepare();
      final gpu = SceneGpu.instance;
      if (gpu == null || shots == null) return;
      var n = 0;
      final doc = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'b${n++}');
      final model = buildScene(
          doc, deriveHouse(doc), const SceneOptions(), (r) => r.name);
      const size = Size(1200, 900);
      Camera at(double yaw, double pitch, double distance) {
        final c = model.center;
        final dir = Vec3(math.cos(pitch) * math.sin(yaw), math.sin(pitch),
            math.cos(pitch) * math.cos(yaw));
        final eye = c + dir * distance;
        return Camera(eye, (c - eye).unit, 50 * math.pi / 180);
      }

      final views = <String, (Camera, SceneSettings)>{
        'big front': (at(0.6, 0.45, 26), const SceneSettings(hour: 15)),
        'big open': (
          at(2.2, 0.9, 22),
          const SceneSettings(roof: false, hour: 15)
        ),
        'big white': (
          at(2.2, 0.9, 22),
          const SceneSettings(roof: false, hour: 15, style: SceneStyle.white)
        ),
        'big cut': (
          at(0.6, 1.0, 20),
          const SceneSettings(cut: true, maxFloor: 0, hour: 10)
        ),
      };
      for (final MapEntry(key: name, value: (camera, settings))
          in views.entries) {
        for (final on in [true, false]) {
          final recorder = ui.PictureRecorder();
          ScenePainter(
                  model: model,
                  camera: camera,
                  settings: settings,
                  northAngleDeg: 0,
                  walk: false,
                  labels: false,
                  gpu: on ? gpu : null)
              .paint(Canvas(recorder), size);
          final image = await recorder
              .endRecording()
              .toImage(size.width.round(), size.height.round());
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          File('$shots/$name ${on ? 'gpu' : 'canvas'}.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png.buffer.asUint8List());
        }
      }
    });
  });
}
