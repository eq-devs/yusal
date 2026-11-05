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
      await t.tap(find.text('项目').last);
      await t.pumpAndSettle();
      final row = find
          .ancestor(
              of: find.text('Yusal smoke test'), matching: find.byType(Row))
          .first;
      final menu = find.descendant(of: row, matching: find.byTooltip('项目操作'));
      await t.ensureVisible(menu);
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.tap(find.text('找施工方'));
      await t.pumpAndSettle();
      expect(find.byType(FromDesignPage), findsOneWidget);
      expect(find.byType(PublishPostPage), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.tap(find.text('发布作品'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '保留的草稿');
      await t.pageBack();
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
