import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/shared/ui/voice_slot.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'storage_test.dart' show MemoryFiles;

/// The phone layout of the design tool: the drawing fills the page under
/// two floating bars, and everything else is one tap away on a sheet.
void main() {
  var n = 0;
  String next() => 'p${n++}';
  final ctx = CommandContext(newId: next, now: () => '2026-11-24T00:00:00Z');

  HouseDocument house({bool twoFloors = false}) {
    var doc = createHouse(
        name: '手机布局',
        width: 10000,
        depth: 12000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
        newId: next);
    if (twoFloors) {
      final r = executeCommand(
          extractDesignState(doc),
          DesignCommand('AddFloor', {'floorId': doc.floors.first.id}),
          ctx) as Applied;
      doc = composeDocument(doc.meta, r.newState);
    }
    return doc;
  }

  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  FloorPlanPainter painter(WidgetTester t) =>
      t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;

  Future<void> mount(WidgetTester t, HouseDocument doc,
      {Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: HouseEditor(entry: ProjectEntry(id, doc), store: store))));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
      await t.pumpAndSettle();
    });
  }

  testWidgets('the drawing has most of the page, under two bars',
      (t) async {
    await mount(t, house());
    // Before: 42% of the height at this size. Now nothing but the two
    // bars takes height from it.
    expect(t.getSize(canvas).height, greaterThan(844 * 0.8));
    // No rows of tools, layer chips or zoom buttons around it.
    expect(find.byTooltip('浏览'), findsNothing);
    expect(find.byTooltip('放大'), findsNothing);
    expect(find.byTooltip('立即保存'), findsNothing);
    // One accent button; the assistant keeps the bottom right corner.
    final add = t.getRect(find.byKey(const Key('plan-add')));
    final orb = t.getRect(find.byType(VoiceSlot));
    expect(orb.left, greaterThan(add.right));
    expect(orb.right, greaterThan(390 - 24));
    expect(orb.center.dy, closeTo(add.center.dy, 2));
    expect(t.takeException(), isNull);
  });

  testWidgets('the selection sheet has three stops and carries the assistant',
      (t) async {
    await mount(t, house());
    await t.tapAt(t.getCenter(canvas));
    await t.pumpAndSettle();
    final grip = find.byKey(const Key('selection-grip'));
    expect(grip, findsOneWidget);
    // It takes the place of the bottom bar; the orb rides on top of it.
    expect(find.byKey(const Key('plan-add')), findsNothing);
    expect(t.getRect(find.byType(VoiceSlot)).bottom,
        lessThanOrEqualTo(t.getRect(grip).top));
    // One line first.
    expect(find.byTooltip('展开'), findsOneWidget);
    final folded = t.getRect(grip).top;
    // Pulled up: the usual card.
    await t.fling(grip, const Offset(0, -60), 900);
    await t.pumpAndSettle();
    expect(find.byTooltip('收起'), findsOneWidget);
    final open = t.getRect(grip).top;
    expect(open, lessThan(folded));
    // Pulled up again: as tall as it gets, never taller than the drawing.
    await t.fling(grip, const Offset(0, -60), 900);
    await t.pumpAndSettle();
    expect(t.getRect(grip).top, lessThanOrEqualTo(open));
    expect(t.getRect(grip).top, greaterThan(56));
    // Pushed down twice: back to one line, not gone.
    await t.fling(grip, const Offset(0, 60), 900);
    await t.pumpAndSettle();
    expect(find.byTooltip('收起'), findsOneWidget);
    await t.fling(grip, const Offset(0, 60), 900);
    await t.pumpAndSettle();
    expect(find.byTooltip('展开'), findsOneWidget);
    expect(t.getRect(grip).top, closeTo(folded, 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('add rises the one bottom sheet; it never closes or dims',
      (t) async {
    await mount(t, house());
    final grip = find.byKey(const Key('dock-grip'));
    final rest = t.getRect(grip).top;
    expect(find.byTooltip('拖动划房'), findsNothing, reason: 'tools below');
    await t.tap(find.byKey(const Key('plan-add')));
    await t.pumpAndSettle();
    // Not a route over the page: the same sheet, risen, the plan live.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('拖动划房'), findsOneWidget);
    final open = t.getRect(grip).top;
    expect(open, lessThan(rest - 100));
    // Furniture is a page inside the sheet, with a way back.
    await t.tap(find.byTooltip('家具'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('dock-back')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('furniture-sofa')));
    await t.pumpAndSettle();
    // The sheet is back at its bar with the piece in hand.
    expect(t.getRect(grip).top, closeTo(rest, 1));
    expect(find.byKey(const Key('dock-back')), findsNothing);
    expect(find.byKey(const Key('tool-done')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the sheet follows the finger and settles on the nearest stop',
      (t) async {
    await mount(t, house());
    final grip = find.byKey(const Key('dock-grip'));
    final rest = t.getRect(grip).top;
    final g = await t.startGesture(t.getCenter(grip));
    await g.moveBy(const Offset(0, -20));
    await g.moveBy(const Offset(0, -60));
    await t.pump();
    // Mid-drag the sheet is where the finger is, not at a stop.
    expect(t.getRect(grip).top, closeTo(rest - 60, 2));
    await t.pump(const Duration(seconds: 1));
    await g.up();
    await t.pumpAndSettle();
    // Let go slowly near the bottom: back down.
    expect(t.getRect(grip).top, closeTo(rest, 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('layers are switches on a sheet, with the ruler and the key',
      (t) async {
    await mount(t, house());
    expect(painter(t).showDimensions, isTrue);
    await t.tap(find.byKey(const Key('plan-layers')));
    await t.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNWidgets(4));
    expect(find.textContaining('承重墙'), findsOneWidget);
    await t.tap(find.widgetWithText(SwitchListTile, '尺寸'));
    await t.pumpAndSettle();
    // The sheet stays up and the drawing changes behind it.
    expect(
        t
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '尺寸'))
            .value,
        isFalse);
    expect(painter(t).showDimensions, isFalse);
    await t.tap(find.text('测距'));
    await t.pumpAndSettle();
    // The ruler is a tool with its own way out.
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byKey(const Key('tool-done')), findsOneWidget);
    await t.tap(find.byKey(const Key('tool-done')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool-done')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the floor is named in the top bar and chosen from its sheet',
      (t) async {
    await mount(t, house(twoFloors: true));
    final pill = find.byKey(const Key('floor-pill'));
    expect(find.descendant(of: pill, matching: find.text('一楼')),
        findsOneWidget);
    await t.tap(pill);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('floor-1')));
    await t.pumpAndSettle();
    expect(find.descendant(of: pill, matching: find.text('二楼')),
        findsOneWidget);
    expect(painter(t).below, isNotNull, reason: 'the floor under shows');
    expect(t.takeException(), isNull);
  });

  testWidgets('an upright tablet gets the same layout', (t) async {
    await mount(t, house(), size: const Size(820, 1180));
    expect(find.byKey(const Key('plan-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-build')), findsNothing);
    await t.tap(find.byKey(const Key('plan-add')));
    await t.pumpAndSettle();
    expect(find.byTooltip('拖动划房'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
