import 'package:flutter/material.dart';
import 'package:yusal/core/house_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  Future<ProjectStore> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final store = ProjectStore(fileSystem: MemoryFiles());
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => AppScope(child: child!),
        home: HouseHome(store: store)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    return store;
  }

  testWidgets('the start sheet offers a size, a sketch and drawn templates',
      (t) async {
    await mount(t);
    await t.tap(find.text('也可以从示例开始'));
    await t.pumpAndSettle();
    expect(find.text('怎么开始？'), findsOneWidget);
    expect(find.text('按长宽新建'), findsOneWidget);
    expect(find.text('在画布上拖出外形'), findsOneWidget);
    for (final name in ['哈萨克乡村住宅', '一层三间', '一层五间', '两层住宅'])
      expect(find.text(name), findsOneWidget);
    await t.tap(find.text('按长宽新建'));
    await t.pumpAndSettle();
    expect(find.text('新建设计'), findsWidgets, reason: 'the size dialog');
    expect(t.takeException(), isNull);
  });

  testWidgets('a size preset fills both fields and shows the area',
      (t) async {
    final store = await mount(t);
    await t.tap(find.text('新建设计'));
    await t.pumpAndSettle();
    await t.tap(find.text('10×13'));
    await t.pump();
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[1].controller!.text, '10');
    expect(fields[2].controller!.text, '13');
    // The roof is picked here too.
    await t.ensureVisible(find.byKey(const ValueKey('new-roof-flat')));
    await t.tap(find.byKey(const ValueKey('new-roof-flat')));
    await t.pump();
    await t.tap(find.text('开始设计'));
    await t.pumpAndSettle();
    final doc = (await store.listProjects()).single.document;
    expect((doc.footprint.width, doc.footprint.depth), (10000, 13000));
    expect(doc.roof.type, RoofType.flat);
  });
}
