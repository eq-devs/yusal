import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/executor.dart';
import 'package:yusal/voice/screen.dart';

import '../storage_test.dart' show MemoryFiles;

void main() {
  final executor = ActionExecutor(appActions, confirm: (_, __) async => true);
  final repos = MockBackend(
      clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
      latency: Duration.zero,
      seed: false);

  Future<ActionResult> say(String id, [Map<String, Object?> args = const {}]) =>
      executor.run(id, args, VoiceScreens.context(repos, loggedIn: true),
          source: Source.voice);

  Map<String, String> shown(String kind) => {
        for (final e in VoiceScreens.current!.entities)
          if (e.kind == kind) e.alias: e.title
      };

  testWidgets('design actions edit the open house and undo', (t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: '语音',
        width: 10000,
        depth: 8000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-11-14T00:00:00Z',
        newId: () => 'id${sequence++}');
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(
            entry: ProjectEntry('project', doc),
            store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();

    final editor = VoiceScreens.current!;
    expect(editor.screenId, 'editor.plan');
    expect(shown('floor').keys, ['f1']);
    expect(shown('room').keys, ['r1']);
    expect(editor.actions, contains('design.add_floor'));

    // The floor defaults to the one being edited.
    expect((await say('design.add_floor')).ok, isTrue);
    await t.pump();
    expect(shown('floor').keys, ['f1', 'f2']);

    final renamed =
        await say('design.rename_room', {'room': 'r1', 'name': '书房'});
    expect(renamed.changed, hasLength(1));
    await t.pump();
    expect(shown('room'), {'r1': '书房'});

    expect(
        (await say('design.set_room_type', {'room': 'r1', 'type': 'bedroom'}))
            .ok,
        isTrue);
    expect((await say('design.set_size', {'width_mm': 12000})).ok, isTrue);
    await t.pump();

    // A command the design rules refuse comes back as a failure with the
    // reason, and changes nothing.
    final refused = await say('design.set_size', {'width_mm': 1});
    expect(refused.ok, isFalse);
    expect(refused.say['message'], isNotEmpty);

    // Arguments are checked before the editor is touched.
    expect((await say('design.rename_room', {'room': 'r7', 'name': 'x'})).code,
        ActionCodes.unknownEntity);

    // Three changes after the added floor: three undos bring back one
    // unnamed room, a fourth removes the floor, then nothing is left.
    for (var i = 0; i < 3; i++) {
      expect((await say('editor.undo')).ok, isTrue);
      await t.pump();
    }
    expect(shown('room')['r1'], isNot('书房'));
    expect(shown('floor').keys, ['f1', 'f2']);
    expect((await say('editor.undo')).ok, isTrue);
    await t.pump();
    expect(shown('floor').keys, ['f1']);
    expect((await say('editor.undo')).code, ActionCodes.notAvailable);

    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });

  testWidgets('design actions are not offered outside the editor', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(VoiceScreens.current, isNull);
    expect((await say('design.add_floor')).code, ActionCodes.notAvailable);
    expect(
        appActions
            .offered(VoiceScreens.context(repos, loggedIn: true))
            .map((a) => a.id),
        isNot(contains('design.add_floor')));
  });
}
