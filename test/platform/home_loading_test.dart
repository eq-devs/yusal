import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

class CountingBackend extends MockBackend {
  CountingBackend() : super(latency: Duration.zero);
  int feedCalls = 0;
  bool failFeed = false;
  @override
  Future<List<HousePost>> feed(FeedFilter filter) {
    feedCalls++;
    if (failFeed) return Future.error(StateError('offline'));
    return super.feed(filter);
  }
}

Future<void> mount(WidgetTester t, CountingBackend backend,
    {double width = 390,
    AppLang lang = AppLang.zh,
    double scale = 1,
    ThemeChoice theme = ThemeChoice.day}) async {
  SharedPreferences.setMockInitialValues({});
  AppSettings.instance.lang = lang;
  AppSettings.instance.theme = theme;
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    t.view.reset();
    t.platformDispatcher.clearTextScaleFactorTestValue();
    AppSettings.instance.lang = AppLang.zh;
    AppSettings.instance.theme = ThemeChoice.auto;
  });
  await t.pumpWidget(ProviderScope(
      child: HouseApp(
          repos: backend, store: ProjectStore(fileSystem: MemoryFiles()))));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('typing queries only after 300 milliseconds', (t) async {
    final backend = CountingBackend();
    await mount(t, backend);
    final initial = backend.feedCalls;
    await t.enterText(find.byType(TextField).first, 'a');
    await t.pump(const Duration(milliseconds: 150));
    await t.enterText(find.byType(TextField).first, 'al');
    await t.pump(const Duration(milliseconds: 299));
    expect(backend.feedCalls, initial);
    await t.pump(const Duration(milliseconds: 1));
    await t.pumpAndSettle();
    expect(backend.feedCalls, initial + 1);
  });
  testWidgets('failed feed uses sliver error and retry recovers', (t) async {
    final backend = CountingBackend()..failFeed = true;
    await mount(t, backend);
    expect(find.text('暂时无法加载房子'), findsOneWidget);
    expect(t.takeException(), isNull);
    backend.failFeed = false;
    await t.tap(find.text('重试'));
    await t.pumpAndSettle();
    expect(find.text('给父母盖的一层砖房'), findsOneWidget);
  });
  testWidgets('failed refresh retains previous houses', (t) async {
    final backend = CountingBackend();
    await mount(t, backend);
    backend.failFeed = true;
    await t.enterText(find.byType(TextField).first, 'test');
    await t.pump(const Duration(milliseconds: 301));
    await t.pumpAndSettle();
    expect(find.text('刷新失败，正在显示上次结果'), findsOneWidget);
    expect(find.text('给父母盖的一层砖房'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('mock account does not claim real phone verification', (t) async {
    final backend = CountingBackend()..signInAs(SeedIds.owner);
    await mount(t, backend, width: 768);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    expect(find.textContaining('演示账号'), findsOneWidget);
    expect(find.textContaining('手机号已验证'), findsNothing);
    expect(find.text('审核后台'), findsNothing);
  });
  for (final width in [360.0, 390.0, 768.0, 1440.0]) {
    for (final lang in AppLang.values) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final theme in [ThemeChoice.day, ThemeChoice.night]) {
          testWidgets('home layout $width $lang scale $scale $theme',
              (t) async {
            await mount(t, CountingBackend(),
                width: width, lang: lang, scale: scale, theme: theme);
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  }
}
