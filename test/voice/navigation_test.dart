import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/main.dart';
import 'package:yusal/data/mock/mock_seed.dart';
import 'package:yusal/features/demand/demand_detail_page.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/executor.dart';
import 'package:yusal/voice/screen.dart';

import '../platform/explore_test.dart' show launch;

void main() {
  final executor = ActionExecutor(appActions, confirm: (_, __) async => true);

  test('every registered action is well formed', () {
    expect(appActions.problems(), isEmpty);
  });

  testWidgets('tabs switch by name and the shell reports the one showing',
      (t) async {
    final (repos, _) = await launch(t, as: SeedIds.owner);
    expect(VoiceScreens.current!.screenId, 'shell.explore');

    Future<ActionResult> run(String id, Map<String, Object?> args,
            {List<Entity> entities = const []}) =>
        executor.run(
            id,
            args,
            ActionContext(
                repos: repos,
                loggedIn: true,
                entities: entities,
                page: VoiceScreens.current?.context),
            source: Source.voice);

    expect((await run('nav.tab', {'tab': 'messages'})).ok, isTrue);
    await t.pumpAndSettle();
    expect(VoiceScreens.current!.screenId, 'shell.messages');

    // Opening something on screen by its alias.
    const demand = Entity('demand', 'no-such-demand', alias: 'd1');
    expect(
        (await run('nav.open', {'kind': 'demand', 'ref': 'd9'},
                entities: [demand]))
            .code,
        ActionCodes.unknownEntity);
    final opened = await run('nav.open', {'kind': 'demand', 'ref': 'd1'},
        entities: [demand]);
    expect(opened.changed, ['no-such-demand']);
    await t.pumpAndSettle();
    expect(find.byType(DemandDetailPage), findsOneWidget);
    // The page on top has no contract yet, so the shell under it is not
    // offered as the current screen.
    expect(VoiceScreens.current, isNull);

    // A tab by name from a pushed page returns to the shell first.
    expect((await run('nav.tab', {'tab': 'houses'})).ok, isTrue);
    await t.pumpAndSettle();
    expect(find.byType(DemandDetailPage), findsNothing);
    expect(VoiceScreens.current!.screenId, 'shell.houses');
  });

  testWidgets('a dialog hides the page under it from voice', (t) async {
    await launch(t, as: SeedIds.owner);
    showDialog<void>(
        context: appNavigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('?')));
    await t.pumpAndSettle();
    expect(VoiceScreens.current, isNull);

    appNavigator.currentState!.pop();
    await t.pumpAndSettle();
    expect(VoiceScreens.current!.screenId, 'shell.explore');
  });
}
