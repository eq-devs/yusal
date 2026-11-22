import 'package:yusal/core/document/house_extras.dart';
import 'package:yusal/core/geometry/floor_base.dart';

/// Where a dragged piece of furniture should land: flush against a wall
/// of the room it is in when it is within [reach] mm of that wall,
/// otherwise where it is. [rooms] are the clear rectangles of each room.
FurnitureItem snapToWalls(FurnitureItem f, Iterable<List<PlanRect>> rooms,
    {int reach = 150}) {
  final cx = f.x + f.width / 2;
  final cy = f.y + f.depth / 2;
  for (final clear in rooms) {
    final rect = clear.where((r) => r.contains(cx, cy)).firstOrNull;
    if (rect == null) continue;
    // An edge is a wall unless the room carries on past it.
    bool wall(double x, double y) => !clear.any((r) => r.contains(x, y));
    var x = f.x;
    var y = f.y;
    if ((f.x - rect.left).abs() <= reach && wall(rect.left - 1, cy)) {
      x = rect.left.ceil();
    } else if ((rect.right - f.right).abs() <= reach &&
        wall(rect.right + 1, cy)) {
      x = rect.right.floor() - f.width;
    }
    if ((f.y - rect.bottom).abs() <= reach && wall(cx, rect.bottom - 1)) {
      y = rect.bottom.ceil();
    } else if ((rect.top - f.top).abs() <= reach && wall(cx, rect.top + 1)) {
      y = rect.top.floor() - f.depth;
    }
    return f.copyWith(x: x, y: y);
  }
  return f;
}
