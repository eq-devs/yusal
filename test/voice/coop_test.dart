import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/domain/rules.dart';
import 'package:yusal/platform/ui/coop/coop_page.dart';
import 'package:yusal/platform/ui/scope.dart';
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
            if (a.id.startsWith('coop.')) a.id
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
}
