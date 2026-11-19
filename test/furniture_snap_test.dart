import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/document/house_extras.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/geometry/furniture_snap.dart';

FurnitureItem bed(int x, int y) => FurnitureItem(
    id: 'f',
    floorId: 'floor',
    kind: FurnitureKind.bed,
    x: x,
    y: y,
    width: 1600,
    depth: 2000,
    height: 500);

void main() {
  // An L-shaped room: 4 × 3 m with a 2 × 2 m arm above its left half.
  const room = [PlanRect(100, 100, 4100, 3100), PlanRect(100, 3100, 2100, 5100)];

  test('furniture near a wall goes flush against it', () {
    final corner = snapToWalls(bed(200, 180), [room]);
    expect((corner.x, corner.y), (100, 100));
    final right = snapToWalls(bed(2450, 600), [room]);
    expect((right.x, right.y), (2500, 600));
  });

  test('furniture away from the walls stays where it is put', () {
    final middle = snapToWalls(bed(1200, 600), [room]);
    expect((middle.x, middle.y), (1200, 600));
    final outside = snapToWalls(bed(9000, 9000), [room]);
    expect((outside.x, outside.y), (9000, 9000));
  });

  test('where the room carries on there is no wall to stick to', () {
    // Top edge of the lower part under the arm: open, so no snap.
    final under = snapToWalls(bed(300, 1050), [room]);
    expect(under.y, 1050);
    // The same edge right of the arm is a wall.
    final beside = snapToWalls(bed(2300, 1050), [room]);
    expect(beside.y, 1100);
  });
}
