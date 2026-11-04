import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/houses/my_houses_data.dart';
import 'package:yusal/platform/ui/houses/workspace_page.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;
import 'mock_backend_test.dart' show backend, terms;

/// Owner invites the wall team, the team confirms: a live contract.
Future<Cooperation> liveContract(MockBackend b) async {
  b.signInAs(SeedIds.owner);
  final coop = await b.invite('app_team_wall', terms());
  b.signInAs(SeedIds.team);
  return b.confirm(coop.id);
}

void main() {
  test('a contract starts with four inspection points', () async {
    final c = await liveContract(backend());
    expect(c.milestones.map((m) => m.key),
        ['foundation', 'walls', 'roof', 'finish']);
    expect(c.milestones.fold(0, (s, m) => s + m.percent), 100);
    expect(c.acceptedPercent, 0);
  });

  test('the pro asks for inspection and only the owner can answer', () async {
    final b = backend();
    final c = await liveContract(b);
    await b.requestMilestone(c.id, 0, note: '基础完成');
    await expectLater(
        b.answerMilestone(c.id, 0, true), throwsA(isA<ApiFailure>()));
    b.signInAs(SeedIds.owner);
    expect(
        (await b.notifications())
            .any((n) => n.kind == NoticeKind.milestoneRequested),
        isTrue);
    final done = await b.answerMilestone(c.id, 0, true);
    expect(done.milestones.first.status, MilestoneStatus.accepted);
    expect(done.acceptedPercent, 20);
    await expectLater(
        b.answerMilestone(c.id, 0, true), throwsA(isA<ApiFailure>()));
  });

  test('raising a problem needs a note and can be asked again', () async {
    final b = backend();
    final c = await liveContract(b);
    await b.requestMilestone(c.id, 1);
    b.signInAs(SeedIds.owner);
    await expectLater(
        b.answerMilestone(c.id, 1, false), throwsA(isA<ApiFailure>()));
    final d = await b.answerMilestone(c.id, 1, false, note: '过梁没到位');
    expect(d.milestones[1].status, MilestoneStatus.disputed);
    b.signInAs(SeedIds.team);
    final again = await b.requestMilestone(c.id, 1);
    expect(again.milestones[1].status, MilestoneStatus.requested);
  });

  test('one work log per day, confirmed by the owner', () async {
    final b = backend();
    final c = await liveContract(b);
    await b.logWork(c.id, 3);
    final twice = await b.logWork(c.id, 4, note: '下午加一人');
    expect(twice.workLogs, hasLength(1));
    expect(twice.workLogs.first.headcount, 4);
    await expectLater(b.logWork(c.id, 0), throwsA(isA<ApiFailure>()));
    await expectLater(b.confirmWork(c.id, twice.workLogs.first.id),
        throwsA(isA<ApiFailure>()));
    b.signInAs(SeedIds.owner);
    await expectLater(b.logWork(c.id, 2), throwsA(isA<ApiFailure>()));
    final ok = await b.confirmWork(c.id, twice.workLogs.first.id);
    expect(ok.workLogs.first.confirmed, isTrue);
  });

  test('quote counts do not mark quotes as read', () async {
    final b = backend()..signInAs(SeedIds.owner);
    final before = await b.myQuoteCounts();
    expect(before.values.any((c) => c.unread > 0), isTrue);
    final again = await b.myQuoteCounts();
    expect(again, before);
  });

  test('my houses group demands, quotes and cooperations by design', () async {
    final b = backend();
    await liveContract(b);
    b.signInAs(SeedIds.owner);
    final houses =
        await loadMyHouses(b, ProjectStore(fileSystem: MemoryFiles()));
    expect(houses, isNotEmpty);
    final withCoop = houses.firstWhere((h) => h.cooperations.isNotEmpty);
    expect(withCoop.stage.name, 'building');
    expect(houses.every((h) => h.demands.isNotEmpty), isTrue);
  });

  testWidgets('the owner sees a to-do strip and opens a house workspace',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final b = backend()..signInAs(SeedIds.owner);
    await t.pumpWidget(ProviderScope(
        child: HouseApp(
            repos: b, store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();
    await t.tap(find.text('我的房子').last);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('todo-strip')), findsOneWidget);
    await t.tap(find
        .byWidgetPredicate((w) =>
            w is InkWell &&
            (w.key?.toString().contains('house-card-') ?? false))
        .first);
    await t.pumpAndSettle();
    expect(find.byType(HouseWorkspacePage), findsOneWidget);
    expect(find.text('施工'), findsWidgets);
  });
}
