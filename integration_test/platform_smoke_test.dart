import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/ui/demand/from_design_page.dart';
import 'package:yusal/platform/ui/home/publish_post_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native project save, recruit, publish draft and cancel leave',
      (t) async {
    final store = ProjectStore();
    var sequence = 0;
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);
    final id = await store.createProject(createHouse(
        name: 'Yusal smoke test',
        width: 10000,
        depth: 13000,
        columns: 1,
        rows: 1,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        newId: () => 'smoke_${sequence++}'));
    try {
      AppSettings.instance.lang = AppLang.zh;
      expect((await store.openProject(id)).meta.name, 'Yusal smoke test');
      await t.pumpWidget(ProviderScope(
          child: HouseApp(
              repos: MockBackend(latency: Duration.zero), store: store)));
      await t.pumpAndSettle();
      expect(find.textContaining('演示模式'), findsOneWidget);
      await t.tap(find.text('我的房子').last);
      await t.pumpAndSettle();
      // The design list is read from disk off the test clock.
      for (var i = 0;
          i < 50 && find.text('Yusal smoke test').evaluate().isEmpty;
          i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      final row = find
          .ancestor(
              of: find.text('Yusal smoke test'), matching: find.byType(Row))
          .first;
      final menu = find.descendant(of: row, matching: find.byTooltip('项目操作'));
      // Finding builders is on the card itself; publishing is in its menu.
      await t.ensureVisible(find.text('找施工方'));
      await t.tap(find.text('找施工方'));
      await t.pumpAndSettle();
      expect(find.byType(FromDesignPage), findsOneWidget);
      expect(find.byType(PublishPostPage), findsNothing);
      await t.tap(find.byTooltip('返回'));
      await t.pumpAndSettle();
      await t.ensureVisible(menu);
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.tap(find.text('发布作品'));
      await t.pumpAndSettle();
      // Set the draft through the field's controller: on the Android
      // emulator the simulated keyboard did not reach this field, and the
      // step under test is leaving with a draft, not typing.
      final titleField = find
          .descendant(
              of: find.byType(PublishPostPage),
              matching: find.byType(TextField))
          .first;
      t.widget<TextField>(titleField).controller!.text = '保留的草稿';
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('返回'));
      await t.pumpAndSettle();
      await t.tap(find.text('继续编辑'));
      await t.pumpAndSettle();
      expect(find.text('保留的草稿'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await store.deleteProject(id);
      await LastOpenProject.write(previous);
    }
  });
}
