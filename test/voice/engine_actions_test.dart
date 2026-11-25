import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/voice/actions/actions.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/actions/engine.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/service/storage/project_store.dart';

import '../storage_test.dart' show MemoryFiles;
import '../support/mock/backend.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_clock.dart';

void main() {
  final executor = ActionExecutor(appActions, confirm: (_, __) async => true);
  final repos = MockBackend(
      clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
      latency: Duration.zero,
      seed: false);

  Future<ActionResult> say(String id, [Map<String, Object?> args = const {}]) =>
      executor.run(
          id,
          // Through text, as the assistant's call arrives.
          (jsonDecode(jsonEncode(args)) as Map).cast<String, Object?>(),
          VoiceScreens.context(voiceRepos(repos), loggedIn: true),
          source: Source.voice);

  Future<DesignHost> open(WidgetTester t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: 'Engine',
        width: 10000,
        depth: 8000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-11-14T00:00:00Z',
        newId: () => 'id${sequence++}');
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: HouseEditor(
                entry: ProjectEntry('project', doc),
                store: ProjectStore(fileSystem: MemoryFiles())))));
    await t.pumpAndSettle();
    return VoiceScreens.current! as DesignHost;
  }

  testWidgets('the assistant reads the house and runs any engine command',
      (t) async {
    final host = await open(t);
    expect(VoiceScreens.current!.actions,
        containsAll(['design.command', 'design.describe']));

    final described = await say('design.describe', {'kinds': true});
    expect(described.ok, isTrue);
    jsonEncode(described.say);
    final floor = (described.say['floors']! as List).single as Map;
    expect(floor['alias'], 'f1');
    final room = (floor['rooms'] as List).single as Map;
    expect(room['alias'], 'r1');
    expect(room['id'], host.document.floors.single.rooms.single.id);
    expect(
        (described.say['kinds']! as Map)['utilityKinds'], contains('socket'));

    // A command no other action covers, by what the description named.
    final added = await say('design.command', {
      'kind': 'AddUtility',
      'arguments': {
        'floorId': floor['id'],
        'kind': 'socket',
        'x': 500,
        'y': 500
      }
    });
    expect(added.ok, isTrue, reason: '${added.code} ${added.say}');
    expect(added.changed, hasLength(1));
    expect(host.document.extras.utilities.single.id, added.changed.single);

    // An alias from the screen stands for its id.
    final renamed = await say('design.command', {
      'kind': 'RenameRoom',
      'arguments': {'roomId': 'r1', 'value': 'Study'}
    });
    expect(renamed.ok, isTrue);
    expect(host.document.floors.single.rooms.single.name, 'Study');

    // One step of the editor's own history each.
    expect((await say('editor.undo')).ok, isTrue);
    expect((await say('editor.undo')).ok, isTrue);
    expect(host.document.extras.utilities, isEmpty);
    expect(host.document.floors.single.rooms.single.name, isNot('Study'));
  });

  testWidgets('measure, locate and visit rooms without editing the plan', (t) async {
    final host = await open(t);
    final before = host.document;
    final measured = await say('design.measure_room', {'room': 'r1'});
    expect(measured.ok, isTrue);
    expect(measured.say['clear_area_m2'], greaterThan(0));
    expect(measured.say['min_clear_span_mm'], greaterThan(0));
    expect((await say('editor.view', {'view': 'walk', 'room': 'r1'})).ok, isTrue);
    expect(VoiceScreens.current!.screenId, 'editor.walk');
    expect((await say('editor.view', {'view': 'plan', 'room': 'r1'})).ok, isTrue);
    expect(VoiceScreens.current!.screenId, 'editor.plan');
    expect(identical(host.document, before), isTrue);
    expect((await say('design.split_room', {'room': 'r1', 'wall': 'north_south'})).ok, isTrue);
    final after = host.document;
    final wall = await say('design.locate_shared_wall', {'a': 'r1', 'b': 'r2'});
    expect(wall.ok, isTrue, reason: wall.code);
    expect(wall.say['axis_length_mm'], 8000);
    expect((await say('design.locate_shared_wall', {'a': 'r1', 'b': 'r1'})).code, 'no_shared_wall');
    expect(identical(host.document, after), isTrue);
    expect((await say('editor.undo')).ok, isTrue);
    expect(host.document.floors.single.rooms, hasLength(1));
  });

  testWidgets('shared wall trials are constrained, reversible and bound to one revision', (t) async {
    final host = await open(t);
    expect((await say('design.split_room', {'room':'r1','wall':'north_south'})).ok,isTrue);
    final before = host.document;
    Future<ActionResult> preview([double? min]) => say('design.preview_wall_move', {
      'grow':'r1','shrink':'r2','distance_mm':300, if(min != null) 'min_remaining_m2':min
    });
    Future<ActionResult> finish(String token,String decision) =>
      say('design.finish_wall_preview', {'preview_id':token,'decision':decision});
    expect((await preview(99)).code,'minimum_area_conflict');
    host.beginUndoGroup();
    final trial = await preview();
    expect(trial.ok,isTrue,reason:'${trial.code} ${trial.say}');
    final token = trial.say['preview_id']! as String;
    expect(trial.say['grow_after_m2'] as num,greaterThan(trial.say['grow_before_m2'] as num));
    expect(identical(host.document,before),isTrue);
    expect((await finish(token,'apply')).code,'await_user_confirmation');
    host.endUndoGroup();
    await t.pump();
    expect(find.textContaining(' → '),findsWidgets);
    expect((await finish(token,'cancel')).ok,isTrue);
    expect(identical(host.document,before),isTrue);
    final stale=(await preview()).say['preview_id']! as String;
    expect((await say('design.rename_room',{'room':'r1','name':'Kitchen'})).ok,isTrue);
    expect((await finish(stale,'apply')).code,'stale_preview');
    final fresh=(await preview()).say['preview_id']! as String;
    final oldArea=host.floorBase.roomsById[host.document.floors.first.rooms.first.id]!.clearArea;
    expect((await finish(fresh,'apply')).ok,isTrue);
    expect((await finish(fresh,'apply')).code,'stale_preview');
    expect((await say('editor.undo')).ok,isTrue);
    expect(host.document.floors.first.rooms.first.name,'Kitchen');
    expect(host.floorBase.roomsById[host.document.floors.first.rooms.first.id]!.clearArea,oldArea);
  });

  testWidgets('wall preview prices the same floor finish and a kitchen substitution', (t) async {
    await open(t);
    await say('design.split_room', {'room': 'r1', 'wall': 'north_south'});
    Future<Map> quote() async {
      final r = await say('design.preview_wall_move',
          {'grow': 'r1', 'shrink': 'r2', 'distance_mm': 300});
      expect(r.ok, isTrue);
      return r.say['estimate'] as Map;
    }
    final same = await quote();
    expect(same['delta'], 0);
    expect(same['finish_changes'], isEmpty);
    await say('design.set_room_type', {'room': 'r1', 'type': 'kitchen'});
    final mixed = await quote();
    expect(mixed['delta'], greaterThan(0));
    final changes = mixed['finish_changes'] as Map;
    expect(changes['finishTileArea']['area_change_m2'], greaterThan(0));
    expect(changes['finishArea']['area_change_m2'],
        closeTo(-(changes['finishTileArea']['area_change_m2'] as num), 0.000001));
    expect(mixed['delta'], mixed['after'] - mixed['before']);
    await t.pump();
    expect(find.textContaining('+'), findsWidgets);
  });

  testWidgets('a command it cannot read comes back with how to write it',
      (t) async {
    final host = await open(t);
    final before = host.document;

    final unknown =
        await say('design.command', {'kind': 'Fly', 'arguments': {}});
    expect(unknown.code, ActionCodes.badArgs);

    final bad = await say('design.command', {
      'kind': 'AddUtility',
      'arguments': {'floorId': 'f1', 'kind': 'fountain', 'x': 1, 'y': 1}
    });
    expect(bad.code, badCommandArguments);
    expect(bad.say['message'], contains('kind'));
    expect(((bad.say['parameters']! as Map)['properties'] as Map).keys,
        containsAll(['floorId', 'kind', 'x', 'y']));

    final refused = await say('design.command', {
      'kind': 'SetFloorHeight',
      'arguments': {'floorId': 'f1', 'value': 500}
    });
    expect(refused.code, 'INVALID_VALUE');
    expect(refused.say['message'], isNotEmpty);

    final lost = await say('design.command', {
      'kind': 'RenameRoom',
      'arguments': {'roomId': 'r9', 'value': 'A'}
    });
    expect(lost.code, 'NOT_FOUND');
    expect(identical(host.document, before), isTrue);
  });

  testWidgets('checks and cost come with the description when asked',
      (t) async {
    await open(t);
    final plain = await say('design.describe');
    expect(plain.say.keys, isNot(contains('checks')));
    final full = await say('design.describe', {'checks': true, 'cost': true});
    expect(full.say['checks'], isA<List>());
    expect((full.say['cost']! as Map)['total'], greaterThan(0));
  });

  test('outside the editor neither is offered', () async {
    expect(VoiceScreens.current, isNull);
    expect((await say('design.describe')).code, ActionCodes.notAvailable);
    expect(
        (await say('design.command',
                {'kind': 'ClearSite', 'arguments': <String, Object?>{}}))
            .code,
        ActionCodes.notAvailable);
  });
}
