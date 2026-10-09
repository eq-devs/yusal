import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

void main() {
  var ids = 0;
  HouseDocument house(String name) => createHouse(
      name: name,
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: '2026-10-09T00:00:00Z',
      newId: () => 'restore_${ids++}');

  testWidgets('a reload returns to the design that was open', (t) async {
    final store = ProjectStore(fileSystem: MemoryFiles());
    await store.createProject(house('另一个'));
    final id = await store.createProject(house('正在改的房子'));
    SharedPreferences.setMockInitialValues({'editing-project': id});
    await t.pumpWidget(MaterialApp(home: HouseHome(store: store)));
    await t.pumpAndSettle();
    expect(find.byType(HouseEditor), findsOneWidget);
    expect(find.text('正在改的房子'), findsOneWidget);
    expect(await LastOpenProject.read(), id);
    // Leaving the editor normally forgets it, so the next start shows home.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(HouseEditor), findsNothing);
    expect(await LastOpenProject.read(), isNull);
  });

  testWidgets('a remembered design that no longer exists is ignored',
      (t) async {
    final store = ProjectStore(fileSystem: MemoryFiles());
    SharedPreferences.setMockInitialValues({'editing-project': 'gone'});
    await t.pumpWidget(MaterialApp(home: HouseHome(store: store)));
    await t.pumpAndSettle();
    expect(find.byType(HouseEditor), findsNothing);
    expect(await LastOpenProject.read(), isNull);
  });
}
