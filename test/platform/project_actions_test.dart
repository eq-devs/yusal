import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/ui/demand/from_design_page.dart';
import 'package:yusal/platform/ui/home/publish_post_page.dart';
import 'package:yusal/storage/project_store.dart';
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
    await t.pumpWidget(
        ProviderScope(child: HouseApp(repos: backend, store: store)));
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
