import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  testWidgets('a room is added from its use, size and corner', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var n = 0;
    final doc = createHouse(
        name: '我的房屋',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        timestamp: '2026-09-30T00:00:00Z',
        newId: () => 'id${n++}');
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: HouseEditor(entry: ProjectEntry(id, doc), store: store))));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('加房间'));
    await t.pumpAndSettle();

    // Picking a use fills in its usual size.
    await t.tap(find.byKey(const Key('add-room-bathroom')));
    await t.pump();
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, '1.8');
    expect(fields[1].controller!.text, '2.4');

    // Bigger than the house: refused in place.
    await t.enterText(find.byType(TextField).first, '20');
    await t.tap(find.byKey(const Key('add-room-go')));
    await t.pump();
    expect(find.text('房间要在 0.3 米到房屋长宽之间'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '1,5+0,5');
    await t.tap(find.byKey(const Key('add-room-tr')));
    await t.tap(find.byKey(const Key('add-room-go')));
    await t.pumpAndSettle();
    // The room lies on the plan to be slid about; 放下 builds it.
    await t.tap(find.byKey(const Key('stamp-place')));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();

    final saved = await store.openProject(id);
    final room = saved.floors.single.rooms.single;
    expect(room.type, RoomType.bathroom);
    final axes = resolveFloorAxes(saved, saved.floors.single.id)!;
    final r = resolveRect(axes, room.regions.single).rect!;
    expect((r.left, r.bottom, r.right, r.top), (10000, 7600, 12000, 10000));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
    await t.pumpAndSettle();
  });
}
