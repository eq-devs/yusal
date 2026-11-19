import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/core/analysis/house_analysis.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/actions_design.dart';
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

  testWidgets('openings go on the wall a room has on the side asked for',
      (t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: '门窗',
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
    final host = VoiceScreens.current! as DesignHost;
    expect(shown('opening'), isEmpty);

    // North is up on the plan until the user turns it: the four outer
    // walls are the room's four sides.
    for (final (side, axis) in [
      ('north', '@top'),
      ('east', '@right'),
      ('south', '@bottom'),
      ('west', '@left')
    ]) {
      final added = await say(
          'design.add_opening', {'room': 'r1', 'side': side, 'kind': 'window'});
      expect(added.changed, hasLength(1), reason: side);
      await t.pump();
      final window = host.document.floors.single.openings.last;
      expect(window, isA<WindowOpening>());
      expect(window.anchor.axisId, axis, reason: side);
    }
    expect(shown('opening').keys, ['o1', 'o2', 'o3', 'o4']);

    // With north turned a quarter to point right, east is the bottom wall,
    // as in the opening cards' facingOf.
    final east = roomWall(host.floorBase,
        host.document.floors.single.rooms.single.id, Facing.east, 90);
    expect(east!.wall.ref.anchor.axisId, '@bottom');

    expect((await say('design.delete_opening', {'opening': 'o1'})).ok, isTrue);
    await t.pump();
    expect(host.document.floors.single.openings, hasLength(3));

    // A door is resized, turned to open the other way and made the way in.
    final door = await say(
        'design.add_opening', {'room': 'r1', 'side': 'north', 'kind': 'door'});
    expect(door.ok, isTrue);
    await t.pump();
    DoorOpening theDoor() => host.document.floors.single.openings
        .whereType<DoorOpening>()
        .single;
    final alias = VoiceScreens.current!.entities
        .firstWhere((e) => e.id == theDoor().id)
        .alias;
    final swing = theDoor().opensTo;
    expect(
        (await say('design.resize_opening',
                {'opening': alias, 'width_mm': 1000}))
            .ok,
        isTrue);
    expect((await say('design.flip_door', {'opening': alias})).ok, isTrue);
    expect(
        (await say('design.set_main_entrance', {'opening': alias})).ok, isTrue);
    await t.pump();
    expect(theDoor().width, 1000);
    expect(theDoor().opensTo, isNot(swing));
    expect(host.document.mainEntranceOpeningId, theDoor().id);
    // A window cannot be the way in: the reason comes back.
    expect((await say('design.set_main_entrance', {'opening': 'o2'})).ok,
        isFalse);
    expect((await say('design.delete_opening', {'opening': alias})).ok, isTrue);
    await t.pump();

    for (final type in ['hip', 'flat', 'gable']) {
      expect((await say('design.set_roof', {'type': type})).ok, isTrue);
      await t.pump();
      expect(host.document.roof.type.name, type);
    }


    // Furniture lands inside the room it was asked for.
    final bed =
        await say('design.add_furniture', {'room': 'r1', 'kind': 'bed'});
    expect(bed.changed, hasLength(1));
    await t.pump();
    final item = host.document.extras.furniture.single;
    final room = host.floorBase.roomGeometry.single;
    expect(
        room.clearRects.any((r) =>
            r.contains(item.x + item.width / 2, item.y + item.depth / 2)),
        isTrue);
    expect(shown('furniture').keys, ['u1']);
    expect(
        (await say('design.delete_furniture', {'furniture': 'u1'})).ok, isTrue);
    await t.pump();
    expect(host.document.extras.furniture, isEmpty);

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

  testWidgets('stairs and floors are spoken into place', (t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: '楼梯',
        width: 10000,
        depth: 12000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-11-17T00:00:00Z',
        newId: () => 'st${sequence++}');
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(
            entry: ProjectEntry('project', doc),
            store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();
    final host = VoiceScreens.current! as DesignHost;

    // No floor above yet: said so, nothing placed.
    final early = await say('design.add_stair');
    expect(early.ok, isFalse);
    expect(early.say['message'], contains('上方'));
    expect((await say('design.delete_stair')).code, noStair);

    // 二楼和一楼一样, then a stair with nothing else said.
    expect((await say('design.copy_floor')).ok, isTrue);
    await t.pump();
    expect(host.document.floors, hasLength(2));
    expect(host.document.floors.last.rooms, hasLength(1));
    final placed = await say('design.add_stair');
    expect(placed.ok, isTrue, reason: '${placed.say}');
    expect(placed.changed, hasLength(1));
    await t.pump();
    expect(shown('stair').keys, ['s1']);
    expect(VoiceScreens.current!.scene, contains('s1 stair U x0 y0 2400x3600'));
    expect(host.document.floors.first.rooms, hasLength(1));

    // Moved to the north-east corner; it keeps its size.
    final moved = await say(
        'design.move_stair', {'stair': 's1', 'x_mm': 7600, 'y_mm': 8400});
    expect(moved.ok, isTrue, reason: '${moved.say}');
    await t.pump();
    expect(VoiceScreens.current!.scene,
        contains('s1 stair U x7600 y8400 2400x3600'));

    // Upstairs the hole it comes up through is in the scene.
    expect((await say('editor.show_floor', {'floor': 'f2'})).ok, isTrue);
    await t.pump();
    expect(VoiceScreens.current!.scene,
        contains('stair opening from the floor below'));
    expect((await say('editor.show_floor', {'floor': 'f1'})).ok, isTrue);
    await t.pump();

    expect((await say('design.set_stair', {'turn': 'right'})).ok, isTrue);
    expect((await say('design.delete_stair')).ok, isTrue);
    await t.pump();
    expect(host.document.floors.first.stairs, isEmpty);
    expect(shown('stair'), isEmpty);
    // One sentence back.
    expect((await say('editor.undo')).ok, isTrue);
    await t.pump();
    expect(host.document.floors.first.stairs, hasLength(1));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
}
