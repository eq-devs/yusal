import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/data/mock/mock_seed.dart';
import 'package:yusal/domain/models.dart';
import 'package:yusal/domain/rules.dart';
import 'package:yusal/features/demand/demand_detail_page.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/actions_demand.dart';
import 'package:yusal/voice/executor.dart';
import 'package:yusal/voice/screen.dart';

import '../platform/mock_backend_test.dart' show backend;
import '../storage_test.dart' show MemoryFiles;

void main() {
  final b = backend();
  var approve = true;
  final executor =
      ActionExecutor(appActions, confirm: (_, __) async => approve);

  ActionContext ctx() => VoiceScreens.context(b, loggedIn: true);
  Set<String> offered() => {
        for (final a in appActions.offered(ctx()))
          if (a.id.startsWith('demand.')) a.id
      };
  Future<ActionResult> say(String id, [Map<String, Object?> args = const {}]) =>
      executor.run(id, args, ctx(), source: Source.voice);

  Future<void> open(WidgetTester t, String id) async {
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        isDemo: true,
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: DemandDetailPage(demandId: id))));
    await t.pumpAndSettle();
  }

  testWidgets(
      'voice is offered what the status allows, the same as the buttons, '
      'and nothing on someone else\'s demand', (t) async {
    b.signInAs(SeedIds.owner);
    final d = b.demands['dem_wall']!;
    expect(d.status, DemandStatus.open);
    await open(t, d.id);
    expect(VoiceScreens.current?.summary, startsWith('demand open'));
    expect(offered(),
        {'demand.pause', 'demand.renew', 'demand.mark_found', 'demand.close'});
    for (final e in DemandEvent.values) {
      expect(demandButton(d.status, e),
          demandMachine.can(d.status, e) && e != DemandEvent.resume);
    }

    approve = false;
    expect((await say('demand.pause')).code, ActionCodes.declined);
    expect(b.demands[d.id]!.status, DemandStatus.open);
    approve = true;
    expect((await say('demand.pause')).ok, isTrue);
    await t.pumpAndSettle();
    expect(b.demands[d.id]!.status, DemandStatus.paused);
    expect(offered(), {'demand.resume', 'demand.mark_found', 'demand.close'});
    // Not offered now, so refused even if the model asks.
    expect((await say('demand.pause')).code, ActionCodes.notAvailable);
    expect(find.text('继续招募'), findsOneWidget);

    b.signInAs(SeedIds.mason);
    await open(t, d.id);
    expect(offered(), isEmpty);
  });
}
