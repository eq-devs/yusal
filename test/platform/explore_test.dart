import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/demand/publish_page.dart';
import 'package:yusal/platform/ui/discover/discover_page.dart';
import 'package:yusal/platform/ui/home/home_page.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

MockBackend backend() => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero);

Future<(MockBackend, ProjectStore)> launch(WidgetTester t,
    {String? as, String route = '/'}) async {
  SharedPreferences.setMockInitialValues({});
  t.binding.platformDispatcher.defaultRouteNameTestValue = route;
  addTearDown(t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  AppSettings.instance.lang = AppLang.zh;
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repos = backend();
  if (as != null) repos.signInAs(as);
  final store = ProjectStore(fileSystem: MemoryFiles());
  await t
      .pumpWidget(ProviderScope(child: HouseApp(repos: repos, store: store)));
  await t.pumpAndSettle();
  return (repos, store);
}

bool showing<T>(WidgetTester t) =>
    t.widgetList(find.byType(T, skipOffstage: true)).isNotEmpty;

void main() {
  test(
      'starting from a design counts it, tells the author and returns the plan',
      () async {
    final b = backend()..signInAs(SeedIds.mason);
    final plan = await b.reusePost('post_aigerim');
    expect(plan, isNotNull);
    expect((await b.post('post_aigerim'))!.reuseCount, 1);
    b.signInAs(SeedIds.owner);
    final notes = await b.notifications();
    expect(notes.any((n) => n.kind == NoticeKind.postReused), isTrue);
  });

  test('a signed-out visitor can start from a design too', () async {
    final b = backend();
    expect(await b.reusePost('post_erlan'), isNotNull);
    expect((await b.post('post_erlan'))!.reuseCount, 1);
  });

  testWidgets('the bottom bar is Discover, My houses, Messages, Me', (t) async {
    await launch(t);
    for (final label in ['发现', '我的房子', '消息', '我的'])
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
  });

  testWidgets('visitors open Discover on houses, pros open it on work',
      (t) async {
    await launch(t);
    expect(showing<HomePage>(t), isTrue);
    expect(find.text('挑一套，用它开始你的房子'), findsOneWidget);
  });

  testWidgets('a pro opens Discover on work and can switch to people',
      (t) async {
    await launch(t, as: SeedIds.mason);
    final work = find.byWidgetPredicate(
        (w) => w is DiscoverPage && w.people == false,
        skipOffstage: true);
    expect(work, findsOneWidget);
    await t.tap(find.byKey(const Key('explore-seg-2')));
    await t.pumpAndSettle();
    expect(
        find.byWidgetPredicate((w) => w is DiscoverPage && w.people == true,
            skipOffstage: true),
        findsOneWidget);
  });

  testWidgets('＋ offers three owner ways in plus joining as a pro and "find people" opens the form',
      (t) async {
    await launch(t, as: SeedIds.owner);
    await t.tap(find.byKey(const Key('explore-create')));
    await t.pumpAndSettle();
    for (var i = 0; i < 4; i++)
      expect(find.byKey(Key('create-option-$i')), findsOneWidget);
    await t.tap(find.byKey(const Key('create-option-2')));
    await t.pumpAndSettle();
    expect(find.byType(PublishPage), findsOneWidget);
  });

  testWidgets('a visitor starts a house from a public design', (t) async {
    final (repos, store) = await launch(t, route: '/h/post_aigerim');
    final before = (await store.listProjects()).length;
    await t.tap(find.byKey(const Key('post-main-action')));
    await t.pumpAndSettle();
    expect((await store.listProjects()).length, before + 1);
    expect((await repos.post('post_aigerim'))!.reuseCount, 1);
  });
}
