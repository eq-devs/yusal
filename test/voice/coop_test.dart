import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/data/mock/mock_seed.dart';
import 'package:yusal/domain/models.dart';
import 'package:yusal/domain/rules.dart';
import 'package:yusal/features/coop/coop_page.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/executor.dart';
import 'package:yusal/voice/screen.dart';

import '../platform/mock_backend_test.dart' show backend, terms;
import '../storage_test.dart' show MemoryFiles;

void main() {
  testWidgets(
      'voice is offered what each side can do with the cooperation now, '
      'and only that', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final b = backend()..signInAs(SeedIds.owner);
    final executor = ActionExecutor(appActions, confirm: (_, __) async => true);
    final coop = await b.invite('app_team_wall', terms());

    Set<String> offered() => {
          for (final a
              in appActions.offered(VoiceScreens.context(b, loggedIn: true)))
            if (a.id.startsWith('coop.') && !a.id.endsWith('_milestone')) a.id
        };
    Future<ActionResult> say(String id,
            [Map<String, Object?> args = const {}]) =>
        executor.run(id, args, VoiceScreens.context(b, loggedIn: true),
            source: Source.voice);
    Future<void> open(String who) async {
      b.signInAs(who);
      await t.pumpWidget(PlatformScope(
          repos: b,
          store: ProjectStore(fileSystem: MemoryFiles()),
          isDemo: true,
          child: MaterialApp(
              builder: (_, child) => AppScope(child: child!),
              home: CooperationPage(cooperationId: coop.id))));
      await t.pumpAndSettle();
    }

    await open(SeedIds.owner);
    expect(offered(), {'coop.revoke'});
    await open(SeedIds.team);
    expect(offered(), {'coop.confirm', 'coop.decline'});
    expect((await say('coop.confirm')).ok, isTrue);
    await t.pumpAndSettle();
    expect(b.cooperations[coop.id]!.status, CooperationStatus.confirmed);
    expect(offered(), {'coop.request_end'});
    expect(VoiceScreens.current?.summary,
        startsWith('cooperation confirmed, ending none'));

    expect((await say('coop.request_end', {'note': '完工了'})).ok, isTrue);
    await t.pumpAndSettle();
    expect(offered(), isEmpty); // Waiting for the owner.
    await open(SeedIds.owner);
    expect(offered(), {'coop.confirm_end', 'coop.dispute_end'});
    expect((await say('coop.dispute_end', {'note': '还差收尾'})).ok, isTrue);
    await t.pumpAndSettle();
    expect(b.cooperations[coop.id]!.endPhase, EndPhase.disputed);
    expect(offered(), {'coop.request_end'});
    // What the page and voice offer is one rule.
    expect(coopMoves(b.cooperations[coop.id]!, SeedIds.owner),
        {CoopMove.requestEnd});
  });

  testWidgets('voice asks for and answers inspections in order', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final b = backend()..signInAs(SeedIds.owner);
    final executor = ActionExecutor(appActions, confirm: (_, __) async => true);
    final coop = await b.invite('app_team_wall', terms());
    b.signInAs(SeedIds.team);
    await b.confirm(coop.id);

    Set<String> offered() => {
          for (final a
              in appActions.offered(VoiceScreens.context(b, loggedIn: true)))
            if (a.id.endsWith('_milestone')) a.id
        };
    Future<ActionResult> say(String id,
            [Map<String, Object?> args = const {}]) =>
        executor.run(id, args, VoiceScreens.context(b, loggedIn: true),
            source: Source.voice);
    Future<void> open(String who) async {
      b.signInAs(who);
      await t.pumpWidget(PlatformScope(
          repos: b,
          store: ProjectStore(fileSystem: MemoryFiles()),
          isDemo: true,
          child: MaterialApp(
              builder: (_, child) => AppScope(child: child!),
              home: CooperationPage(cooperationId: coop.id))));
      await t.pumpAndSettle();
    }

    MilestoneStatus status(int i) =>
        b.cooperations[coop.id]!.milestones[i].status;

    await open(SeedIds.team);
    expect(offered(), {'coop.request_milestone'});
    // A walls contract starts at the walls stage.
    expect(VoiceScreens.current?.summary, contains('milestone walls planned'));
    expect((await say('coop.request_milestone', {'note': '墙砌完了'})).ok, isTrue);
    await t.pumpAndSettle();
    expect(status(0), MilestoneStatus.requested);
    expect(offered(), isEmpty); // The owner's turn.

    await open(SeedIds.owner);
    expect(offered(), {'coop.accept_milestone', 'coop.dispute_milestone'});
    expect((await say('coop.dispute_milestone', {'note': '有裂缝'})).ok, isTrue);
    await t.pumpAndSettle();
    expect(status(0), MilestoneStatus.disputed);
    expect(offered(), isEmpty);

    await open(SeedIds.team);
    expect((await say('coop.request_milestone')).ok, isTrue);
    await open(SeedIds.owner);
    expect((await say('coop.accept_milestone')).ok, isTrue);
    await t.pumpAndSettle();
    expect(status(0), MilestoneStatus.accepted);
    // The contract covers walls only, so no inspection is left to ask for.
    await open(SeedIds.team);
    expect(VoiceScreens.current?.summary, isNot(contains('milestone')));
    expect(offered(), isEmpty);
  });
}
