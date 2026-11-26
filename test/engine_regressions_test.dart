// One test per engine defect found in the 2026-11-26 audit, plus the
// invariants that hold for every sampled command.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/history/design_history.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart'
    show openingClearance;

import 'support/command_samples.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'r_${ids++}', now: () => '2026-11-26T00:00:00Z');
  const meta = Meta(
      name: 'R',
      createdAt: '2026-11-26T00:00:00Z',
      updatedAt: '2026-11-26T00:00:00Z');
  UndoableDesignState box({int width = 12000, int depth = 10000}) =>
      extractDesignState(createHouse(
          name: 'R',
          width: width,
          depth: depth,
          columns: 1,
          rows: 1,
          initialRoom: true,
          timestamp: ctx.now(),
          newId: ctx.newId));
  CommandResult run(
          UndoableDesignState s, String kind, Map<String, dynamic> args) =>
      executeCommand(
          s, DesignCommand(kind, {'floorId': s.floors.first.id, ...args}), ctx);
  UndoableDesignState ok(CommandResult r) {
    expect(r, isA<Applied>(), reason: r is Rejected ? r.message : null);
    return (r as Applied).newState;
  }

  Map<String, dynamic> line(int x0, int y0, int x1, int y1) =>
      {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1};

  group('R1: an opening lies within one wall', () {
    test('a door past the end of a wall onto a low wall is not ok', () {
      var s = ok(run(box(), 'AddDrawnWall', line(0, 4000, 3000, 4000)));
      s = ok(run(
          s, 'AddDrawnWall', {...line(3000, 4000, 6000, 4000), 'height': 900}));
      final solid = s.floors.first.wallOverrides
          .whereType<SolidWall>()
          .firstWhere((w) => w.height == null);
      final low = s.floors.first.wallOverrides
          .whereType<SolidWall>()
          .firstWhere((w) => w.height != null);
      // One anchor over both walls, the door straddling where they meet.
      final door = DoorOpening(
          id: 'door',
          anchor: BoundaryAnchor(
              axisId: solid.anchor.axisId,
              startAxisId: solid.anchor.startAxisId,
              endAxisId: low.anchor.endAxisId),
          position: const FromStartPosition(2500),
          width: 1000,
          height: 2100,
          sill: 0,
          hinge: Hinge.start,
          opensTo: OpeningSide.positiveSide);
      final doc = composeDocument(
          meta, s.withFloor(s.floors.first.copyWith(openings: [door])));
      final placed = documentOpeningsOf(doc).single;
      expect(placed.status, 'tooLong');
      expect(placed.host, isNull);
    });

    test('moving a door so it overhangs the end of its wall is refused', () {
      var s = ok(run(box(), 'AddDrawnWall', line(0, 4000, 3000, 4000)));
      final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
      s = ok(run(s, 'AddOpening', {
        'anchor': wall.anchor,
        'kind': OpeningKind.door,
        'tapT': 1500,
        'centerAtTap': true
      }));
      final door = s.floors.first.openings.single;
      final moved = executeCommand(
          s,
          DesignCommand('MoveOpening', {
            'openingId': door.id,
            'position': {'type': 'fromStart', 'd': 2500}
          }),
          ctx);
      expect(moved, isA<Rejected>());
    });
  });

  group('R3: every document number has an upper bound', () {
    test('a floor two thousand kilometres high is refused', () {
      final r = run(box(), 'SetFloorHeight', {'value': 2000000000});
      expect(r, isA<Rejected>());
    });

    test('an outer wall fifty metres thick is refused', () {
      final r = executeCommand(
          box(),
          DesignCommand(
              'SetDefault', {'field': 'outerWallThickness', 'value': 50000}),
          ctx);
      expect(r, isA<Rejected>());
    });

    test('a loaded file with an opening twenty metres wide is refused', () {
      var s = ok(run(box(), 'AddDrawnWall', line(0, 4000, 6000, 4000)));
      final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
      s = ok(run(s, 'AddOpening', {
        'anchor': wall.anchor,
        'kind': OpeningKind.window,
        'tapT': 3000,
        'centerAtTap': true
      }));
      final raw = jsonDecode(encodeHouse(composeDocument(meta, s)))
          as Map<String, dynamic>;
      (((raw['floors'] as List).first as Map)['openings'] as List)
          .first['width'] = 20000;
      final loaded = loadHouse(utf8.encode(jsonEncode(raw)));
      expect(loaded.isSuccess, isFalse);
    });

    test('the limits accept every template', () {
      for (final s in [box(), box(width: 30000, depth: 24000)]) {
        expect(validateHouse(composeDocument(meta, s)), isEmpty);
      }
    });
  });

  test('R14: a low wall cannot stand on the outline', () {
    final s = ok(run(
        box(), 'CutOutline', {'corner': 'tr', 'width': 4000, 'depth': 3000}));
    // The cut leaves an outside wall along y = 7000 from x = 8000 to 12000.
    final r = run(
        s, 'AddDrawnWall', {...line(8000, 7000, 12000, 7000), 'height': 900});
    expect(r, isA<Rejected>());
  });

  group('R6: a pitched roof follows the outline', () {
    List<Point3> roofPoints(UndoableDesignState s) => [
          for (final e in deriveHouse(composeDocument(meta, s)).scene3d)
            if (e.kind == 'RoofPlane') ...e.vertices
        ];
    UndoableDesignState hip(UndoableDesignState s) => ok(executeCommand(
        s,
        DesignCommand('SetRoof', {
          'roof': {'type': 'hip', 'pitchDeg': 30, 'overhang': 500}
        }),
        ctx));

    test('an L-shaped house leaves its cut corner open', () {
      final l = hip(ok(run(box(), 'CutOutline',
          {'corner': 'tr', 'width': 4000, 'depth': 3000})));
      final points = roofPoints(l);
      expect(points, isNotEmpty);
      // The cut is x 8000-12000, y 7000-10000; the eaves reach 500 into it.
      expect(points.where((p) => p.x > 8500 && p.y > 7500), isEmpty);
      // Two wings, each a hip of its own: their ridges are at two heights.
      expect(points.map((p) => p.z).toSet().length, greaterThan(3));
    });

    test('a rectangle keeps one roof of four planes', () {
      final planes = deriveHouse(composeDocument(meta, hip(box())))
          .scene3d
          .where((e) => e.kind == 'RoofPlane');
      expect(planes, hasLength(4));
    });

    test('the wings of an L are its two largest rectangles', () {
      expect(
          outlineRectangles(
                  12000, 10000, const [PlanRect(8000, 7000, 12000, 10000)])
              .map((r) => (r.left, r.bottom, r.right, r.top))
              .toSet(),
          {(0.0, 0.0, 12000.0, 7000.0), (0.0, 0.0, 8000.0, 10000.0)});
    });
  });

  test('a door\'s clear distances run to the faces of the walls beside it', () {
    var s = ok(run(box(), 'AddDrawnWall', line(0, 4000, 12000, 4000)));
    s = ok(run(s, 'AddDrawnWall', line(6000, 0, 6000, 4000)));
    final wall = deriveFloorBase(composeDocument(meta, s), s.floors.first.id)
        .wallSegments
        .firstWhere((w) =>
            w.axis.dir == AxisDir.H && w.axis.pos == 4000 && w.start.pos == 0);
    s = ok(run(s, 'AddOpening', {
      'anchor': wall.ref.anchor,
      'kind': OpeningKind.door,
      'tapT': 3000,
      'centerAtTap': true
    }));
    final doc = composeDocument(meta, s);
    final base = deriveFloorBase(doc, doc.floors.first.id);
    final door = deriveOpenings(doc, base, doc.floors.first.id).single;
    expect((door.start, door.end), (2550.0, 3450.0));
    // The outer wall's inner face at 240, the partition's face at 5940.
    expect(openingClearance(base, door), (240.0, 5940.0));
  });

  group('R15: history', () {
    final base = box();
    HouseDocument docWith(String name) => composeDocument(
        meta,
        ok(executeCommand(
            base,
            DesignCommand('RenameRoom',
                {'roomId': base.floors.first.rooms.first.id, 'value': name}),
            ctx)));

    test('a group longer than the history limit undoes as one step', () {
      final history = DesignHistory(docWith('start'), limit: 10)
        ..commit(docWith('a'))
        ..commit(docWith('b'))
        ..beginGroup();
      for (var i = 0; i < 25; i++) {
        history.commit(docWith('g$i'));
      }
      history.endGroup();
      expect(history.undoDepth, 3);
      history.undo();
      expect(history.present.floors.first.rooms.first.name, 'b');
    });

    test('undo hands back the very document it stored', () {
      final first = docWith('a');
      final history = DesignHistory(first)
        ..commit(docWith('b'))
        ..undo();
      expect(identical(history.present, first), isTrue);
    });

    test('rename takes no undo step and survives undo', () {
      final history = DesignHistory(docWith('a'))
        ..commit(docWith('b'))
        ..rename(const Meta(
            name: 'New',
            createdAt: '2026-11-26T00:00:00Z',
            updatedAt: '2026-11-27T00:00:00Z'));
      expect(history.undoDepth, 1);
      history.undo();
      expect(history.present.meta.name, 'New');
      expect(history.present.floors.first.rooms.first.name, 'a');
    });
  });

  test('a floor is checked again only when what it reads changed', () {
    final s = box();
    final f = s.floors.first;
    // A second room over the first one's cells: an overlap.
    final bad = f.copyWith(rooms: [
      ...f.rooms,
      Room(
          id: 'twin',
          type: RoomType.bedroom,
          name: 'Twin',
          regions: f.rooms.first.regions)
    ]);
    final doc = composeDocument(meta, s.withFloor(bad));
    final first = validateHouse(doc).map((e) => (e.code, e.path)).toList();
    expect(first, isNotEmpty);
    // The same floor object in a new document: the same findings.
    final renamed = composeDocument(
        const Meta(name: 'Other', createdAt: 'x', updatedAt: 'x'),
        extractDesignState(doc));
    expect(validateHouse(renamed).map((e) => (e.code, e.path)).toList(), first);
    // The fixed floor: none.
    expect(validateHouse(composeDocument(meta, s.withFloor(f))), isEmpty);
  });

  test('R17: an invalid document is never encoded', () {
    final s = box();
    final bad = composeDocument(
        meta, s.withFloor(s.floors.first.copyWith(height: 100)));
    expect(() => encodeHouse(bad), throwsArgumentError);
  });

  test('a damaged file fails to load with a code, never with a throw', () {
    final raw = encodeHouse(composeDocument(meta, box()));
    final seeds = [for (var i = 0; i < 400; i++) i];
    for (final seed in seeds) {
      final json = jsonDecode(raw);
      // Walk to a pseudo-random node and damage it.
      Object? node = json;
      var key = seed;
      for (var depth = 0; depth < 6; depth++) {
        final children = node is Map
            ? node.keys.toList()
            : node is List
                ? [for (var i = 0; i < node.length; i++) i]
                : const [];
        if (children.isEmpty) break;
        final pick = children[key % children.length];
        key = key * 31 + 7;
        final child = node is Map ? node[pick] : (node! as List)[pick! as int];
        if (child is! Map && child is! List || depth == seed % 5) {
          final damage = [
            null,
            -1,
            2147483648,
            'x',
            1.5,
            <String, Object?>{},
            []
          ][seed % 7];
          if (node is Map) {
            if (seed % 11 == 0) {
              node.remove(pick);
            } else {
              node[pick] = damage;
            }
          } else {
            (node! as List)[pick! as int] = damage;
          }
          break;
        }
        node = child;
      }
      final loaded = loadHouse(utf8.encode(jsonEncode(json)));
      if (!loaded.isSuccess) {
        expect(loaded.failure!.errors, isNotEmpty);
        expect(loaded.failure!.errors.first.code, isNotEmpty);
      }
    }
  });

  test('every sampled command applies to a valid house or is refused', () {
    final docs = [
      composeDocument(meta, box()),
      composeDocument(meta, box(width: 30000, depth: 24000)),
    ];
    var applied = 0;
    for (final doc in docs) {
      final state = extractDesignState(doc);
      for (final (kind, args) in commandsFor(doc)) {
        final r = executeCommand(state, DesignCommand(kind, args), ctx);
        if (r is! Applied) continue;
        applied++;
        final next = composeDocument(meta, r.newState);
        expect(validateHouse(next), isEmpty, reason: '$kind $args');
        final again = loadHouse(utf8.encode(encodeHouse(next)));
        expect(again.isSuccess, isTrue, reason: '$kind $args');
        expect(extractDesignState(again.document!), r.newState,
            reason: '$kind $args');
      }
    }
    expect(applied, greaterThan(40));
  });
}

List<OpeningPlacement> documentOpeningsOf(HouseDocument doc) => deriveOpenings(
    doc, deriveFloorBase(doc, doc.floors.first.id), doc.floors.first.id);
