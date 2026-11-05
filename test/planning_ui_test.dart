import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/render2d/site_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'pu_${sequence++}';
  HouseDocument village() =>
      createKazakhTemplate('2026-10-01T00:00:00Z', next, names: const {
        'b1': '卧室 1',
        'b2': '卧室 2',
        'cor': '走廊',
        'ent': '门厅',
        'boil': '锅炉房'
      });

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

  Future<HouseDocument> saved(
      WidgetTester t, ProjectStore store, String id) async {
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
    return store.openProject(id);
  }

  Future<void> page(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey('tab-$key')));
    await t.pumpAndSettle();
  }

  for (final size in [const Size(1280, 900), const Size(390, 844)])
    testWidgets('every new page opens without layout errors at ${size.width}',
        (t) async {
      await mount(t, village(), size: size);
      for (final key in ['site', 'heat', 'cost', 'build']) {
        await page(t, key);
        expect(t.takeException(), isNull, reason: key);
      }
      for (final lang in AppLang.values) {
        AppSettings.instance.lang = lang;
        await t.pumpAndSettle();
        for (final key in ['heat', 'cost', 'build', 'site']) {
          await page(t, key);
          expect(t.takeException(), isNull, reason: '$key $lang');
        }
      }
    });

  testWidgets('the budget edits a price and the schedule ticks a check',
      (t) async {
    final s = await mount(t, village());
    await page(t, 'cost');
    expect(find.textContaining('造价预算'), findsOneWidget);
    // Concrete: 480 ¥/m³ → 600.
    await t.tap(find.text('480'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '600');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect((await saved(t, s.store, s.id)).extras.cost.prices['concrete'], 600);
    await page(t, 'build');
    await t.tap(find.text('基础'));
    await t.pumpAndSettle();
    await t.tap(find.text('砂砾石垫层分层夯实'));
    await t.pumpAndSettle();
    final doc = await saved(t, s.store, s.id);
    expect(doc.extras.stages.firstWhere((x) => x.key == 'found').checks, [1]);
    expect(doc.schemaVersion, 4);
  });

  testWidgets('the utilities tool lays out a floor and the layer shows it',
      (t) async {
    final s = await mount(t, village());
    await t.tap(find.text('水电').first);
    await t.pumpAndSettle();
    await t.tap(find.text('自动布置本层'));
    await t.pumpAndSettle();
    final painter = t
        .widget<CustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is FloorPlanPainter))
        .painter! as FloorPlanPainter;
    expect(painter.utilities, isNotEmpty);
    final doc = await saved(t, s.store, s.id);
    expect(doc.extras.utilities.length, painter.utilities.length);
  });

  testWidgets('a plot is set up and an outbuilding added on the site page',
      (t) async {
    final s = await mount(t, village());
    await page(t, 'site');
    await t.tap(find.text('设置宅基地'));
    await t.pumpAndSettle();
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SitePlanPainter),
        findsOneWidget);
    await t.tap(find.text('添加设施'));
    await t.pumpAndSettle();
    await t.tap(find.text('牲畜棚'));
    await t.pumpAndSettle();
    final doc = await saved(t, s.store, s.id);
    expect(doc.extras.site!.items.single.kind, SiteKind.barn);
    expect(find.text('院子检查 · ${0}'), findsNothing);
  });

  testWidgets('a corner is cut from the settings and undone', (t) async {
    final doc = createHouse(
        name: 'L',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-10-01T00:00:00Z',
        newId: next);
    final s = await mount(t, doc);
    await t.tap(find.byTooltip('房屋长宽').first);
    await t.pumpAndSettle();
    await t.tap(find.text('切掉一个角（L 形）'));
    await t.pumpAndSettle();
    await t.tap(find.text('切掉'));
    await t.pumpAndSettle();
    var current = await saved(t, s.store, s.id);
    expect(current.floors.single.outside, hasLength(1));
    await t.tap(find.byTooltip('撤销').first);
    await t.pumpAndSettle();
    current = await saved(t, s.store, s.id);
    expect(current.floors.single.outside, isEmpty);
  });
}
