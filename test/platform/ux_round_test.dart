import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/ui/shell.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/cards.dart';
import 'package:yusal/platform/ui/chat/inbox_page.dart';
import 'package:yusal/platform/ui/components.dart';
import 'package:yusal/platform/ui/demand/from_design_page.dart';
import 'package:yusal/platform/ui/design/plan_viewer.dart';
import 'package:yusal/platform/ui/home/publish_post_page.dart';
import 'package:yusal/platform/ui/houses/workspace_page.dart';
import 'package:yusal/platform/ui/theme.dart';
import 'package:yusal/platform/ui/widgets.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;
import 'explore_test.dart' show launch;

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const phone = Size(390, 844);

/// A house of mine in the local store, so "My houses" has a card.
Future<void> addDesign(WidgetTester t, ProjectStore store) async {
  var id = 0;
  await store.createProject(createHouse(
      name: '我的测试设计',
      width: 10000,
      depth: 13000,
      columns: 1,
      rows: 1,
      timestamp: '2026-11-04T00:00:00Z',
      newId: () => 'ux_${id++}'));
}

void main() {
  tearDown(() {
    AppSettings.instance.lang = AppLang.zh;
    AppSettings.instance.theme = ThemeChoice.auto;
  });

  group('contrast', () {
    test('text on any fill of either theme reaches 4.5 : 1', () {
      for (final t in [YTokens.light, YTokens.night]) {
        for (final fill in [t.ink, t.accent, t.ok, t.crit, t.info]) {
          expect(contrast(onFill(fill), fill), greaterThanOrEqualTo(4.5),
              reason: 'onFill on $fill (${t.dark ? 'night' : 'day'})');
        }
        expect(contrast(t.ink, t.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(t.muted, t.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(t.muted, t.card), greaterThanOrEqualTo(4.5));
        expect(contrast(t.accentInk, t.accent), greaterThanOrEqualTo(4.5));
      }
    });

    testWidgets('a filled pill is readable at night', (t) async {
      await t.pumpWidget(MaterialApp(
          theme: buildPlatformTheme(YTokens.night),
          home: Builder(
              builder: (context) => Scaffold(
                  body: StatusPill('求点评',
                      color: YTokens.of(context).ink, filled: true)))));
      final text = t.widget<Text>(find.text('求点评'));
      expect(contrast(text.style!.color!, YTokens.night.ink),
          greaterThanOrEqualTo(4.5));
    });
  });

  testWidgets('pills and settings rows are at least 44 px tall to touch',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: buildPlatformTheme(YTokens.light),
        home: Scaffold(
            body: Column(children: [
          Row(children: [
            FilterPill(label: '地区', selected: false, onTap: () {}),
          ]),
          SettingsGroup(children: [
            SettingsRow(icon: Icons.language, title: '语言', onTap: () {}),
          ]),
        ]))));
    expect(t.getSize(find.byType(FilterPill)).height,
        greaterThanOrEqualTo(yTouch));
    expect(t.getSize(find.byType(SettingsRow)).height,
        greaterThanOrEqualTo(yTouch));
  });

  testWidgets('a guest on Messages is offered to sign in, not to retry',
      (t) async {
    await launch(t, size: phone);
    await t.tap(find.byType(ShellBarTab).at(2));
    await t.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(InboxPage), matching: find.byType(SignInPrompt)),
        findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.byTooltip('全部已读'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('signed in, Messages has its tabs and "mark all read"',
      (t) async {
    await launch(t, as: SeedIds.owner, size: phone);
    await t.tap(find.byType(ShellBarTab).at(2));
    await t.pumpAndSettle();
    expect(find.byType(SignInPrompt), findsNothing);
    expect(find.byTooltip('全部已读'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(InboxPage), matching: find.byType(TabBar)),
        findsOneWidget);
  });

  testWidgets('the demo notice is one line and explains itself on tap',
      (t) async {
    await launch(t, size: phone);
    final notice = find.byKey(const Key('demo-notice'));
    expect(notice, findsOneWidget);
    expect(t.getSize(notice).height, lessThan(40));
    await t.tap(notice);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('知道了'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final lang in AppLang.values) {
    testWidgets('system texts follow the app language ($lang)', (t) async {
      await launch(t, route: '/h/post_aigerim', size: phone);
      AppSettings.instance.setLang(lang);
      await t.pumpAndSettle();
      final l = MaterialLocalizations.of(t.element(find.byType(Scaffold).first));
      expect(
          l.backButtonTooltip,
          switch (lang) {
            AppLang.zh => '返回',
            AppLang.ru => 'Назад',
            AppLang.kk => 'Артқа',
          });
    });
  }

  group('My houses', () {
    testWidgets('a design shows Continue and Find builders on its card',
        (t) async {
      final (_, store) = await launch(t, size: phone);
      await addDesign(t, store);
      await t.tap(find.byType(ShellBarTab).at(1));
      await t.pumpAndSettle();
      expect(find.text('我的测试设计'), findsOneWidget);
      expect(find.text('继续设计'), findsOneWidget);
      expect(find.text('找施工方'), findsOneWidget);
      // One title, no second drafting header.
      expect(find.text('我的房子'), findsNWidgets(2)); // title + bar label
      expect(find.text('自建房设计工具'), findsNothing);

      await t.tap(find.text('找施工方'));
      await t.pumpAndSettle();
      expect(find.byType(FromDesignPage), findsOneWidget);
      await t.tap(find.byTooltip('返回'));
      await t.pumpAndSettle();

      await t.tap(find.byTooltip('项目操作'));
      await t.pumpAndSettle();
      expect(find.text('导出设计文件'), findsOneWidget);
      expect(find.text('删除设计'), findsOneWidget);
      await t.tap(find.text('发布作品'));
      await t.pumpAndSettle();
      expect(find.byType(PublishPostPage), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('with no designs the example is offered', (t) async {
      await launch(t, size: phone);
      await t.tap(find.byType(ShellBarTab).at(1));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('designs-empty')), findsOneWidget);
      expect(find.byKey(const Key('designs-new')), findsOneWidget);
      expect(find.text('打开这个示例'), findsOneWidget);
    });

    testWidgets('the list and the new-design dialog are in Russian',
        (t) async {
      AppSettings.instance.lang = AppLang.ru;
      final (_, store) = await launch(t, size: phone, lang: AppLang.ru);
      await addDesign(t, store);
      await t.tap(find.byType(ShellBarTab).at(1));
      await t.pumpAndSettle();
      expect(find.text('Мои проекты'), findsOneWidget);
      expect(find.text('Продолжить'), findsOneWidget);
      expect(find.text('Найти мастеров'), findsOneWidget);
      await t.tap(find.byKey(const Key('designs-new')));
      await t.pumpAndSettle();
      expect(find.text('Название проекта'), findsOneWidget);
      expect(find.text('Ширина (слева направо)'), findsOneWidget);
      // Nothing Kazakh is left in the dialog.
      expect(find.textContaining('Жоба'), findsNothing);
      await t.tap(find.text('Отмена'));
      await t.pumpAndSettle();
      // The other ways to start are one sheet away, in Russian too.
      await t.tap(find.byKey(const Key('designs-template')));
      await t.pumpAndSettle();
      expect(find.text('С чего начнём?'), findsOneWidget);
      expect(find.text('Нарисовать контур'), findsOneWidget);
      expect(find.text('Казахский сельский дом'), findsOneWidget);
      expect(find.textContaining('Үлгі'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('deleting a design asks first and removes it', (t) async {
      final (_, store) = await launch(t, size: phone);
      await addDesign(t, store);
      await t.tap(find.byType(ShellBarTab).at(1));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('项目操作'));
      await t.pumpAndSettle();
      await t.tap(find.text('删除设计'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect((await store.listProjects()).length, 1);
      await t.tap(find.widgetWithText(FilledButton, '删除'));
      await t.pumpAndSettle();
      expect((await store.listProjects()), isEmpty);
      expect(find.byKey(const Key('designs-empty')), findsOneWidget);
    });
  });

  testWidgets('workspace tabs scroll on a phone in Russian instead of cutting',
      (t) async {
    await launch(t, as: SeedIds.owner, size: phone, lang: AppLang.ru);
    await t.tap(find.byType(ShellBarTab).at(1));
    await t.pumpAndSettle();
    final card = find.byWidgetPredicate(
        (w) => w.key?.toString().contains('house-card-') ?? false);
    await t.tap(card.first);
    await t.pumpAndSettle();
    expect(find.byType(HouseWorkspacePage), findsOneWidget);
    final bar = t.widget<TabBar>(find.descendant(
        of: find.byType(HouseWorkspacePage), matching: find.byType(TabBar)));
    expect(bar.isScrollable, isTrue);
    // Every label is laid out at its full width.
    for (final label in ['Поиск', 'Соглашения', 'Стройка']) {
      final text = find.descendant(
          of: find.byType(TabBar), matching: find.textContaining(label));
      expect(text, findsOneWidget);
      final box = t.renderObject<RenderBox>(text);
      expect(box.size.width, greaterThan(0));
      expect(t.widget<Text>(text).overflow, isNot(TextOverflow.ellipsis));
    }
    expect(t.takeException(), isNull);
  });

  group('demand card', () {
    Demand demandOf(MockBackend b, bool withDrawing) => b.demands.values
        .firstWhere((d) => (d.current.snapshotId != null) == withDrawing);

    Future<void> pump(WidgetTester t, Demand d, MockBackend b) =>
        t.pumpWidget(MaterialApp(
            theme: buildPlatformTheme(YTokens.light),
            home: Builder(
                builder: (context) => _scope(
                    b,
                    Scaffold(
                        body: SizedBox(
                            width: 350,
                            child: DemandCard(demand: d, onTap: () {})))))));

    testWidgets('without a drawing it has no picture, only its facts',
        (t) async {
      final b = _backend();
      final d = demandOf(b, false);
      await pump(t, d, b);
      await t.pumpAndSettle();
      expect(find.byType(Cover), findsNothing);
      expect(find.byType(PlanCover), findsNothing);
      expect(find.text(d.current.title), findsOneWidget);
    });

    testWidgets('with a drawing the plan is the picture', (t) async {
      final b = _backend();
      final d = demandOf(b, true);
      await pump(t, d, b);
      await t.pumpAndSettle();
      expect(find.byType(PlanCover), findsOneWidget);
    });
  });

  testWidgets(
      'on a phone the design tool keeps language and theme in its menu, '
      'and all three languages can be chosen', (t) async {
    t.view.physicalSize = phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var id = 0;
    final doc = createHouse(
        name: '手机上的设计',
        width: 10000,
        depth: 13000,
        columns: 1,
        rows: 1,
        timestamp: '2026-11-04T00:00:00Z',
        newId: () => 'ed_${id++}');
    final store = ProjectStore(fileSystem: MemoryFiles());
    final pid = await store.createProject(doc);
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => AppScope(child: child!),
        home: HouseEditor(entry: ProjectEntry(pid, doc), store: store)));
    await t.pumpAndSettle();
    // The two switches no longer sit in the header's scrolling row.
    expect(find.text('Қазақша'), findsNothing);
    expect(find.text('Русский'), findsNothing);
    await t.tap(find.byTooltip('更多操作'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('语言'));
    await t.pumpAndSettle();
    for (final name in ['Қазақша', 'Русский', '中文'])
      expect(find.text(name), findsOneWidget);
    await t.tap(find.text('Русский'));
    await t.pumpAndSettle();
    expect(AppSettings.instance.lang, AppLang.ru);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });

  test('demo content is written in the language the app starts in', () async {
    AppSettings.instance.lang = AppLang.ru;
    final ru = _backend();
    expect((await ru.post('post_aigerim'))!.title,
        'Одноэтажный кирпичный дом для родителей');
    AppSettings.instance.lang = AppLang.kk;
    final kk = _backend();
    expect((await kk.post('post_aigerim'))!.title,
        'Ата-анама арналған бір қабатты кірпіш үй');
    AppSettings.instance.lang = AppLang.zh;
    final zh = _backend();
    expect((await zh.post('post_aigerim'))!.title, '给父母盖的一层砖房');
    // No Chinese is left in any Russian title, story or name.
    final cjk = RegExp(r'[一-鿿]');
    for (final p in await ru.feed(const FeedFilter())) {
      expect(cjk.hasMatch(p.title + p.story), isFalse, reason: p.title);
    }
    for (final p in await ru.searchProfiles(const ProfileFilter())) {
      expect(cjk.hasMatch(p.name + p.bio), isFalse, reason: p.name);
    }
    for (final d in await ru.searchDemands(const DemandFilter())) {
      expect(cjk.hasMatch(d.current.title + d.current.locality), isFalse,
          reason: d.current.title);
    }
  });
}

MockBackend _backend() => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero);

Widget _scope(MockBackend b, Widget child) => PlatformScope(
    repos: b, store: ProjectStore(fileSystem: MemoryFiles()), child: child);
