import 'package:flutter/material.dart';
import '../support/test_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import '../support/mock/mock_backend.dart';
import 'package:yusal/features/demand/pages/from_design.dart';
import 'package:yusal/features/home/pages/publish_post.dart';
import 'package:yusal/service/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

void main() {
  testWidgets('project can recruit without publishing a house post', (t) async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = ProjectStore(fileSystem: MemoryFiles());
    var id = 0;
    await store.createProject(createHouse(
        name: '我的测试设计',
        width: 10000,
        depth: 13000,
        columns: 1,
        rows: 1,
        timestamp: '2026-11-04T00:00:00Z',
        newId: () => 'test_${id++}'));
    final backend = MockBackend(latency: Duration.zero);
    await t.pumpWidget(testApp(backend, store: store));
    await t.pumpAndSettle();
    await t.tap(find.text('我的房子').last);
    await t.pumpAndSettle();
    // Finding builders is on the card itself, not behind the menu.
    await t.tap(find.text('找施工方'));
    await t.pumpAndSettle();
    expect(find.byType(FromDesignPage), findsOneWidget);
    expect(find.byType(PublishPostPage), findsNothing);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('项目操作'));
    await t.pumpAndSettle();
    await t.tap(find.text('发布作品'));
    await t.pumpAndSettle();
    expect(find.byType(PublishPostPage), findsOneWidget);
  });
}
