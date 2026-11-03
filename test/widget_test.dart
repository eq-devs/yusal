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
  testWidgets('opens on discover with the seeded open demands', (t) async {
    await launch(t);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('130 平米住宅砌墙'), findsOneWidget);
    expect(find.text('找两名瓦工，按天结算'), findsOneWidget);
  });

  testWidgets('a demand opens its detail with the apply action', (t) async {
    await launch(t, as: SeedIds.electrician);
    await t.tap(find.text('找两名瓦工，按天结算'));
    await t.pumpAndSettle();
    expect(find.byType(DemandDetailPage), findsOneWidget);
    expect(find.text('报名'), findsWidgets);
  });

  testWidgets('the projects tab keeps the design home', (t) async {
    await launch(t);
    await t.tap(find.text('我的项目').last);
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
