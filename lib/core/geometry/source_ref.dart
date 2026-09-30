import 'floor_base.dart';

sealed class SourceRef {
  const SourceRef();
}

class RoomSource extends SourceRef {
  const RoomSource(this.roomId);
  final String roomId;
  @override
  bool operator ==(Object other) =>
      other is RoomSource && other.roomId == roomId;
  @override
  int get hashCode => Object.hash(RoomSource, roomId);
}

class StairSource extends SourceRef {
  const StairSource(this.stairId);
  final String stairId;
  @override
  bool operator ==(Object other) =>
      other is StairSource && other.stairId == stairId;
  @override
  int get hashCode => Object.hash(StairSource, stairId);
}

class OpeningSource extends SourceRef {
  const OpeningSource(this.openingId);
  final String openingId;
  @override
  bool operator ==(Object other) =>
      other is OpeningSource && other.openingId == openingId;
  @override
  int get hashCode => Object.hash(OpeningSource, openingId);
}

class WallSource extends SourceRef {
  const WallSource(this.wall);
  final WallRef wall;
  @override
  bool operator ==(Object other) => other is WallSource && other.wall == wall;
  @override
  int get hashCode => Object.hash(WallSource, wall);
}
