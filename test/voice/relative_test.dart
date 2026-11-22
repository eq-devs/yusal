import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/page.dart';
import '../support/mock/mock_backend.dart';
import 'package:yusal/services/storage/project_store.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/actions/actions.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/state/screen.dart';

import '../storage_test.dart' show MemoryFiles;

void main() {
  final executor = ActionExecutor(appActions, confirm: (_, __) async => true);
  final repos = MockBackend(latency: Duration.zero, seed: false);

  testWidgets('rooms, openings and furniture change relative to where they are',
      (t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: '相对',
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
    String scene() => VoiceScreens.current!.scene;

    Future<ActionResult> say(String id,
        [Map<String, Object?> args = const {}]) async {
      final result = await executor.run(
          id, args, VoiceScreens.context(repos, loggedIn: true),
          source: Source.voice);
      await t.pump();
      return result;
    }

    // Two rooms side by side: r1 on the west, 4 m wide.
    expect(
        (await say('design.split_room',
                {'room': 'r1', 'wall': 'north_south', 'at_mm': 4000}))
            .ok,
        isTrue);
    expect(scene(), contains(' r1 '));
    expect(scene(), contains('x0 y0 4000x8000'));
    expect(scene(), contains('x4000 y0 6000x8000'));

    // The wall between them moves; the one opposite stays.
    final wider = await say(
        'design.resize_room', {'room': 'r1', 'side': 'east', 'size_mm': 5500});
    expect(wider.ok, isTrue, reason: '${wider.code} ${wider.say}');
    expect(wider.changed, hasLength(2));
    expect(scene(), contains('x0 y0 5500x8000'));
    expect(scene(), contains('x5500 y0 4500x8000'));
    final narrower = await say(
        'design.resize_room', {'room': 'r2', 'side': 'west', 'size_mm': 6000});
    expect(narrower.ok, isTrue);
    expect(scene(), contains('x0 y0 4000x8000'));
    // The house's own walls move with the size of the house.
    expect(
        (await say('design.resize_room',
                {'room': 'r1', 'side': 'west', 'size_mm': 3000}))
            .code,
        outerWall);

    // A window slides along its wall, and not off it.
    final window = await say('design.add_opening',
        {'room': 'r1', 'side': 'north', 'kind': 'window'});
    expect(window.ok, isTrue);
    double at() =>
        deriveHouse(host.document).floors.first.openings.single.start;
    final before = at();
    expect(
        (await say('design.move_opening', {'opening': 'o1', 'shift_mm': 500}))
            .ok,
        isTrue);
    expect(at(), before + 500);
    final off =
        await say('design.move_opening', {'opening': 'o1', 'shift_mm': 9000});
    expect(off.code, ActionCodes.badArgs);
    expect(at(), before + 500);
    // Or goes to another wall.
    expect(
        (await say('design.move_opening',
                {'opening': 'o1', 'room': 'r2', 'side': 'south'}))
            .ok,
        isTrue);
    expect(scene(), contains(RegExp(' r2 .*windows o1 south')));
    expect((await say('design.move_opening', {'opening': 'o1'})).code,
        ActionCodes.badArgs);

    // Furniture moves by a distance and turns where it stands.
    expect(
        (await say('design.add_furniture', {'room': 'r1', 'kind': 'bed'})).ok,
        isTrue);
    final bed = host.document.extras.furniture.single;
    expect(
        (await say('design.move_furniture',
                {'furniture': 'u1', 'east_mm': 300, 'north_mm': -200}))
            .ok,
        isTrue);
    var moved = host.document.extras.furniture.single;
    expect((moved.x, moved.y), (bed.x + 300, bed.y - 200));
    expect(
        (await say('design.move_furniture', {'furniture': 'u1', 'turn': true}))
            .ok,
        isTrue);
    moved = host.document.extras.furniture.single;
    expect((moved.width, moved.depth), (bed.depth, bed.width));

    // Two rooms trade use and name, not walls.
    await say('design.set_room_type', {'room': 'r1', 'type': 'kitchen'});
    await say('design.rename_room', {'room': 'r1', 'name': '厨房'});
    await say('design.rename_room', {'room': 'r2', 'name': '书房'});
    final swapped = await say('design.swap_rooms', {'a': 'r1', 'b': 'r2'});
    expect(swapped.changed, hasLength(2));
    expect(scene(), contains(' r2 kitchen "厨房" x4000'));
    expect(scene(), contains(' r1 '));
    expect(scene(), contains('"书房" x0 y0'));

    // Showing something selects it; another floor can be brought up.
    expect(scene(), isNot(contains('selected:')));
    expect((await say('editor.select', {'room': 'r2'})).ok, isTrue);
    expect(scene(), contains('selected: r2'));
    expect((await say('editor.select', {'opening': 'o1'})).ok, isTrue);
    expect(scene(), contains('selected: o1'));
    expect((await say('editor.select')).code, ActionCodes.badArgs);
    await say('design.add_floor');
    expect(scene(), contains('floor f1 '));
    expect((await say('editor.show_floor', {'floor': 'f2'})).ok, isTrue);
    expect(scene(), contains('floor f2 '));
    expect(scene(), contains('other floor f1 '));

    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
}
