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
import 'package:yusal/platform/ui/me/me_page.dart';
import 'package:yusal/platform/ui/showcase/showcase_card.dart';
import 'package:yusal/platform/ui/showcase/showcase_detail_page.dart';
import 'package:yusal/platform/ui/theme.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

MockBackend mock() => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero);

Future<MockBackend> launch(WidgetTester t, {String? as}) async {
  SharedPreferences.setMockInitialValues({});
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
  testWidgets('opens on the feed of published house designs', (t) async {
    await launch(t);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('塔尔加尔 · 哈萨克乡村住宅'), findsOneWidget);
    expect(find.text('卡斯克连 · 两层小楼'), findsOneWidget);
    expect(find.text('招人中'), findsWidgets);
  });

  testWidgets('the hiring category only shows houses with open demands',
      (t) async {
    await launch(t);
    await t.tap(find.text('招人中').first);
    await t.pumpAndSettle();
    expect(find.byType(ShowcaseCard), findsOneWidget);
    expect(find.text('塔尔加尔 · 哈萨克乡村住宅'), findsOneWidget);
  });

  testWidgets('a house shows its story, ratings and the demands it hires for',
      (t) async {
    await launch(t, as: SeedIds.electrician);
    await t.tap(find.text('塔尔加尔 · 哈萨克乡村住宅'));
    await t.pumpAndSettle();
    expect(find.byType(ShowcaseDetailPage), findsOneWidget);
    expect(find.text('这套房子正在招人'), findsOneWidget);
    expect(find.text('130 平米住宅砌墙'), findsOneWidget);
    expect(find.textContaining('锅炉房单独出入口'), findsOneWidget);
    await t.tap(find.text('去报名'));
    await t.pumpAndSettle();
    expect(find.byType(DemandDetailPage), findsOneWidget);
    expect(find.text('报名'), findsWidgets);
  });

  testWidgets('rating a house adds the review to it', (t) async {
    final repos = await launch(t, as: SeedIds.electrician);
    await t.tap(find.text('卡斯克连 · 两层小楼'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('写评价'));
    await t.pumpAndSettle();
    await t.tap(find.text('写评价'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('5'));
    await t.enterText(find.byType(TextField).last, '楼梯位置很好');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '发布'));
    await t.pumpAndSettle();
    expect(find.text('楼梯位置很好'), findsOneWidget);
    final comments = await repos.comments('show_two');
    expect(comments.first.rating, 5);
  });

  testWidgets('the work tab lists the open demands', (t) async {
    await launch(t, as: SeedIds.electrician);
    await t.tap(find.text('招工').last);
    await t.pumpAndSettle();
    expect(find.text('找两名瓦工，按天结算'), findsOneWidget);
    await t.tap(find.text('找两名瓦工，按天结算'));
    await t.pumpAndSettle();
    expect(find.byType(DemandDetailPage), findsOneWidget);
  });

  testWidgets('the design tab keeps the design home', (t) async {
    await launch(t);
    await t.tap(find.text('我的设计').last);
    await t.pumpAndSettle();
    expect(find.text('自建房设计工具'), findsOneWidget);
  });

  testWidgets('night mode switches the whole platform to the dark palette',
      (t) async {
    await launch(t, as: SeedIds.owner);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await t.tap(find.text('夜间'));
    await t.pumpAndSettle();
    final ctx = t.element(find.byType(MePage));
    expect(YTokens.of(ctx).dark, isTrue);
    AppSettings.instance.theme = ThemeChoice.auto;
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
