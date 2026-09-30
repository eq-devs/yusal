import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/commands/design_commands.dart';
import 'package:yusal/core/commands/delete_axis.dart';
import 'package:yusal/core/geometry/derived_house.dart';

void main() {
  var sequence = 0;
  String next() => 'generated${sequence++}';
  HouseDocument blank() => createHouse(
      name: '测试',
      width: 12000,
      depth: 10000,
      columns: 2,
      rows: 1,
      timestamp: '2026-09-30T00:00:00Z',
      newId: next);

  test('axis deletion requests resolution and merges adjacent rooms', () {
    var doc = blank();
    final floor = doc.floors.first.id;
    doc = paintCells(doc, floor, [const Cell(0, 0)], RoomType.living, next);
    doc = paintCells(doc, floor, [const Cell(1, 0)], RoomType.bedroom, next);
    final axis = doc.axes.global.single.id;
    final pending = deleteAxis(doc, axis, next);
    expect(pending.needsResolution, isTrue);
    expect(pending.document, isNull);
    final merged =
        deleteAxis(doc, axis, next, resolution: 'mergeRooms').document!;
    expect(validateHouse(merged), isEmpty);
    expect(merged.axes.global, isEmpty);
    expect(merged.floors.first.rooms.length, 1);
    expect(merged.floors.first.rooms.single.regions.single.x0, '@left');
    expect(merged.floors.first.rooms.single.regions.single.x1, '@right');
  });

  test('axis deletion keeps the chosen side and never changes the input', () {
    var doc = blank();
    final floor = doc.floors.first.id;
    doc = paintCells(doc, floor, [const Cell(0, 0)], RoomType.living, next);
    doc = paintCells(doc, floor, [const Cell(1, 0)], RoomType.bedroom, next);
    final before = encodeHouse(doc);
    final kept = deleteAxis(doc, doc.axes.global.single.id, next,
            resolution: 'keepHighSide')
        .document!;
    expect(kept.floors.first.rooms.single.type, RoomType.bedroom);
    expect(encodeHouse(doc), before);
    expect(deleteAxis(doc, '@left', next).document, isNull);
  });

  test('floor copy allocates new room identities and remains valid', () {
    var doc = blank();
    doc = paintCells(
        doc, doc.floors.first.id, [const Cell(0, 0)], RoomType.living, next);
    final copy = executeDocumentCommand(
        doc, 'CopyFloor', {'floorId': doc.floors.first.id}, next);
    expect(copy.accepted, isTrue, reason: copy.error);
    expect(validateHouse(copy.document!), isEmpty);
    expect(copy.document!.floors.length, 2);
    expect(copy.document!.floors.last.rooms.single.id,
        isNot(doc.floors.first.rooms.single.id));
    expect(doc.floors.length, 1);
  });

  test('opening geometry and scene are deterministic', () {
    final doc = blank();
    final edited = executeDocumentCommand(
        doc,
        'AddOpening',
        {
          'floorId': doc.floors.first.id,
          'anchor': const BoundaryAnchor(
              axisId: '@bottom', startAxisId: '@left', endAxisId: '@right'),
          'tapT': 3000,
          'kind': OpeningKind.window,
        },
        next);
    expect(edited.accepted, isTrue, reason: edited.error);
    final derived = deriveHouse(edited.document!);
    expect(derived.floors.first.openings.single.status, 'ok');
    expect(derived.scene3d, isNotEmpty);
    expect(
        deriveHouse(edited.document!).scene3d.length, derived.scene3d.length);
  });

  test('invalid commands preserve document and reject axis crossing', () {
    final doc = blank();
    final result = executeDocumentCommand(doc, 'MoveAxis',
        {'axisId': doc.axes.global.single.id, 'pos': 11999}, next);
    expect(result.accepted, isFalse);
    expect(validateHouse(doc), isEmpty);
  });
  test('merge command keeps a valid connected room and rejects other floors',
      () {
    var doc = blank();
    final floor = doc.floors.first.id;
    doc = paintCells(doc, floor, [const Cell(0, 0)], RoomType.living, next);
    doc = paintCells(doc, floor, [const Cell(1, 0)], RoomType.bedroom, next);
    final result = executeDocumentCommand(
        doc,
        'MergeRooms',
        {
          'roomIdA': doc.floors.first.rooms.first.id,
          'roomIdB': doc.floors.first.rooms.last.id
        },
        next);
    expect(result.accepted, isTrue, reason: result.error);
    expect(result.document!.floors.first.rooms.length, 1);
    expect(validateHouse(result.document!), isEmpty);
  });

  test('opening conversion clears door-only fields and the main entrance', () {
    var doc = blank();
    doc = executeDocumentCommand(
            doc,
            'AddOpening',
            {
              'floorId': doc.floors.first.id,
              'anchor': const BoundaryAnchor(
                  axisId: '@bottom', startAxisId: '@left', endAxisId: '@right'),
              'tapT': 0,
              'kind': OpeningKind.door
            },
            next)
        .document!;
    final id = doc.floors.first.openings.single.id;
    doc =
        executeDocumentCommand(doc, 'SetMainEntrance', {'openingId': id}, next)
            .document!;
    final result = executeDocumentCommand(doc, 'SetOpeningKind',
        {'openingId': id, 'kind': OpeningKind.window}, next);
    expect(result.accepted, isTrue, reason: result.error);
    expect(result.document!.mainEntranceOpeningId, isNull);
    expect(
        result.document!.floors.first.openings.single.kind, OpeningKind.window);
    final restored = executeDocumentCommand(result.document!, 'SetOpeningKind',
        {'openingId': id, 'kind': OpeningKind.door}, next);
    expect(restored.accepted, isTrue, reason: restored.error);
    expect(restored.document!.floors.first.openings.single.sill, 0);
  });

  test('stair layouts and floor deletion resolve without invalid references',
      () {
    var doc = blank();
    doc = executeDocumentCommand(
            doc, 'AddFloor', {'floorId': doc.floors.first.id}, next)
        .document!;
    for (final type in StairType.values) {
      final withStair = executeDocumentCommand(
          doc,
          'AddStair',
          {
            'floorId': doc.floors.first.id,
            'type': type,
            'region': const AxisRectangle(
                x0: '@left', x1: '@right', y0: '@bottom', y1: '@top')
          },
          next);
      expect(withStair.accepted, isTrue, reason: withStair.error);
      final geometry =
          deriveHouse(withStair.document!).floors.first.stairs.single;
      expect(geometry.fits, isTrue);
      expect(geometry.steps, isNotEmpty);
      final blocked = executeDocumentCommand(withStair.document!, 'DeleteFloor',
          {'floorId': doc.floors.last.id}, next);
      expect(blocked.accepted, isFalse);
      final deleted = executeDocumentCommand(withStair.document!, 'DeleteFloor',
          {'floorId': doc.floors.last.id, 'deleteStairs': true}, next);
      expect(deleted.accepted, isTrue, reason: deleted.error);
      expect(deleted.document!.floors.single.stairs, isEmpty);
    }
  });
}
