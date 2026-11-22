import 'package:yusal/core/axis/axis_resolver.dart';
import 'package:yusal/core/canonicalization/room_canonicalizer.dart';
import 'package:yusal/core/document/house_document.dart';
import 'package:yusal/core/validation/document_validator.dart';
import 'package:yusal/core/commands/design_commands.dart';

/// Flips the whole house left to right ([horizontal]) or top to bottom:
/// every floor, with its walls, rooms, doors, windows, stairs, cut
/// corners, furniture, service points, sleeves and marked issue areas.
/// Sizes stay; a door keeps its wall and swings to the mirrored side. The
/// plot around the house is left as it is.
EditResult mirrorPlan(HouseDocument doc, {required bool horizontal}) {
  final size = horizontal ? doc.footprint.width : doc.footprint.depth;
  // The axes whose positions flip, and the boundary names that swap.
  final flipped = horizontal ? AxisDir.V : AxisDir.H;
  final (low, high) = horizontal ? ('@left', '@right') : ('@bottom', '@top');
  String id(String axis) => axis == low
      ? high
      : axis == high
          ? low
          : axis;

  AxisRectangle rect(AxisRectangle r) => horizontal
      ? AxisRectangle(x0: id(r.x1), x1: id(r.x0), y0: r.y0, y1: r.y1)
      : AxisRectangle(x0: r.x0, x1: r.x1, y0: id(r.y1), y1: id(r.y0));

  final axes = AxisSystem(global: [
    for (final a in doc.axes.global)
      a.dir == flipped ? GlobalAxis(id: a.id, dir: a.dir, pos: size - a.pos) : a
  ], floor: [
    for (final a in doc.axes.floor)
      a.dir == flipped
          ? FloorAxis(
              id: a.id, floorId: a.floorId, dir: a.dir, pos: size - a.pos)
          : a
  ]);

  final floors = <Floor>[];
  for (final floor in doc.floors) {
    final resolved = resolveFloorAxes(doc, floor.id)!;
    // A wall along the flipped direction keeps its line and swaps its
    // ends; a wall across it moves to the mirrored line.
    bool runsAlong(BoundaryAnchor a) =>
        lookupAxis(resolved, a.axisId).axis?.dir != flipped;
    BoundaryAnchor anchor(BoundaryAnchor a) => runsAlong(a)
        ? BoundaryAnchor(
            axisId: a.axisId,
            startAxisId: id(a.endAxisId),
            endAxisId: id(a.startAxisId))
        : BoundaryAnchor(
            axisId: id(a.axisId),
            startAxisId: a.startAxisId,
            endAxisId: a.endAxisId);
    OpeningPosition position(Opening o) => !runsAlong(o.anchor)
        ? o.position
        : switch (o.position) {
            FromStartPosition(:final d) => FromEndPosition(d),
            FromEndPosition(:final d) => FromStartPosition(d),
            CenterPosition() => const CenterPosition(),
          };
    floors.add(Floor(
        id: floor.id,
        name: floor.name,
        height: floor.height,
        explicitWalls: floor.explicitWalls,
        rooms: [
          for (final r in floor.rooms)
            Room(
                id: r.id,
                type: r.type,
                name: r.name,
                regions: [for (final region in r.regions) rect(region)])
        ],
        wallOverrides: [
          for (final w in floor.wallOverrides)
            switch (w) {
              OpenWall() => OpenWall(id: w.id, anchor: anchor(w.anchor)),
              ThicknessWall() => ThicknessWall(
                  id: w.id, anchor: anchor(w.anchor), value: w.value),
              SolidWall() =>
                SolidWall(id: w.id, anchor: anchor(w.anchor), value: w.value),
            }
        ],
        openings: [
          for (final o in floor.openings)
            switch (o) {
              DoorOpening() => DoorOpening(
                  id: o.id,
                  anchor: anchor(o.anchor),
                  position: position(o),
                  width: o.width,
                  height: o.height,
                  sill: o.sill,
                  hinge: !runsAlong(o.anchor)
                      ? o.hinge
                      : o.hinge == Hinge.start
                          ? Hinge.end
                          : Hinge.start,
                  opensTo: runsAlong(o.anchor)
                      ? o.opensTo
                      : o.opensTo == OpeningSide.positiveSide
                          ? OpeningSide.negativeSide
                          : OpeningSide.positiveSide),
              WindowOpening() => WindowOpening(
                  id: o.id,
                  anchor: anchor(o.anchor),
                  position: position(o),
                  width: o.width,
                  height: o.height,
                  sill: o.sill),
              SlidingOpening() => SlidingOpening(
                  id: o.id,
                  anchor: anchor(o.anchor),
                  position: position(o),
                  width: o.width,
                  height: o.height,
                  sill: o.sill),
            }
        ],
        stairs: [
          for (final s in floor.stairs)
            () {
              final edge = switch ((horizontal, s.startEdge)) {
                (true, StairEdge.left) => StairEdge.right,
                (true, StairEdge.right) => StairEdge.left,
                (false, StairEdge.bottom) => StairEdge.top,
                (false, StairEdge.top) => StairEdge.bottom,
                _ => s.startEdge,
              };
              return switch (s) {
                StraightStair() => StraightStair(
                    id: s.id, region: rect(s.region), startEdge: edge),
                // A mirror image turns the other way.
                TurnStair() => TurnStair(
                    id: s.id,
                    region: rect(s.region),
                    startEdge: edge,
                    type: s.type,
                    turn: s.turn == StairTurn.left
                        ? StairTurn.right
                        : StairTurn.left),
              };
            }()
        ],
        outside: [
          for (final r in floor.outside) rect(r)
        ]));
  }

  int box(int at, int length) => size - at - length;
  final e = doc.extras;
  final extras = e.copyWith(furniture: [
    for (final f in e.furniture)
      horizontal
          ? f.copyWith(x: box(f.x, f.width))
          : f.copyWith(y: box(f.y, f.depth))
  ], utilities: [
    for (final u in e.utilities)
      horizontal ? u.copyWith(x: size - u.x) : u.copyWith(y: size - u.y)
  ], sleeves: [
    for (final s in e.sleeves)
      Sleeve(
          id: s.id,
          x: horizontal ? size - s.x : s.x,
          y: horizontal ? s.y : size - s.y,
          diameter: s.diameter,
          kind: s.kind)
  ], issues: [
    for (final i in e.issues)
      i.copyWith(areas: [
        for (final a in i.areas)
          horizontal
              ? (size - a.$3, a.$2, size - a.$1, a.$4)
              : (a.$1, size - a.$4, a.$3, size - a.$2)
      ])
  ]);

  HouseDocument compose(List<Floor> floors) => HouseDocument(
      schemaVersion: doc.schemaVersion,
      meta: doc.meta,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: axes,
      floors: floors,
      roof: doc.roof,
      extras: extras);

  // Room regions are kept in one canonical order of rectangles, which a
  // mirror image breaks: rebuild them on the flipped grid.
  final draft = compose(floors);
  final result = compose([
    for (final floor in floors)
      Floor(
          id: floor.id,
          name: floor.name,
          height: floor.height,
          explicitWalls: floor.explicitWalls,
          rooms: [
            for (final r in floor.rooms)
              Room(
                  id: r.id,
                  type: r.type,
                  name: r.name,
                  regions: canonicalizeRegions(
                          resolveFloorAxes(draft, floor.id)!, r.regions)
                      .regions)
          ],
          wallOverrides: floor.wallOverrides,
          openings: floor.openings,
          stairs: floor.stairs,
          outside: floor.outside)
  ]);
  final errors = validateHouse(result);
  if (errors.isNotEmpty) {
    return EditResult(null, '操作无法完成：${errors.first.message}');
  }
  return EditResult(result, null);
}
