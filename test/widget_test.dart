import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/ui/demand/demand_detail_page.dart';
import 'package:yusal/platform/ui/home/post_page.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

MockBackend mock() => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero);

Future<MockBackend> launch(WidgetTester t,
    {String? as, String route = '/'}) async {
  SharedPreferences.setMockInitialValues({});
  t.binding.platformDispatcher.defaultRouteNameTestValue = route;
  addTearDown(t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  AppSettings.instance.lang = AppLang.zh;
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repos = mock();
  if (as != null) repos.signInAs(as);
  await t.pumpWidget(ProviderScope(
      child: HouseApp(
          repos: repos, store: ProjectStore(fileSystem: MemoryFiles()))));
  await t.pumpAndSettle();
  return repos;
}

void main() {
  testWidgets('opens on the feed of designed houses', (t) async {
    await launch(t);
    expect(find.text('看看大家设计的房子'), findsOneWidget);
    expect(find.text('给父母盖的一层砖房'), findsOneWidget);
    expect(find.text('两层别墅，带车库和露台'), findsOneWidget);
  });

  testWidgets('a house opens with its facts, demands and reviews', (t) async {
    await launch(t, as: SeedIds.roofTeam);
    await t.tap(find.text('给父母盖的一层砖房'));
    await t.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);
    expect(find.text('130 m²'), findsOneWidget);
    expect(find.text('130 平米住宅砌墙'), findsOneWidget);
    expect(find.text('去报名 / 报价'), findsOneWidget);
    await t.tap(find.text('130 平米住宅砌墙'));
    await t.pumpAndSettle();
    expect(find.byType(DemandDetailPage), findsOneWidget);
  });

  testWidgets('a shared house link opens the house for a signed-out visitor',
      (t) async {
    await launch(t, route: '/h/post_aigerim');
    expect(find.byType(PostPage), findsOneWidget);
    expect(find.text('给父母盖的一层砖房'), findsOneWidget);
    expect(find.text('130 m²'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    // No page to go back to: a home button leads to the feed.
    await t.tap(find.byTooltip('首页'));
    await t.pumpAndSettle();
    expect(find.text('看看大家设计的房子'), findsOneWidget);
  });

  testWidgets('an unknown link falls back to the feed', (t) async {
    await launch(t, route: '/h/nope');
    expect(find.text('这栋房子已经不可见'), findsOneWidget);
  });

  testWidgets('the owner sees the recruit action on their own house',
      (t) async {
    await launch(t, as: SeedIds.owner2);
    await t.tap(find.text('两层别墅，带车库和露台'));
    await t.pumpAndSettle();
    expect(find.text('招人'), findsOneWidget);
    expect(find.text('这是你的设计'), findsOneWidget);
  });

  testWidgets('the design tab keeps the design home', (t) async {
    await launch(t);
    await t.tap(find.text('设计').last);
    await t.pumpAndSettle();
    expect(find.text('自建房设计工具'), findsOneWidget);
  });

  testWidgets('the me tab switches language to Russian', (t) async {
    await launch(t, as: SeedIds.owner);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    await t.tap(find.text('Русский'));
    await t.pumpAndSettle();
    expect(find.text('Настройки'), findsOneWidget);
    AppSettings.instance.lang = AppLang.zh;
  });
}
