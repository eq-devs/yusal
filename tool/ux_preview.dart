// Developer preview entry point; the production app starts at lib/main.dart.
import 'package:flutter/material.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/storage/project_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var sequence = 0;
  String next() => 'preview${sequence++}';
  final context = CommandContext(newId: next, now: () => 'unused');
  var doc = createHouse(
      name: '长宽与直接操作演示',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: '2026-09-30T00:00:00Z',
      newId: next);
  void edit(String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        extractDesignState(doc), DesignCommand(kind, args), context);
    if (result is! Applied) throw StateError('Invalid preview: $kind');
    doc = composeDocument(doc.meta, result.newState);
  }

  edit('SplitSpace', {
    'floorId': doc.floors.first.id,
    'dir': AxisDir.V,
    'pos': 6000,
    'x': 6000,
    'y': 5000
  });
  edit('CarveRoom', {
    'floorId': doc.floors.first.id,
    'left': 0,
    'bottom': 0,
    'right': 3000,
    'top': 4000,
    'roomType': RoomType.bathroom
  });
  final v =
      doc.axes.floor.firstWhere((a) => a.dir == AxisDir.V && a.pos == 6000);
  final right = doc.floors.first.rooms
      .firstWhere((r) => r.regions.every((b) => b.x0 == v.id));
  edit('SetRoomType', {'roomId': right.id, 'value': RoomType.bedroom});
  final living =
      doc.floors.first.rooms.firstWhere((r) => r.type == RoomType.custom);
  edit('SetRoomType', {'roomId': living.id, 'value': RoomType.living});
  edit('AddOpening', {
    'floorId': doc.floors.first.id,
    'kind': OpeningKind.window,
    'centerAtTap': true,
    'anchor':
        BoundaryAnchor(axisId: '@top', startAxisId: v.id, endAxisId: '@right'),
    'tapT': 3000
  });
  final bathroomV =
      doc.axes.floor.firstWhere((a) => a.dir == AxisDir.V && a.pos == 3000);
  final bathroomH =
      doc.axes.floor.firstWhere((a) => a.dir == AxisDir.H && a.pos == 4000);
  edit('AddOpening', {
    'floorId': doc.floors.first.id,
    'kind': OpeningKind.door,
    'centerAtTap': true,
    'anchor': BoundaryAnchor(
        axisId: bathroomV.id, startAxisId: '@bottom', endAxisId: bathroomH.id),
    'tapT': 2000
  });
  edit('AddOpening', {
    'floorId': doc.floors.first.id,
    'kind': OpeningKind.door,
    'centerAtTap': true,
    'anchor': BoundaryAnchor(
        axisId: '@bottom', startAxisId: bathroomV.id, endAxisId: v.id),
    'tapT': 1500
  });
  edit('SetMainEntrance', {'openingId': doc.floors.first.openings.last.id});
  edit('AddOpening', {
    'floorId': doc.floors.first.id,
    'kind': OpeningKind.door,
    'centerAtTap': true,
    'anchor':
        BoundaryAnchor(axisId: v.id, startAxisId: '@bottom', endAxisId: '@top'),
    'tapT': 7000
  });
  edit('AddOpening', {
    'floorId': doc.floors.first.id,
    'kind': OpeningKind.window,
    'centerAtTap': true,
    'anchor': BoundaryAnchor(
        axisId: '@left', startAxisId: bathroomH.id, endAxisId: '@top'),
    'tapT': 3000
  });
  final store = ProjectStore();
  final existing = (await store.listProjects())
      .where((p) => p.document.meta.name == doc.meta.name)
      .firstOrNull;
  final id = existing?.id ?? await store.createProject(doc);
  if (existing != null) await store.saveProject(id, doc);
  final navigator = GlobalKey<NavigatorState>();
  runApp(MaterialApp(
      navigatorKey: navigator,
      title: '自建房设计',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorSchemeSeed: const Color(0xff526b5b),
          scaffoldBackgroundColor: const Color(0xfff6f7f3),
          useMaterial3: true),
      home: const HouseHome()));
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => HouseEditor(
              entry: ProjectEntry(id, doc),
              store: store,
              initialView3d: const bool.fromEnvironment('PREVIEW_3D'),
              initialTool: const bool.fromEnvironment('PREVIEW_CONTEXT')
                  ? 'wallContext'
                  : const bool.fromEnvironment('PREVIEW_WALL')
                      ? 'drawWall'
                      : null))));
}
