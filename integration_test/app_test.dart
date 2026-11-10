import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/main.dart' as app;
import 'package:yusal/platform/ui/projects/projects_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/geometry/derived_house.dart';

// Runs on a phone or simulator: flutter test integration_test -d <device>.
// Without one, on Linux: flutter create --platforms=linux . (not committed),
// install libgtk-3-dev and xdg-user-dirs, then
// xvfb-run -a flutter test integration_test/app_test.dart -d linux
// (desktop has no WebP encoder, so the preview checks are skipped there).

/// Start the app in Chinese so the finders below match, on the design home
/// (the app opens on 发现). The previous test leaves its design open, and
/// the app would reopen it: forget it first.
Future<void> startApp(WidgetTester tester) async {
  (await SharedPreferences.getInstance()).setString('house-lang', 'zh');
  await LastOpenProject.write(null);
  app.main();
  await tester.pumpAndSettle();
  await tester.tap(find.text('我的房子').last);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // On a phone the less common plan tools sit behind "更多工具".
  final more = find.byTooltip('更多工具');
  if (finder.evaluate().isEmpty && more.evaluate().isNotEmpty) {
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

const tab3d = ValueKey('tab-ext');

/// Creating a design writes it to disk before the editor opens: wait for
/// the editor's tabs.
Future<void> waitForEditor(WidgetTester tester) async {
  for (var i = 0; i < 50 && find.byKey(tab3d).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Open a design from 我的设计 on the 我的房子 tab. The list builds lazily,
/// so scroll to it; the other tabs stay in the tree, so look only inside
/// the houses page.
Future<void> openDesign(WidgetTester tester, String name) async {
  await tester.tap(find.text('我的房子').last);
  await tester.pumpAndSettle();
  final page = find.byType(ProjectsPage);
  final card = find.descendant(of: page, matching: find.text(name));
  await tester.scrollUntilVisible(card.first, 200,
      scrollable:
          find.descendant(of: page, matching: find.byType(Scrollable)).first);
  await tester.pumpAndSettle();
  await tester.tap(card.first);
}

/// The name field of the new-design dialog (the home page behind it has a
/// search field of its own).
final nameField = find.widgetWithText(TextField, '设计名称');

/// Preview images are WebP from flutter_image_compress, which has no
/// desktop implementation: on a desktop run the preview is left out.
final nativePreview = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create template, show 3D, persist preview and reopen',
      (tester) async {
    await startApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('也可以从示例开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一层三间'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // Wait for native WebP encoding and the route transition.
    for (var i = 0; i < 50 && find.byKey(tab3d).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('一层三间'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byKey(tab3d));
    await tester.pumpAndSettle();
    expect(find.byTooltip('适配画面'), findsOneWidget);
    await tester.tap(find.byTooltip('适配画面'));
    await tester.pumpAndSettle();
    final store = ProjectStore();
    final projects = await store.listProjects();
    final created = projects.firstWhere((p) => p.document.meta.name == '一层三间');
    expect(created.document.floors.first.rooms.length, 3);
    if (nativePreview) {
      expect(created.preview, isNotNull,
          reason: 'Native WebP preview must be saved');
      expect(created.preview!.take(4), [82, 73, 70, 70]); // RIFF
    }
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('我的设计'), findsOneWidget);
    await openDesign(tester, '一层三间');
    await tester.pumpAndSettle();
    expect(find.byKey(tab3d), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byKey(tab3d));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
  });
  testWidgets('direct dimensions, partitions, door, 3D and native reopen',
      (tester) async {
    await startApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设计'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField, '交互改造验收');
    await tester.tap(find.text('开始设计'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 50 && find.byKey(tab3d).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(tab3d), findsOneWidget);
    await tapVisible(tester, find.byTooltip('拉线分房'));
    await tester.pumpAndSettle();
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    var painter =
        tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    var origin = tester.getTopLeft(canvas), size = tester.getSize(canvas);
    final line =
        await tester.startGesture(origin + painter.point(6000, 2000, size));
    await line.moveTo(origin + painter.point(6000, 8000, size));
    await line.up();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('拖动划房'));
    await tester.pumpAndSettle();
    painter = tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    origin = tester.getTopLeft(canvas);
    size = tester.getSize(canvas);
    final room = await tester.startGesture(origin + painter.point(0, 0, size));
    await room.moveTo(origin + painter.point(3000, 4000, size));
    await room.up();
    await tester.pumpAndSettle();
    painter = tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    origin = tester.getTopLeft(canvas);
    size = tester.getSize(canvas);
    final door =
        await tester.startGesture(tester.getCenter(find.byTooltip('拖入门')));
    await door.moveBy(const Offset(0, -30));
    await tester.pump();
    // The dragged door lands at its arrow tip, 28 px above the finger.
    await door
        .moveTo(origin + painter.point(8500, 0, size) + const Offset(0, 28));
    await tester.pump();
    await door.up();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('立即保存'));
    await tester.pumpAndSettle();
    final store = ProjectStore();
    final projects = await store.listProjects();
    final created =
        projects.firstWhere((p) => p.document.meta.name == '交互改造验收');
    expect(created.document.floors.first.rooms.length, 3);
    expect(created.document.floors.first.openings.length, 1);
    if (nativePreview) expect(created.preview, isNotNull);
    await tapVisible(tester, find.byKey(tab3d));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openDesign(tester, '交互改造验收');
    await tester.pumpAndSettle();
    expect(find.byKey(tab3d), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('blank canvas sketch creates the exact exterior dimensions',
      (tester) async {
    await startApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设计'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField, '外形草绘验收');
    await tester.ensureVisible(find.text('在画布上拖出外形'));
    await tester.tap(find.text('在画布上拖出外形'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('footprint-sketch-canvas'));
    final size = tester.getSize(canvas), origin = tester.getTopLeft(canvas);
    final scale = math.min(size.width - 48, size.height - 48) / 20000;
    final start = origin + const Offset(30, 30);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + Offset(12000 * scale, 10000 * scale));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用这个外形'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 50 && find.byKey(tab3d).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(tab3d), findsOneWidget);
    final created = (await ProjectStore().listProjects())
        .firstWhere((p) => p.document.meta.name == '外形草绘验收');
    expect(created.document.footprint.width, 12000);
    expect(created.document.footprint.depth, 10000);
    expect(created.document.floors.first.rooms.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'floating tools, continuous walls, hosted door and native v2 reopen',
      (tester) async {
    await startApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设计'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField, '浮层绘墙验收');
    await tester.tap(find.text('开始设计'));
    await tester.pumpAndSettle();
    await waitForEditor(tester);
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    Offset point(double x, double y) {
      final p = tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
      return tester
          .renderObject<RenderBox>(canvas)
          .localToGlobal(p.point(x, y, tester.getSize(canvas)));
    }

    Future<void> drag(double x0, double y0, double x1, double y1) async {
      final g = await tester.startGesture(point(x0, y0));
      await g.moveTo(point(x1, y1));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('墙体'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('独立墙'));
    await tester.pumpAndSettle();
    await drag(6000, 5000, 8000, 5000);
    await drag(8000, 5000, 8000, 8000);
    await drag(8000, 8000, 6000, 8000);
    await drag(6000, 8000, 6000, 5000);
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    final g =
        await tester.startGesture(tester.getCenter(find.byTooltip('拖入门')));
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    await g.moveTo(point(7000, 5000) + const Offset(0, 28));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('墙体调整'));
    await tester.pumpAndSettle();
    await tester.tapAt(point(7000, 5000));
    await tester.pumpAndSettle();
    expect(find.byTooltip('删除墙体'), findsOneWidget);
    await drag(7000, 5000, 7000, 4500);
    await tapVisible(tester, find.byTooltip('立即保存'));
    await tester.pumpAndSettle();
    final entry = (await ProjectStore().listProjects())
        .firstWhere((p) => p.document.meta.name == '浮层绘墙验收');
    expect(entry.document.schemaVersion, 2);
    expect(entry.document.floors.first.explicitWalls, true);
    expect(
        entry.document.floors.first.wallOverrides.whereType<SolidWall>().length,
        4);
    final opening = deriveHouse(entry.document).floors.first.openings.single;
    expect(opening.status, 'ok');
    expect(opening.axis.pos, 4500);
    if (nativePreview) expect(entry.preview, isNotNull);
    await tapVisible(tester, find.byKey(tab3d));
    await tester.pumpAndSettle();
    expect(find.byTooltip('适配画面'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openDesign(tester, '浮层绘墙验收');
    await tester.pumpAndSettle();
    expect(find.byTooltip('墙体'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fixed wall attachments and long-press editing on native touch',
      (tester) async {
    await startApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设计'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField, '接点长按验收');
    await tester.tap(find.text('开始设计'));
    await tester.pumpAndSettle();
    await waitForEditor(tester);
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    Offset point(double x, double y) {
      final painter =
          tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
      return tester
          .renderObject<RenderBox>(canvas)
          .localToGlobal(painter.point(x, y, tester.getSize(canvas)));
    }

    Future<void> drag(double x0, double y0, double x1, double y1) async {
      final g = await tester.startGesture(point(x0, y0));
      await g.moveTo(point(x1, y1));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('墙体'));
    await tester.pumpAndSettle();
    expect(
        (tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter)
            .wallSeed,
        isNull);
    await tester.tapAt(point(3000, 5000));
    await tester.pumpAndSettle();
    expect(
        (tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter)
            .wallSeed,
        isNull);
    await drag(6000, 0, 6000, 4000);
    await drag(6000, 4000, 3000, 4000);
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    final hold = await tester.startGesture(point(6000, 2000));
    await tester.pump(const Duration(milliseconds: 650));
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.byTooltip('调整长度'), findsOneWidget);
    await tester.tap(find.byTooltip('调整长度'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5.0');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('立即保存'));
    await tester.pumpAndSettle();
    final entry = (await ProjectStore().listProjects())
        .firstWhere((e) => e.document.meta.name == '接点长按验收');
    expect(
        entry.document.floors.first.wallOverrides.whereType<SolidWall>().length,
        2);
    final axes =
        resolveFloorAxes(entry.document, entry.document.floors.first.id)!;
    expect(
        entry.document.floors.first.wallOverrides.whereType<SolidWall>().any(
            (w) => resolveAnchor(axes, w.anchor).chain!.nominalLength == 5000),
        true);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openDesign(tester, '接点长按验收');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
