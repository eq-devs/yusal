import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/render3d/scene_model.dart';
import 'package:yusal/render3d/scene_view.dart';

void main() {
  var n = 0;
  final doc = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'cam${n++}');
  final derived = deriveHouse(doc);

  Future<SceneViewState> mount(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 800,
            height: 600,
            child: SceneView(
                doc: doc,
                derived: derived,
                roomName: (r) => r.name,
                settings: const SceneSettings(),
                walk: false))));
    return t.state<SceneViewState>(find.byType(SceneView));
  }

  Offset screen(SceneViewState s, Vec3 p) {
    final cam = orbitCamera(s.target, s.yaw, s.pitch, s.distance);
    final c = cam.toCamera(p);
    final f = s.viewSize.height / 2 / math.tan(cam.fov / 2);
    return Offset(s.viewSize.width / 2 + c.x / c.z * f,
        s.viewSize.height / 2 - c.y / c.z * f);
  }

  testWidgets('two fingers pan with the fingers and pinch about them',
      (t) async {
    final s = await mount(t);
    final centre = t.getCenter(find.byType(SceneView));
    final p = s.target; // on screen at the centre
    expect(screen(s, p).dx, closeTo(400, 1e-6));
    expect(screen(s, p).dy, closeTo(300, 1e-6));

    final a = await t.startGesture(centre - const Offset(60, 0), pointer: 1);
    final b = await t.startGesture(centre + const Offset(60, 0), pointer: 2);
    await t.pump();
    Future<void> step(int i) async {
      await a.moveTo(centre - const Offset(60, 0) + Offset(10.0 * i, 10.0 * i));
      await b.moveTo(centre + const Offset(60, 0) + Offset(10.0 * i, 10.0 * i));
      await t.pump();
    }

    // The first moves pass the touch slop and start the gesture.
    for (var i = 1; i <= 3; i++) await step(i);
    final start = screen(s, p);
    for (var i = 4; i <= 7; i++) await step(i);
    // From then on the point under the fingers moves with them (40, 40).
    final moved = screen(s, p) - start;
    expect(moved.dx, closeTo(40, 1.5));
    expect(moved.dy, closeTo(40, 1.5));
    await a.up();
    await b.up();
    await t.pump();

    // Zooming about a corner keeps what is under it in place.
    final yaw = s.yaw, pitch = s.pitch, before = s.distance;
    final cam = orbitCamera(s.target, yaw, pitch, before);
    final f = 300 / math.tan(cam.fov / 2);
    const at = Offset(650, 120);
    final q = s.target +
        (cam.right * (at.dx - 400) - cam.up * (at.dy - 300)) * (before / f);
    s.zoomAt(at, before * 0.5);
    expect(s.distance, closeTo(before * 0.5, 1e-9));
    expect((screen(s, q) - at).distance, lessThan(0.5));
  });

  testWidgets('a flick keeps turning, then comes to rest', (t) async {
    final s = await mount(t);
    final yaw = s.yaw;
    await t.fling(find.byType(SceneView), const Offset(-200, 0), 1500);
    final released = s.yaw;
    expect(released, greaterThan(yaw));
    await t.pump(const Duration(milliseconds: 100));
    expect(s.yaw, greaterThan(released), reason: 'coasting after release');
    await t.pumpAndSettle();
    final rest = s.yaw;
    await t.pump(const Duration(milliseconds: 200));
    expect(s.yaw, rest);
  });
}
