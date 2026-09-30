import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yusal/main.dart' as app;
import 'package:yusal/storage/project_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create template, show 3D, persist preview and reopen',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建设计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一层三间 · 12 × 10 米'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // Wait for native WebP encoding and the route transition.
    for (var i = 0;
        i < 50 && find.byTooltip('平面 / 3D').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('一层三间'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('平面 / 3D'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('恢复视角'), findsOneWidget);
    await tester.tap(find.byTooltip('恢复视角'));
    await tester.pumpAndSettle();
    final store = ProjectStore();
    final projects = await store.listProjects();
    final created = projects.firstWhere((p) => p.document.meta.name == '一层三间');
    expect(created.document.floors.first.rooms.length, 3);
    expect(created.preview, isNotNull,
        reason: 'Native WebP preview must be saved');
    expect(created.preview!.take(4), [82, 73, 70, 70]); // RIFF
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('最近设计'), findsOneWidget);
    await tester.tap(find.text('一层三间').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('平面 / 3D'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('平面 / 3D'));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
