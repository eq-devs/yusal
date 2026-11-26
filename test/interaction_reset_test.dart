// Every way out of what the user was doing leaves nothing behind: no
// selection acted on from another tab, no gesture resumed by the next
// finger, no selection carried to another floor.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'storage_test.dart' show MemoryFiles;

void main() {
  var sequence = 0;
  String next() => 'reset_${sequence++}';
  final ctx = CommandContext(newId: next, now: () => '2026-11-26T00:00:00Z');

  HouseDocument house({bool twoFloors = false}) {
    var doc = createHouse(
        name: '复位',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
        newId: next);
    HouseDocument run(String kind, Map<String, dynamic> args) =>
        doc = composeDocument(
            doc.meta,
            (executeCommand(extractDesignState(doc), DesignCommand(kind, args),
                    ctx) as Applied)
                .newState);
    final floorId = doc.floors.first.id;
    run('AddFurniture', {
      'floorId': floorId,
      'kind': FurnitureKind.bed,
      'x': 2000,
      'y': 2000,
      'id': 'bed'
    });
    run('AddUtility', {
      'floorId': floorId,
      'kind': UtilityKind.socket,
      'x': 6000,
      'y': 5000,
      'id': 'socket'
    });
    if (twoFloors) run('AddFloor', {'floorId': floorId});
    return doc;
  }

  final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter);
  FloorPlanPainter painter(WidgetTester t) =>
      t.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
  Offset point(WidgetTester t, double x, double y) =>
      t.getTopLeft(canvas) + painter(t).point(x, y, t.getSize(canvas));
  DesignHost host() => VoiceScreens.mounted.whereType<DesignHost>().last;

  Future<void> mount(WidgetTester t, HouseDocument doc) async {
    final store = ProjectStore(fileSystem: MemoryFiles());
    final id = await store.createProject(doc);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: HouseEditor(entry: ProjectEntry(id, doc), store: store))));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
      await t.pumpAndSettle();
    });
  }

  testWidgets('Delete on another tab leaves the plan selection alone (R4)',
      (t) async {
    await mount(t, house());
    expect(host().select('bed'), isTrue);
    await t.pumpAndSettle();
    host().showTab('cost');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pumpAndSettle();
    expect(host().document.extras.furniture.map((f) => f.id), contains('bed'));
  });

  testWidgets('changing floor drops the selection (R5)', (t) async {
    await mount(t, house(twoFloors: true));
    expect(host().select('bed'), isTrue);
    await t.pumpAndSettle();
    expect(VoiceScreens.current!.scene, contains('selected:'));
    host().showFloor(host().document.floors.last.id);
    await t.pumpAndSettle();
    host().showFloor(host().document.floors.first.id);
    await t.pumpAndSettle();
    expect(VoiceScreens.current!.scene, isNot(contains('selected:')));
  });

  testWidgets(
      'a utility drag cut short by a second finger does not come back on '
      'the next drag (R2)', (t) async {
    await mount(t, house());
    expect(host().document.extras.utilities.map((u) => u.id), ['socket']);
    await t.tap(find.text('水电').first);
    await t.pumpAndSettle();
    // Select the socket, then press on it and put a second finger down.
    await t.tapAt(point(t, 6000, 5000));
    await t.pumpAndSettle();
    expect(host().document.extras.utilities.map((u) => u.id), ['socket'],
        reason: 'after select');
    final first = await t.startGesture(point(t, 6000, 5000), pointer: 11);
    await t.pump();
    // The system takes the pointer away (a call, a system gesture).
    await first.cancel();
    await t.pumpAndSettle();
    // A plain one-finger drag somewhere else.
    final drag = await t.startGesture(point(t, 3000, 6000), pointer: 13);
    await t.pump();
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(point(t, 3000 + i * 150.0, 6000));
      await t.pump();
    }
    await drag.up();
    await t.pumpAndSettle();
    final socket =
        host().document.extras.utilities.firstWhere((u) => u.id == 'socket');
    expect((socket.x, socket.y), (6000, 5000));
  });
}
