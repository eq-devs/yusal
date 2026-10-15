import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/render3d/scene_view.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'ui_${sequence++}';
  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  FloorPlanPainter painter(WidgetTester t) =>
      t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
  Offset at(WidgetTester t, double x, double y) =>
      t.getTopLeft(canvas) + painter(t).point(x, y, t.getSize(canvas));

  Future<({ProjectStore store, String id})> mount(
      WidgetTester t, HouseDocument doc,
      {Size size = const Size(1280, 900)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => AppScope(child: child!),
        home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      AppSettings.instance.lang = AppLang.zh;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    return (store: store, id: id);
  }

  Future<HouseDocument> saved(WidgetTester t, ProjectStore store, String id) async {
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
    return store.openProject(id);
  }

  HouseDocument plain() => createHouse(
      name: '卡片',
      width: 12000,
      depth: 10000,
      columns: 2,
      rows: 1,
      initialRoom: true,
      timestamp: '2026-10-01T00:00:00Z',
      newId: next);

  HouseDocument village() =>
      createKazakhTemplate('2026-10-01T00:00:00Z', next, names: const {
        'b1': '卧室 1',
        'b2': '卧室 2',
        'cor': '走廊',
        'ent': '门厅',
        'boil': '锅炉房'
      });

  testWidgets('a tapped room shows its card; drawing area and note are edited there',
      (t) async {
    final s = await mount(t, plain());
    await t.tapAt(at(t, 3000, 5000));
    await t.pumpAndSettle();
    expect(painter(t).selectedRoom, isNotNull);
    expect(find.text('图纸标注'), findsOneWidget);
    await t.tap(find.text('—').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '35.5');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('添加说明'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '朝南，冬天暖和');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    final doc = await saved(t, s.store, s.id);
    final info = doc.extras.rooms[painter(t).selectedRoom]!;
    expect(info.labelArea, 3550);
    expect(info.note, '朝南，冬天暖和');
    expect(doc.schemaVersion, 3);
    expect(find.text('朝南，冬天暖和'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('furniture is placed from the palette, dragged, turned and deleted',
      (t) async {
    final s = await mount(t, plain());
    await t.tap(find.byTooltip('家具'));
    await t.pumpAndSettle();
    await t.tap(find.text('沙发'));
    await t.pumpAndSettle();
    await t.tapAt(at(t, 6000, 5000));
    await t.pumpAndSettle();
    var doc = await saved(t, s.store, s.id);
    final sofa = doc.extras.furniture.single;
    expect(sofa.kind, FurnitureKind.sofa);
    expect(painter(t).selectedFurniture, sofa.id);
    // The selected piece follows a drag in browse mode.
    await t.tap(find.text('结束'));
    await t.pumpAndSettle();
    final g = await t.startGesture(at(t, sofa.x + sofa.width / 2, sofa.y + sofa.depth / 2));
    await t.pump();
    await g.moveTo(at(t, sofa.x + sofa.width / 2 + 1000, sofa.y + sofa.depth / 2));
    await t.pump();
    await g.moveTo(at(t, sofa.x + sofa.width / 2 + 2000, sofa.y + sofa.depth / 2));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    doc = await saved(t, s.store, s.id);
    expect(doc.extras.furniture.single.x, closeTo(sofa.x + 2000, 60));
    await t.tap(find.text('旋转 90°'));
    await t.pumpAndSettle();
    doc = await saved(t, s.store, s.id);
    expect(doc.extras.furniture.single.width, sofa.depth);
    await t.tap(find.text('删除'));
    await t.pumpAndSettle();
    doc = await saved(t, s.store, s.id);
    expect(doc.extras.furniture, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('the tape measure reads the distance between two taps', (t) async {
    await mount(t, plain());
    await t.tap(find.text('测距'));
    await t.pumpAndSettle();
    await t.tapAt(at(t, 1000, 1000));
    await t.pumpAndSettle();
    await t.tapAt(at(t, 4000, 5000));
    await t.pumpAndSettle();
    expect(painter(t).measure, hasLength(2));
    expect(find.textContaining('5000 mm'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('switching to Kazakh translates the editor and back', (t) async {
    await mount(t, plain());
    await t.tap(find.text('Қазақша').first);
    await t.pumpAndSettle();
    expect(find.text('2D жоспар'), findsOneWidget);
    expect(find.byTooltip('Қабырға салу'), findsOneWidget);
    await t.tap(find.text('中文').first);
    await t.pumpAndSettle();
    expect(find.text('2D 平面'), findsOneWidget);
    expect(find.byTooltip('墙体'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an issue is located on the plan and user issues are kept',
      (t) async {
    final s = await mount(t, village());
    await t.tap(find.byKey(const ValueKey('tab-iss')));
    await t.pumpAndSettle();
    expect(find.text('隔墙下面没有基础'), findsOneWidget);
    await t.tap(find.text('添加问题'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '确认冻深');
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(find.text('确认冻深'), findsOneWidget);
    await t.tap(find.text('在平面图中定位').first);
    await t.pumpAndSettle();
    expect(painter(t).highlights, isNotEmpty);
    expect(painter(t).foundation, isNotNull,
        reason: 'foundation issues switch the foundation layer on');
    final doc = await saved(t, s.store, s.id);
    expect(doc.extras.issues.single.title, '确认冻深');
    expect(t.takeException(), isNull);
  });

  testWidgets('foundation parameters and the window schedule are editable',
      (t) async {
    final s = await mount(t, village());
    await t.tap(find.byKey(const ValueKey('tab-det')));
    await t.pumpAndSettle();
    await t.tap(find.text('450').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '500');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    var doc = await saved(t, s.store, s.id);
    expect(doc.extras.foundation.width, 500);
    await t.tap(find.byKey(const ValueKey('tab-qty')));
    await t.pumpAndSettle();
    await t.tap(find.text('1600 × 1400'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1700');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1500');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    doc = await saved(t, s.store, s.id);
    expect(
        doc.floors.first.openings
            .any((o) => o.width == 1700 && o.height == 1500),
        true);
    expect(t.takeException(), isNull);
  });

  testWidgets('the walk-through moves with W and walls stop the walker',
      (t) async {
    await mount(t, village());
    await t.tap(find.byKey(const ValueKey('tab-walk')));
    await t.pumpAndSettle();
    final state = t.state<SceneViewState>(find.byType(SceneView));
    final z0 = state.wz;
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    for (var i = 0; i < 30; i++) await t.pump(const Duration(milliseconds: 50));
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await t.pump(const Duration(milliseconds: 50));
    expect(state.wz, lessThan(z0 - 1), reason: 'walked toward the house');
    // Keep walking into the front wall beside the door: it stops us.
    state.standAt(2000, -1500, 0, 0);
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    for (var i = 0; i < 60; i++) await t.pump(const Duration(milliseconds: 50));
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await t.pump(const Duration(milliseconds: 50));
    expect(state.wz, greaterThan(state.model.depth - 0.05),
        reason: 'the exterior wall blocks the way');
    expect(t.takeException(), isNull);
  });
}
