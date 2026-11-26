// The create-house flow moves like one thing: the size form is the next
// page of the start sheet, a design opens out of its card, and the card
// of a selection rises in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/editor/widgets/dock_sheet.dart';
import 'package:yusal/features/shared/motion/motion.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'storage_test.dart' show MemoryFiles;

void main() {
  Future<ProjectStore> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = ProjectStore(fileSystem: MemoryFiles());
    await t.pumpWidget(
        ProviderScope(child: MaterialApp(home: HouseHome(store: store))));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
      await t.pumpAndSettle();
    });
    return store;
  }

  testWidgets('the size form is a page of the start sheet, with a way back',
      (t) async {
    await mount(t);
    await t.tap(find.text('新建设计'));
    await t.pumpAndSettle();
    await t.tap(find.text('按长宽新建'));
    await t.pumpAndSettle();
    // Still the one bottom sheet: no dialog was opened for the form.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('开始设计'), findsOneWidget);
    expect(find.text('怎么开始？'), findsNothing);
    await t.tap(find.byKey(const Key('start-back')));
    await t.pumpAndSettle();
    expect(find.text('怎么开始？'), findsOneWidget);
    expect(find.text('开始设计'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('starting from a size opens the editor out of the outline',
      (t) async {
    final store = await mount(t);
    await t.tap(find.text('新建设计'));
    await t.pumpAndSettle();
    await t.tap(find.text('按长宽新建'));
    await t.pumpAndSettle();
    await t.tap(find.text('开始设计'));
    await t.pumpAndSettle();
    expect(await store.listProjects(), hasLength(1));
    final route = ModalRoute.of(t.element(find.byType(HouseEditor)));
    expect(route, isA<ZoomPageRoute<void>>());
    expect(t.takeException(), isNull);
  });

  testWidgets('a zoom route with no touched card is the usual slide',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(ZoomPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('page')))),
                child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    // No card was marked, so nothing is being scaled into place.
    expect(
        find.ancestor(of: find.text('page'), matching: find.byType(FittedBox)),
        findsNothing);
    await t.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('a touched card grows into the page and back', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomLeft,
                child: Builder(
                    builder: (context) => ZoomSource(
                        child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                                ZoomPageRoute<void>(
                                    builder: (_) => const Scaffold(
                                        body: Center(child: Text('page'))))),
                            child: const SizedBox(
                                width: 100,
                                height: 80,
                                child: Text('card')))))))));
    await t.tap(find.text('card'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    final early = t.getSize(find
        .ancestor(of: find.text('page'), matching: find.byType(FittedBox))
        .first);
    expect(early.width, lessThan(600), reason: 'still growing from the card');
    await t.pumpAndSettle();
    expect(
        find.ancestor(of: find.text('page'), matching: find.byType(FittedBox)),
        findsNothing,
        reason: 'the settled page is not wrapped any more');
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    expect(find.text('card'), findsOneWidget);
  });

  testWidgets('the card of a selected room fades into the sheet that stays',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var n = 0;
    final store = ProjectStore(fileSystem: MemoryFiles());
    final doc = createKazakhTemplate('2026-11-17T00:00:00Z', () => 'id${n++}');
    final id = await store.createProject(doc);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: HouseEditor(entry: ProjectEntry(id, doc), store: store))));
    await t.pumpAndSettle();
    final sheet = t.state(find.byType(DockSheet));
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    final painter =
        t.widget<CustomPaint>(canvas.first).painter! as FloorPlanPainter;
    await t.tapAt(t.getTopLeft(canvas.first) +
        painter.point(doc.footprint.width * 0.3, doc.footprint.depth * 0.3,
            t.getSize(canvas.first)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    // The same sheet, not a new one sliding up.
    expect(t.state(find.byType(DockSheet)), same(sheet));
    double fade() => t
        .widget<FadeTransition>(find
            .ancestor(
                of: find.byKey(const Key('room-use')),
                matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;
    expect(fade(), lessThan(1), reason: 'the card fades in');
    await t.pumpAndSettle();
    expect(fade(), 1);
    await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
    await t.pumpAndSettle();
  });
}
