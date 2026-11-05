import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/core/serialization/house_codec.dart';
import 'package:yusal/platform/snapshot/design_snapshot.dart';
import 'package:yusal/platform/ui/design/plan_viewer.dart';
import 'package:yusal/render3d/scene_view.dart';

void main() {
  var n = 0;
  final doc = createTemplate('three', '2026-11-04T00:00:00Z', () => 'p${n++}');
  final snap = buildSnapshot(projectId: 'private', doc: doc,
      stages: const [], lines: const [], summary: 'plan');
  test('published geometry is frozen and excludes private extras', () {
    final loaded = loadHouse(utf8.encode(snap.planJson!)).document!;
    expect(loaded.extras.isEmpty, isTrue);
    expect(loaded.floors, doc.floors);
    expect(encodeHouse(loaded), snap.planJson);
  });
  testWidgets('public attachment opens read only with zoom controls', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PlanAttachment(snapshot: snap)))));
    await t.tap(find.text('打开图纸'));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('重置缩放'), findsOneWidget);
    expect(find.text('图纸 · 只读'), findsOneWidget);
    await t.tap(find.text('3D'));
    await t.pumpAndSettle();
    expect(find.byType(SceneView), findsOneWidget);
    expect(t.widget<SceneView>(find.byType(SceneView)).doc.floors, doc.floors);
    await t.tap(find.text('2D'));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('private attachment cannot be opened', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlanAttachment(snapshot: snap, hidden: true))));
    expect(find.text('打开图纸'), findsNothing);
    expect(find.text('图纸未公开，可联系发布者'), findsOneWidget);
  });
}
