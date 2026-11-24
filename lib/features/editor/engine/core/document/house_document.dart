import 'package:meta/meta.dart';
import 'package:yusal/features/editor/engine/core/document/house_extras.dart';
export 'house_extras.dart';

enum AxisDir { V, H }

/// What a room is for. [custom] ("房间") is a room nobody has named a use
/// for yet; it stays last, so the pickers end with it.
enum RoomType {
  living,
  bedroom,
  kitchen,
  bathroom,
  dining,
  hall,
  corridor,
  storage,
  boiler,
  custom
}

enum OpeningKind { door, window, sliding }

enum Hinge { start, end }

enum OpeningSide { positiveSide, negativeSide }

enum StairType { straight, L, U }

enum StairEdge { bottom, top, left, right }

enum StairTurn { left, right }

enum RoofType { flat, gable, hip }

enum PositionType { center, fromStart, fromEnd }

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

@immutable
class Meta {
  const Meta({
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  final String name;
  final String createdAt;
  final String updatedAt;
  @override
  bool operator ==(Object other) =>
      other is Meta &&
      name == other.name &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt;
  @override
  int get hashCode => Object.hash(name, createdAt, updatedAt);
}

@immutable
class Defaults {
  const Defaults({
    required this.outerWallThickness,
    required this.innerWallThickness,
    required this.slabThickness,
    required this.stairRiserMax,
    required this.stairTread,
    required this.stairWidthMin,
    required this.floorHeight,
    required this.doorWidth,
    required this.doorHeight,
    required this.windowWidth,
    required this.windowHeight,
    required this.windowSill,
  });
  final int outerWallThickness;
  final int innerWallThickness;
  final int slabThickness;
  final int stairRiserMax;
  final int stairTread;
  final int stairWidthMin;
  final int floorHeight;
  final int doorWidth;
  final int doorHeight;
  final int windowWidth;
  final int windowHeight;
  final int windowSill;
  @override
  bool operator ==(Object other) =>
      other is Defaults &&
      outerWallThickness == other.outerWallThickness &&
      innerWallThickness == other.innerWallThickness &&
      slabThickness == other.slabThickness &&
      stairRiserMax == other.stairRiserMax &&
      stairTread == other.stairTread &&
      stairWidthMin == other.stairWidthMin &&
      floorHeight == other.floorHeight &&
      doorWidth == other.doorWidth &&
      doorHeight == other.doorHeight &&
      windowWidth == other.windowWidth &&
      windowHeight == other.windowHeight &&
      windowSill == other.windowSill;
  @override
  int get hashCode => Object.hashAll([
        outerWallThickness,
        innerWallThickness,
        slabThickness,
        stairRiserMax,
        stairTread,
        stairWidthMin,
        floorHeight,
        doorWidth,
        doorHeight,
        windowWidth,
        windowHeight,
        windowSill
      ]);
}

@immutable
class BuildingFootprint {
  const BuildingFootprint({
    required this.width,
    required this.depth,
    required this.northAngleDeg,
  });
  final int width;
  final int depth;
  final int northAngleDeg;
  @override
  bool operator ==(Object other) =>
      other is BuildingFootprint &&
      width == other.width &&
      depth == other.depth &&
      northAngleDeg == other.northAngleDeg;
  @override
  int get hashCode => Object.hash(width, depth, northAngleDeg);
}

@immutable
class GlobalAxis {
  const GlobalAxis({required this.id, required this.dir, required this.pos});
  final String id;
  final AxisDir dir;
  final int pos;
  @override
  bool operator ==(Object other) =>
      other is GlobalAxis &&
      id == other.id &&
      dir == other.dir &&
      pos == other.pos;
  @override
  int get hashCode => Object.hash(id, dir, pos);
}

@immutable
class FloorAxis {
  const FloorAxis({
    required this.id,
    required this.floorId,
    required this.dir,
    required this.pos,
  });
  final String id;
  final String floorId;
  final AxisDir dir;
  final int pos;
  @override
  bool operator ==(Object other) =>
      other is FloorAxis &&
      id == other.id &&
      floorId == other.floorId &&
      dir == other.dir &&
      pos == other.pos;
  @override
  int get hashCode => Object.hash(id, floorId, dir, pos);
}

@immutable
class AxisSystem {
  AxisSystem({required List<GlobalAxis> global, required List<FloorAxis> floor})
      : global = List.unmodifiable(global),
        floor = List.unmodifiable(floor);
  final List<GlobalAxis> global;
  final List<FloorAxis> floor;
  @override
  bool operator ==(Object other) =>
      other is AxisSystem &&
      _listEquals(global, other.global) &&
      _listEquals(floor, other.floor);
  @override
  int get hashCode =>
      Object.hash(Object.hashAll(global), Object.hashAll(floor));
}

@immutable
class AxisRectangle {
  const AxisRectangle({
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
  });
  final String x0;
  final String x1;
  final String y0;
  final String y1;
  @override
  bool operator ==(Object other) =>
      other is AxisRectangle &&
      x0 == other.x0 &&
      x1 == other.x1 &&
      y0 == other.y0 &&
      y1 == other.y1;
  @override
  int get hashCode => Object.hash(x0, x1, y0, y1);
}

@immutable
class BoundaryAnchor {
  const BoundaryAnchor({
    required this.axisId,
    required this.startAxisId,
    required this.endAxisId,
  });
  final String axisId;
  final String startAxisId;
  final String endAxisId;
  @override
  bool operator ==(Object other) =>
      other is BoundaryAnchor &&
      axisId == other.axisId &&
      startAxisId == other.startAxisId &&
      endAxisId == other.endAxisId;
  @override
  int get hashCode => Object.hash(axisId, startAxisId, endAxisId);
}

sealed class WallOverride {
  const WallOverride({required this.id, required this.anchor});
  final String id;
  final BoundaryAnchor anchor;
}

@immutable
class OpenWall extends WallOverride {
  const OpenWall({required super.id, required super.anchor});
  @override
  bool operator ==(Object other) =>
      other is OpenWall && id == other.id && anchor == other.anchor;
  @override
  int get hashCode => Object.hash(id, anchor);
}

@immutable
class ThicknessWall extends WallOverride {
  const ThicknessWall({
    required super.id,
    required super.anchor,
    required this.value,
  });
  final int value;
  @override
  bool operator ==(Object other) =>
      other is ThicknessWall &&
      id == other.id &&
      anchor == other.anchor &&
      value == other.value;
  @override
  int get hashCode => Object.hash(id, anchor, value);
}

/// An independently drawn wall, including unfinished partitions.
@immutable
class SolidWall extends WallOverride {
  const SolidWall(
      {required super.id,
      required super.anchor,
      required this.value,
      this.height});

  /// Thickness, in millimetres.
  final int value;

  /// How high the wall stands, in millimetres; null for a wall that
  /// reaches the ceiling. A wall given a height is a low wall (a knee
  /// wall, a bar, a balustrade): one can see over it, so it divides no
  /// room, carries no door or window and takes nothing from a room's
  /// measured area.
  final int? height;

  bool get low => height != null;

  @override
  bool operator ==(Object other) =>
      other is SolidWall &&
      id == other.id &&
      anchor == other.anchor &&
      value == other.value &&
      height == other.height;
  @override
  int get hashCode => Object.hash(id, anchor, value, height);
}

/// The lowest and highest a low wall may stand, in millimetres.
const lowWallMin = 300;
const lowWallMax = 2100;

sealed class OpeningPosition {
  const OpeningPosition();
}

@immutable
class CenterPosition extends OpeningPosition {
  const CenterPosition();
  @override
  bool operator ==(Object other) => other is CenterPosition;
  @override
  int get hashCode => 0;
}

@immutable
class FromStartPosition extends OpeningPosition {
  const FromStartPosition(this.d);
  final int d;
  @override
  bool operator ==(Object other) => other is FromStartPosition && d == other.d;
  @override
  int get hashCode => Object.hash('fromStart', d);
}

@immutable
class FromEndPosition extends OpeningPosition {
  const FromEndPosition(this.d);
  final int d;
  @override
  bool operator ==(Object other) => other is FromEndPosition && d == other.d;
  @override
  int get hashCode => Object.hash('fromEnd', d);
}

sealed class Opening {
  const Opening({
    required this.id,
    required this.anchor,
    required this.position,
    required this.width,
    required this.height,
    required this.sill,
  });
  final String id;
  final BoundaryAnchor anchor;
  final OpeningPosition position;
  final int width;
  final int height;
  final int sill;
  OpeningKind get kind;
}

@immutable
class DoorOpening extends Opening {
  const DoorOpening({
    required super.id,
    required super.anchor,
    required super.position,
    required super.width,
    required super.height,
    required super.sill,
    required this.hinge,
    required this.opensTo,
  });
  final Hinge hinge;
  final OpeningSide opensTo;
  @override
  bool operator ==(Object other) =>
      other is DoorOpening &&
      id == other.id &&
      anchor == other.anchor &&
      position == other.position &&
      width == other.width &&
      height == other.height &&
      sill == other.sill &&
      hinge == other.hinge &&
      opensTo == other.opensTo;
  @override
  int get hashCode =>
      Object.hash(id, anchor, position, width, height, sill, hinge, opensTo);
  @override
  OpeningKind get kind => OpeningKind.door;
}

@immutable
class WindowOpening extends Opening {
  const WindowOpening({
    required super.id,
    required super.anchor,
    required super.position,
    required super.width,
    required super.height,
    required super.sill,
  });
  @override
  OpeningKind get kind => OpeningKind.window;
  @override
  bool operator ==(Object other) =>
      other is WindowOpening &&
      id == other.id &&
      anchor == other.anchor &&
      position == other.position &&
      width == other.width &&
      height == other.height &&
      sill == other.sill;
  @override
  int get hashCode => Object.hash(id, anchor, position, width, height, sill);
}

@immutable
class SlidingOpening extends Opening {
  const SlidingOpening({
    required super.id,
    required super.anchor,
    required super.position,
    required super.width,
    required super.height,
    required super.sill,
  });
  @override
  OpeningKind get kind => OpeningKind.sliding;
  @override
  bool operator ==(Object other) =>
      other is SlidingOpening &&
      id == other.id &&
      anchor == other.anchor &&
      position == other.position &&
      width == other.width &&
      height == other.height &&
      sill == other.sill;
  @override
  int get hashCode => Object.hash(id, anchor, position, width, height, sill);
}

sealed class Stair {
  const Stair({
    required this.id,
    required this.region,
    required this.startEdge,
  });
  final String id;
  final AxisRectangle region;
  final StairEdge startEdge;
  StairType get type;
}

@immutable
class StraightStair extends Stair {
  const StraightStair({
    required super.id,
    required super.region,
    required super.startEdge,
  });
  @override
  bool operator ==(Object other) =>
      other is StraightStair &&
      id == other.id &&
      region == other.region &&
      startEdge == other.startEdge;
  @override
  int get hashCode => Object.hash(id, region, startEdge);
  @override
  StairType get type => StairType.straight;
}

@immutable
class TurnStair extends Stair {
  const TurnStair({
    required super.id,
    required super.region,
    required super.startEdge,
    required this.turn,
    required this.type,
  });
  final StairTurn turn;
  @override
  bool operator ==(Object other) =>
      other is TurnStair &&
      id == other.id &&
      region == other.region &&
      startEdge == other.startEdge &&
      turn == other.turn &&
      type == other.type;
  @override
  int get hashCode => Object.hash(id, region, startEdge, turn, type);
  @override
  final StairType type;
}

@immutable
class Roof {
  const Roof.flat(this.parapetHeight)
      : type = RoofType.flat,
        ridgeDir = null,
        pitchDeg = null,
        overhang = null;
  const Roof.gable({
    required this.ridgeDir,
    required this.pitchDeg,
    required this.overhang,
  })  : type = RoofType.gable,
        parapetHeight = null;

  /// Four slopes; the ridge runs along the longer side (version 4).
  const Roof.hip({required this.pitchDeg, required this.overhang})
      : type = RoofType.hip,
        parapetHeight = null,
        ridgeDir = null;
  final RoofType type;
  bool get pitched => type != RoofType.flat;
  final int? parapetHeight;
  final AxisDir? ridgeDir;
  final int? pitchDeg;
  final int? overhang;
  @override
  bool operator ==(Object other) =>
      other is Roof &&
      type == other.type &&
      parapetHeight == other.parapetHeight &&
      ridgeDir == other.ridgeDir &&
      pitchDeg == other.pitchDeg &&
      overhang == other.overhang;
  @override
  int get hashCode =>
      Object.hash(type, parapetHeight, ridgeDir, pitchDeg, overhang);
}

@immutable
class Room {
  Room({
    required this.id,
    required this.type,
    required this.name,
    required List<AxisRectangle> regions,
  }) : regions = List.unmodifiable(regions);
  final String id;
  final RoomType type;
  final String name;
  final List<AxisRectangle> regions;
  @override
  bool operator ==(Object other) =>
      other is Room &&
      id == other.id &&
      type == other.type &&
      name == other.name &&
      _listEquals(regions, other.regions);
  @override
  int get hashCode => Object.hash(id, type, name, Object.hashAll(regions));
}

@immutable
class Floor {
  Floor({
    this.explicitWalls = false,
    required this.id,
    required this.name,
    required this.height,
    required List<Room> rooms,
    required List<WallOverride> wallOverrides,
    required List<Opening> openings,
    required List<Stair> stairs,
    List<AxisRectangle> outside = const [],
  })  : rooms = List.unmodifiable(rooms),
        wallOverrides = List.unmodifiable(wallOverrides),
        openings = List.unmodifiable(openings),
        stairs = List.unmodifiable(stairs),
        outside = List.unmodifiable(outside);
  final String id;
  final String name;
  final bool explicitWalls;
  final int height;
  final List<Room> rooms;
  final List<WallOverride> wallOverrides;
  final List<Opening> openings;
  final List<Stair> stairs;

  /// Parts of the footprint rectangle left outside the building on this
  /// floor (an L-shaped house, a terrace over the floor below). Walls run
  /// along their edges as outside walls (version 4).
  final List<AxisRectangle> outside;
  @override
  bool operator ==(Object other) =>
      other is Floor &&
      explicitWalls == other.explicitWalls &&
      id == other.id &&
      name == other.name &&
      height == other.height &&
      _listEquals(rooms, other.rooms) &&
      _listEquals(wallOverrides, other.wallOverrides) &&
      _listEquals(openings, other.openings) &&
      _listEquals(stairs, other.stairs) &&
      _listEquals(outside, other.outside);
  @override
  int get hashCode => Object.hash(
      id,
      name,
      height,
      Object.hashAll(rooms),
      Object.hashAll(wallOverrides),
      explicitWalls,
      Object.hashAll(openings),
      Object.hashAll(stairs),
      Object.hashAll(outside));
}

@immutable
class HouseDocument {
  HouseDocument({
    required this.schemaVersion,
    required this.meta,
    this.mainEntranceOpeningId,
    required this.defaults,
    required this.footprint,
    required this.axes,
    required List<Floor> floors,
    required this.roof,
    HouseExtras? extras,
  })  : floors = List.unmodifiable(floors),
        extras = extras ?? HouseExtras.empty;
  final int schemaVersion;
  final Meta meta;
  final String? mainEntranceOpeningId;
  final Defaults defaults;
  final BuildingFootprint footprint;
  final AxisSystem axes;
  final List<Floor> floors;
  final Roof roof;

  /// Furniture, notes and construction specs (schema version 3).
  final HouseExtras extras;
  @override
  bool operator ==(Object other) =>
      other is HouseDocument &&
      schemaVersion == other.schemaVersion &&
      meta == other.meta &&
      mainEntranceOpeningId == other.mainEntranceOpeningId &&
      defaults == other.defaults &&
      footprint == other.footprint &&
      axes == other.axes &&
      _listEquals(floors, other.floors) &&
      roof == other.roof &&
      extras == other.extras;
  @override
  int get hashCode => Object.hash(
        schemaVersion,
        meta,
        mainEntranceOpeningId,
        defaults,
        footprint,
        axes,
        Object.hashAll(floors),
        roof,
        extras,
      );
}

@immutable
class UndoableDesignState {
  UndoableDesignState({
    required this.defaults,
    required this.footprint,
    required this.axes,
    required List<Floor> floors,
    required this.roof,
    this.mainEntranceOpeningId,
    HouseExtras? extras,
  })  : floors = List.unmodifiable(floors),
        extras = extras ?? HouseExtras.empty;
  final Defaults defaults;
  final BuildingFootprint footprint;
  final AxisSystem axes;
  final List<Floor> floors;
  final Roof roof;
  final String? mainEntranceOpeningId;
  final HouseExtras extras;
  @override
  bool operator ==(Object other) =>
      other is UndoableDesignState &&
      defaults == other.defaults &&
      footprint == other.footprint &&
      axes == other.axes &&
      roof == other.roof &&
      mainEntranceOpeningId == other.mainEntranceOpeningId &&
      extras == other.extras &&
      floors.length == other.floors.length &&
      [for (var i = 0; i < floors.length; i++) floors[i] == other.floors[i]]
          .every((equal) => equal);
  @override
  int get hashCode => Object.hash(defaults, footprint, axes, roof,
      mainEntranceOpeningId, extras, Object.hashAll(floors));

  UndoableDesignState withExtras(HouseExtras value) => UndoableDesignState(
      defaults: defaults,
      footprint: footprint,
      axes: axes,
      floors: floors,
      roof: roof,
      mainEntranceOpeningId: mainEntranceOpeningId,
      extras: value);
}

UndoableDesignState extractDesignState(HouseDocument doc) =>
    UndoableDesignState(
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: doc.axes,
      floors: doc.floors,
      roof: doc.roof,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      extras: doc.extras,
    );

/// Extras with references to removed floors, rooms or openings dropped.
HouseExtras prunedExtras(HouseExtras extras, List<Floor> floors) =>
    extras.pruned({
      for (final f in floors) f.id
    }, {
      for (final f in floors)
        for (final r in f.rooms) r.id
    }, {
      for (final f in floors)
        for (final o in f.openings) o.id
    });

/// Whether a design uses anything only schema version 4 can hold.
bool needsVersion4(Roof roof, HouseExtras extras, List<Floor> floors) =>
    roof.type == RoofType.hip ||
    extras.needsVersion4 ||
    floors.any((f) => f.outside.isNotEmpty);

HouseDocument composeDocument(Meta meta, UndoableDesignState state) {
  final extras = prunedExtras(state.extras, state.floors);
  return HouseDocument(
    schemaVersion: needsVersion4(state.roof, extras, state.floors)
        ? 4
        : !extras.isEmpty
            ? 3
            : state.floors.any((f) =>
                    f.explicitWalls ||
                    f.wallOverrides.any((w) => w is SolidWall))
                ? 2
                : 1,
    meta: meta,
    mainEntranceOpeningId: state.mainEntranceOpeningId,
    defaults: state.defaults,
    footprint: state.footprint,
    axes: state.axes,
    floors: state.floors,
    roof: state.roof,
    extras: extras,
  );
}

/// [doc] carrying [extras] (pruned), for results of geometry operations
/// that build documents without knowing about extras.
HouseDocument withExtras(HouseDocument doc, HouseExtras extras) =>
    composeDocument(doc.meta, extractDesignState(doc).withExtras(extras));
