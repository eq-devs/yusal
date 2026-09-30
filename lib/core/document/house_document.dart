enum AxisDir { V, H }

enum RoomType { living, bedroom, kitchen, bathroom, dining, custom }

enum OpeningKind { door, window, sliding }

enum Hinge { start, end }

enum OpeningSide { positiveSide, negativeSide }

enum StairType { straight, L, U }

enum StairEdge { bottom, top, left, right }

enum StairTurn { left, right }

enum RoofType { flat, gable }

enum PositionType { center, fromStart, fromEnd }

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class Meta {
  const Meta({
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  final String name, createdAt, updatedAt;
  @override
  bool operator ==(Object other) =>
      other is Meta &&
      name == other.name &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt;
  @override
  int get hashCode => Object.hash(name, createdAt, updatedAt);
}

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
  final int outerWallThickness,
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
      windowSill;
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

class BuildingFootprint {
  const BuildingFootprint({
    required this.width,
    required this.depth,
    required this.northAngleDeg,
  });
  final int width, depth, northAngleDeg;
  @override
  bool operator ==(Object other) =>
      other is BuildingFootprint &&
      width == other.width &&
      depth == other.depth &&
      northAngleDeg == other.northAngleDeg;
  @override
  int get hashCode => Object.hash(width, depth, northAngleDeg);
}

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

class FloorAxis {
  const FloorAxis({
    required this.id,
    required this.floorId,
    required this.dir,
    required this.pos,
  });
  final String id, floorId;
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

class AxisRectangle {
  const AxisRectangle({
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
  });
  final String x0, x1, y0, y1;
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

class BoundaryAnchor {
  const BoundaryAnchor({
    required this.axisId,
    required this.startAxisId,
    required this.endAxisId,
  });
  final String axisId, startAxisId, endAxisId;
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

class OpenWall extends WallOverride {
  const OpenWall({required super.id, required super.anchor});
  @override
  bool operator ==(Object other) =>
      other is OpenWall && id == other.id && anchor == other.anchor;
  @override
  int get hashCode => Object.hash(id, anchor);
}

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

sealed class OpeningPosition {
  const OpeningPosition();
}

class CenterPosition extends OpeningPosition {
  const CenterPosition();
  @override
  bool operator ==(Object other) => other is CenterPosition;
  @override
  int get hashCode => 0;
}

class FromStartPosition extends OpeningPosition {
  const FromStartPosition(this.d);
  final int d;
  @override
  bool operator ==(Object other) => other is FromStartPosition && d == other.d;
  @override
  int get hashCode => Object.hash('fromStart', d);
}

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
  final int width, height, sill;
  OpeningKind get kind;
}

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
  final RoofType type;
  final int? parapetHeight;
  final AxisDir? ridgeDir;
  final int? pitchDeg, overhang;
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

class Floor {
  Floor({
    required this.id,
    required this.name,
    required this.height,
    required List<Room> rooms,
    required List<WallOverride> wallOverrides,
    required List<Opening> openings,
    required List<Stair> stairs,
  })  : rooms = List.unmodifiable(rooms),
        wallOverrides = List.unmodifiable(wallOverrides),
        openings = List.unmodifiable(openings),
        stairs = List.unmodifiable(stairs);
  final String id, name;
  final int height;
  final List<Room> rooms;
  final List<WallOverride> wallOverrides;
  final List<Opening> openings;
  final List<Stair> stairs;
  @override
  bool operator ==(Object other) =>
      other is Floor &&
      id == other.id &&
      name == other.name &&
      height == other.height &&
      _listEquals(rooms, other.rooms) &&
      _listEquals(wallOverrides, other.wallOverrides) &&
      _listEquals(openings, other.openings) &&
      _listEquals(stairs, other.stairs);
  @override
  int get hashCode => Object.hash(
      id,
      name,
      height,
      Object.hashAll(rooms),
      Object.hashAll(wallOverrides),
      Object.hashAll(openings),
      Object.hashAll(stairs));
}

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
  }) : floors = List.unmodifiable(floors);
  final int schemaVersion;
  final Meta meta;
  final String? mainEntranceOpeningId;
  final Defaults defaults;
  final BuildingFootprint footprint;
  final AxisSystem axes;
  final List<Floor> floors;
  final Roof roof;
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
      roof == other.roof;
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
      );
}

class UndoableDesignState {
  UndoableDesignState({
    required this.defaults,
    required this.footprint,
    required this.axes,
    required List<Floor> floors,
    required this.roof,
    this.mainEntranceOpeningId,
  }) : floors = List.unmodifiable(floors);
  final Defaults defaults;
  final BuildingFootprint footprint;
  final AxisSystem axes;
  final List<Floor> floors;
  final Roof roof;
  final String? mainEntranceOpeningId;
  @override
  bool operator ==(Object other) =>
      other is UndoableDesignState &&
      defaults == other.defaults &&
      footprint == other.footprint &&
      axes == other.axes &&
      roof == other.roof &&
      mainEntranceOpeningId == other.mainEntranceOpeningId &&
      floors.length == other.floors.length &&
      [for (var i = 0; i < floors.length; i++) floors[i] == other.floors[i]]
          .every((equal) => equal);
  @override
  int get hashCode => Object.hash(defaults, footprint, axes, roof,
      mainEntranceOpeningId, Object.hashAll(floors));
}

UndoableDesignState extractDesignState(HouseDocument doc) =>
    UndoableDesignState(
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: doc.axes,
      floors: doc.floors,
      roof: doc.roof,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
    );
HouseDocument composeDocument(Meta meta, UndoableDesignState state) =>
    HouseDocument(
      schemaVersion: 1,
      meta: meta,
      mainEntranceOpeningId: state.mainEntranceOpeningId,
      defaults: state.defaults,
      footprint: state.footprint,
      axes: state.axes,
      floors: state.floors,
      roof: state.roof,
    );
