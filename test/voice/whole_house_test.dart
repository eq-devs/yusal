import 'package:flutter/material.dart';
import '../support/mock/backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/page.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_clock.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/actions/actions.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/actions/houses.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/state/screen.dart';

import '../house_spec_test.dart' show spec;
import '../storage_test.dart' show MemoryFiles;

/// Designs in memory, standing in for the "My houses" list.
class FakeLibrary implements HouseLibrary {
  final added = <HouseDocument>[];
  final opened = <String>[];
  @override
  List<({String id, String name})> designs = [
    (id: 'a', name: 'Менің үйім'),
    (id: 'b', name: 'Дача'),
    (id: 'c', name: 'Дача 2'),
  ];
  @override
  Future<void> addDesign(HouseDocument doc) async => added.add(doc);
  @override
  Future<void> openDesign(String id) async => opened.add(id);
  @override
  HouseDocument newDesign(String template,
          {String? name, int? width, int? depth}) =>
      createHouse(
          name: name ?? template,
          width: width ?? 12000,
          depth: depth ?? 10000,
          columns: 1,
          rows: 1,
          timestamp: '2026-11-15T00:00:00Z',
          newId: () => 'x');
}

void main() {
  final executor = ActionExecutor(appActions, confirm: (_, __) async => true);
  final repos = MockBackend(
      clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
      latency: Duration.zero,
      seed: false);

  Future<ActionResult> say(String id, [Map<String, Object?> args = const {}]) =>
      executor.run(
          id, args, VoiceScreens.context(voiceRepos(repos), loggedIn: true),
          source: Source.voice);

  Map<String, String> shown(String kind) => {
        for (final e in VoiceScreens.current!.entities)
          if (e.kind == kind) e.alias: e.title
      };

  Future<void> editor(WidgetTester t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: 'Үй',
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
  }

  testWidgets('a whole house replaces the open design and undoes in one step',
      (t) async {
    await editor(t);
    final host = VoiceScreens.current! as DesignHost..beginUndoGroup();
    final made = await say('design.create_house', {'spec': spec});
    host.endUndoGroup();
    await t.pump();
    expect(made.ok, isTrue);
    expect(made.say['rooms'], 6);
    expect(shown('room'), hasLength(6));
    expect(shown('room').values, contains('Қонақ бөлме'));
    // The design keeps its own name.
    expect(host.document.meta.name, 'Үй');

    expect((await say('editor.undo')).ok, isTrue);
    await t.pump();
    expect(shown('room'), hasLength(1));
    expect(host.document.footprint.width, 10000);

    // A spec that cannot be built says why and changes nothing.
    final bad = await say('design.create_house', {
      'spec': {'width_mm': 100, 'depth_mm': 8000, 'floors': []}
    });
    expect(bad.code, badSpec);
    expect(bad.say['errors'], isNotEmpty);
    expect(shown('room'), hasLength(1));

    await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
    await t.pumpAndSettle();
  });

  testWidgets('a house is laid out from what it must have, in several plans',
      (t) async {
    await editor(t);
    final host = VoiceScreens.current! as DesignHost;
    final made = await say('design.plan_house', {
      'width_mm': 12000,
      'depth_mm': 10000,
      'bedrooms': 3,
      'entrance': 'north'
    });
    await t.pump();
    expect(made.ok, isTrue);
    expect(made.say['plan'], 1);
    expect(made.say['plans'], 3);
    expect(made.say['entrance'], 'north');
    expect(host.document.footprint.width, 12000);
    expect(
        host.document.floors.single.rooms
            .where((r) => r.type == RoomType.bedroom),
        hasLength(3));
    expect(host.document.mainEntranceOpeningId, isNotNull);
    final first = made.say['layout'];

    // "Another one" is a different layout of the same house.
    final other = await say('design.plan_house', {
      'width_mm': 12000,
      'depth_mm': 10000,
      'bedrooms': 3,
      'entrance': 'north',
      'plan': 2
    });
    expect(other.ok, isTrue);
    expect(other.say['layout'], isNot(first));
    expect(
        (await say('design.plan_house',
                {'area_sqm': 120, 'bedrooms': 3, 'plan': 9}))
            .code,
        ActionCodes.badArgs);

    // An area becomes a width and a depth.
    final byArea =
        await say('design.plan_house', {'area_sqm': 120, 'bedrooms': 3});
    expect(byArea.say['width_mm'], 12000);
    expect(byArea.say['depth_mm'], 10000);

    // No size is not enough, and a house too small for the rooms says so.
    expect((await say('design.plan_house', {'bedrooms': 3})).code,
        ActionCodes.badArgs);
    final small = await say('design.plan_house',
        {'width_mm': 6000, 'depth_mm': 6000, 'bedrooms': 5});
    expect(small.code, tooSmall);
    expect(host.document.footprint.width, 12000);

    await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
    await t.pumpAndSettle();
  });

  testWidgets('rooms are drawn by size and split in two', (t) async {
    await editor(t);
    // The house is one room; carve a bedroom out of its south-west corner.
    final added = await say('design.add_room', {
      'type': 'bedroom',
      'name': 'Жатын бөлме',
      'x_mm': 0,
      'y_mm': 0,
      'w_mm': 4000,
      'd_mm': 4000
    });
    expect(added.ok, isTrue, reason: '${added.say}');
    await t.pump();
    expect(shown('room'), hasLength(2));
    expect(shown('room').values, contains('Жатын бөлме'));

    final bedroom =
        shown('room').entries.firstWhere((e) => e.value == 'Жатын бөлме').key;
    final split = await say(
        'design.split_room', {'room': bedroom, 'wall': 'north_south'});
    expect(split.ok, isTrue, reason: '${split.say}');
    await t.pump();
    expect(shown('room'), hasLength(3));

    expect(
        (await say('design.split_room',
                {'room': bedroom, 'wall': 'east_west', 'at_mm': 99999}))
            .code,
        ActionCodes.badArgs);

    // Or by where it goes: the north-east corner of the 10 by 8 m house.
    final corner = await say('design.add_room',
        {'type': 'kitchen', 'where': 'northeast', 'w_mm': 3000, 'd_mm': 3000});
    expect(corner.ok, isTrue, reason: '${corner.say}');
    await t.pump();
    expect(VoiceScreens.current!.scene, contains('x7000 y5000 3000x3000'));
    expect(
        (await say('design.add_room',
                {'type': 'kitchen', 'w_mm': 3000, 'd_mm': 3000}))
            .code,
        ActionCodes.badArgs);

    await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
    await t.pumpAndSettle();
  });

  test('designs open by name and new ones are made', () async {
    final library = HouseLibrary.instance = FakeLibrary();
    addTearDown(() => HouseLibrary.instance = null);
    Future<ActionResult> run(String id, Map<String, Object?> args) =>
        executor.run(
            id, args, ActionContext(repos: voiceRepos(repos), loggedIn: true),
            source: Source.voice);

    expect((await run('houses.open', {'name': 'менің үйім'})).ok, isTrue);
    expect(library.opened, ['a']);
    // An exact name wins over names that contain it.
    expect((await run('houses.open', {'name': 'Дача'})).ok, isTrue);
    expect(library.opened.last, 'b');
    final many = await run('houses.open', {'name': 'дач'});
    expect(many.code, severalDesigns);
    expect(many.say['designs'], ['Дача', 'Дача 2']);
    final none = await run('houses.open', {'name': 'Сарай'});
    expect(none.code, noSuchDesign);
    expect(none.say['designs'], hasLength(3));

    expect((await run('houses.create', {'name': 'Жаңа', 'width_mm': 9000})).ok,
        isTrue);
    expect(library.added.single.meta.name, 'Жаңа');
    expect(library.added.single.footprint.width, 9000);
    expect((await run('houses.create', {'width_mm': 100})).code,
        ActionCodes.badArgs);

    // Without an editor, a whole house goes into a new design.
    expect((await run('design.create_house', {'spec': spec})).ok, isTrue);
    expect(library.added, hasLength(2));
  });
}
