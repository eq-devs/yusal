// Off-screen renders of the 3D view for visual review (not run in CI).
// SHOTS_OUT=/path flutter test test/render_shots/shots_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/render3d/scene_model.dart';
import 'package:yusal/render3d/scene_view.dart';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  final out = Platform.environment['SHOTS_OUT'] ?? 'build/shots';
  setUpAll(() async {
    await loadFont(
        'Inter', ['assets/fonts/Inter-400.otf', 'assets/fonts/Inter-700.otf']);
    await loadFont('JetBrainsMono', ['assets/fonts/JetBrainsMono-Regular.ttf']);
  });
  var n = 0;
  String id() => 'id${n++}';
  final houses = <String, HouseDocument>{
    'kz': createKazakhTemplate('2026-10-14T00:00:00Z', id),
    'two': createTemplate('two', '2026-10-14T00:00:00Z', id),
    'five': createTemplate('five', '2026-10-14T00:00:00Z', id),
    'gable': loadHouse(
            File('test/fixtures/full_two_floor_gable.house').readAsBytesSync())
        .document!,
  };
  const views = ['iso', 'front', 'back', 'side', 'top'];
  final modes = <String, SceneSettings>{
    'full': const SceneSettings(),
    'noroof': const SceneSettings(roof: false),
    'cut': const SceneSettings(cut: true),
    'floor0': const SceneSettings(maxFloor: 0),
    'night': const SceneSettings(hour: 22),
    'found': const SceneSettings(foundation: true),
  };
  const size = Size(780, 520);
  test(skip: Platform.environment['SHOTS_OUT'] == null, 'render', () async {
    Directory(out).createSync(recursive: true);
    final stats = StringBuffer();
    for (final h in houses.entries) {
      final derived = deriveHouse(h.value);
      for (final m in modes.entries) {
        final model = buildScene(
            h.value,
            derived,
            SceneOptions(roof: m.value.roof, foundation: m.value.foundation),
            (r) => r.name);
        for (final v in views) {
          if (m.key != 'full' && v != 'iso' && v != 'top') continue;
          final pose = viewPose(model, v, aspect: size.width / size.height);
          final cam =
              orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance);
          await _shot(model, cam, m.value, h.value, false, size,
              '$out/${h.key}_${m.key}_$v.png', stats);
        }
        // Close-up zoom (frustum test) and low orbit.
        if (m.key == 'full' || m.key == 'cut') {
          final pose = viewPose(model, 'iso', aspect: size.width / size.height);
          final cam = orbitCamera(
              pose.target, pose.yaw + 0.6, 0.25, pose.distance * 0.35);
          await _shot(model, cam, m.value, h.value, false, size,
              '$out/${h.key}_${m.key}_close.png', stats);
        }
      }
      // Walk-through: inside the house, facing a wall.
      final wModel = buildScene(
          h.value, derived, const SceneOptions(walk: true), (r) => r.name);
      for (final (name, eye, yaw, mf) in [
        ('walk_out', Vec3(wModel.width / 2, 1.6, wModel.depth + 8), 0.0, 999),
        ('walk_in', Vec3(wModel.width * 0.3, 1.6, wModel.depth * 0.6), 0.8, 0),
      ]) {
        final f = Vec3(-math.sin(yaw), 0, -math.cos(yaw));
        await _shot(
            wModel,
            Camera(eye, f, 72 * math.pi / 180),
            SceneSettings(maxFloor: mf),
            h.value,
            true,
            size,
            '$out/${h.key}_$name.png',
            stats);
      }
    }
    File('$out/stats.txt').writeAsStringSync(stats.toString());
    // ignore: avoid_print
    print(stats);
  });
}

Future<void> _shot(
    SceneModel model,
    Camera cam,
    SceneSettings s,
    HouseDocument doc,
    bool walk,
    Size size,
    String path,
    StringBuffer stats) async {
  final p = ScenePainter(
      model: model,
      camera: cam,
      settings: s,
      northAngleDeg: doc.footprint.northAngleDeg,
      walk: walk,
      labels: true);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final sw = Stopwatch()..start();
  p.paint(canvas, size);
  final ms = sw.elapsedMicroseconds / 1000;
  final img =
      await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  var diff = '';
  final before = Platform.environment['SHOTS_BEFORE'];
  if (before != null && File('$before/${path.split('/').last}').existsSync()) {
    final codec = await ui.instantiateImageCodec(
        File('$before/${path.split('/').last}').readAsBytesSync());
    final b = (await (await codec.getNextFrame()).image.toByteData())!;
    final a = (await img.toByteData())!;
    var changed = 0;
    for (var i = 0; i < a.lengthInBytes; i += 4) {
      var d = 0;
      for (var k = 0; k < 3; k++) {
        d = math.max(d, (a.getUint8(i + k) - b.getUint8(i + k)).abs());
      }
      if (d > 40) changed++;
    }
    diff = '\tchanged=$changed';
  }
  stats.writeln(
      '${path.split('/').last}\titems=${p.itemCount}\tculled=${p.culled}\tfaces=${model.faces.length}\tpaint=${ms.toStringAsFixed(1)}ms$diff');
}
