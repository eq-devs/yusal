import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';

class ValidationError {
  const ValidationError(
    this.code,
    this.path,
    this.message, {
    this.related = const [],
  });
  final String code, path, message;
  final List<String> related;
}

List<ValidationError> validateHouse(HouseDocument d) {
  final out = <ValidationError>[];
  void add(
    int n,
    String path,
    String message, {
    List<String> related = const [],
  }) {
    if (out.length < 100)
      out.add(
        ValidationError(
          'INV${n.toString().padLeft(2, '0')}',
          path,
          message,
          related: related,
        ),
      );
  }

  final first = <String, String>{};
  void id(String value, String path) {
    final prior = first[value];
    if (prior == null) {
      first[value] = path;
    } else {
      add(1, '$path/id', 'id $value 重复', related: ['$prior/id']);
    }
  }

  for (var i = 0; i < d.axes.global.length; i++) {
    final a = d.axes.global[i];
    id(a.id, '/axes/global/$i');
  }
  for (var i = 0; i < d.axes.floor.length; i++) {
    final a = d.axes.floor[i];
    id(a.id, '/axes/floor/$i');
  }
  for (var f = 0; f < d.floors.length; f++) {
    final floor = d.floors[f];
    id(floor.id, '/floors/$f');
    for (var r = 0; r < floor.rooms.length; r++)
      id(floor.rooms[r].id, '/floors/$f/rooms/$r');
    for (var w = 0; w < floor.wallOverrides.length; w++)
      id(floor.wallOverrides[w].id, '/floors/$f/wallOverrides/$w');
    for (var o = 0; o < floor.openings.length; o++)
      id(floor.openings[o].id, '/floors/$f/openings/$o');
    for (var s = 0; s < floor.stairs.length; s++)
      id(floor.stairs[s].id, '/floors/$f/stairs/$s');
  }
  if (d.footprint.width < 3000 || d.footprint.width > 100000)
    add(3, '/footprint/width', 'width 必须在 3000 到 100000 毫米之间');
  if (d.footprint.depth < 3000 || d.footprint.depth > 100000)
    add(3, '/footprint/depth', 'depth 必须在 3000 到 100000 毫米之间');
  for (var i = 0; i < d.axes.global.length; i++) {
    final a = d.axes.global[i];
    if (a.id.startsWith('@')) add(6, '/axes/global/$i/id', '已保存轴线不得使用保留 id');
  }
  for (var i = 0; i < d.axes.floor.length; i++) {
    final a = d.axes.floor[i];
    if (a.id.startsWith('@')) add(6, '/axes/floor/$i/id', '已保存轴线不得使用保留 id');
    if (!d.floors.any((f) => f.id == a.floorId))
      add(7, '/axes/floor/$i/floorId', 'FloorAxis.floorId 必须存在');
  }
  for (var f = 0; f < d.floors.length; f++) {
    final floor = d.floors[f];
    for (var w = 0; w < floor.wallOverrides.length; w++) {
      final x = floor.wallOverrides[w];
      if (x is ThicknessWall && (x.value < 60 || x.value > 600))
        add(13, '/floors/$f/wallOverrides/$w/value', '墙厚必须在 60 到 600 毫米之间');
    }
    if (floor.height < 2400) add(15, '/floors/$f/height', '层高不得低于 2400 毫米');
    if (f == d.floors.length - 1)
      for (var s = 0; s < floor.stairs.length; s++)
        add(16, '/floors/$f/stairs/$s', '楼梯不能放在顶层');
    for (var o = 0; o < floor.openings.length; o++) {
      final x = floor.openings[o], p = '/floors/$f/openings/$o';
      if (x.width <= 0) add(18, '$p/width', '宽度必须大于零');
      if (x.height <= 0) add(18, '$p/height', '高度必须大于零');
      if (x.sill < 0) add(18, '$p/sill', '窗台高度不得为负');
      if (x.position is FromStartPosition &&
          (x.position as FromStartPosition).d < 0)
        add(18, '$p/position/d', '定位距离不得为负');
      if (x.position is FromEndPosition &&
          (x.position as FromEndPosition).d < 0)
        add(18, '$p/position/d', '定位距离不得为负');
    }
  }
  if (d.floors.isEmpty) add(15, '/floors', '至少需要一层');
  if (d.footprint.northAngleDeg < 0 || d.footprint.northAngleDeg >= 360)
    add(23, '/footprint/northAngleDeg', '方位角必须在 0 到 359 之间');
  final defs = d.defaults;
  final positive = {
    'outerWallThickness': defs.outerWallThickness,
    'innerWallThickness': defs.innerWallThickness,
    'slabThickness': defs.slabThickness,
    'stairRiserMax': defs.stairRiserMax,
    'stairTread': defs.stairTread,
    'stairWidthMin': defs.stairWidthMin,
    'doorWidth': defs.doorWidth,
    'doorHeight': defs.doorHeight,
    'windowWidth': defs.windowWidth,
    'windowHeight': defs.windowHeight,
  };
  for (final e in positive.entries)
    if (e.value <= 0) add(22, '/defaults/${e.key}', '默认值必须大于零');
  if (defs.windowSill < 0) add(22, '/defaults/windowSill', 'windowSill 不得为负');
  if (defs.floorHeight < 2400)
    add(22, '/defaults/floorHeight', 'floorHeight 不得低于 2400');
  if (d.roof.type == RoofType.gable) {
    if (d.roof.pitchDeg! <= 0 || d.roof.pitchDeg! > 60)
      add(21, '/roof/pitchDeg', '坡度必须在 1 到 60 度之间');
    if (d.roof.overhang! < 0 || d.roof.overhang! > 1500)
      add(21, '/roof/overhang', '挑檐必须在 0 到 1500 毫米之间');
  } else if (d.roof.parapetHeight! < 0 || d.roof.parapetHeight! > 1500)
    add(21, '/roof/parapetHeight', '女儿墙高度必须在 0 到 1500 毫米之间');
  if (d.schemaVersion != 1) add(24, '/schemaVersion', 'schemaVersion 必须为 1');
  final orderedA1 = [for (var i = 0; i < out.length; i++) (i: i, error: out[i])]
    ..sort((a, b) {
      final code = a.error.code.compareTo(b.error.code);
      return code != 0 ? code : a.i.compareTo(b.i);
    });
  out
    ..clear()
    ..addAll(orderedA1.map((item) => item.error));
  if (out.any((e) => e.code == 'INV01' || e.code == 'INV03')) {
    return List.unmodifiable(out);
  }
  for (var i = 0; i < d.axes.global.length; i++) {
    final a = d.axes.global[i];
    if (a.dir == AxisDir.V
        ? (a.pos <= 0 || a.pos >= d.footprint.width)
        : (a.pos <= 0 || a.pos >= d.footprint.depth))
      add(4, '/axes/global/$i/pos', '内部轴线超出外轮廓');
  }
  for (var i = 0; i < d.axes.floor.length; i++) {
    final a = d.axes.floor[i];
    if (a.dir == AxisDir.V
        ? (a.pos <= 0 || a.pos >= d.footprint.width)
        : (a.pos <= 0 || a.pos >= d.footprint.depth))
      add(4, '/axes/floor/$i/pos', '内部轴线超出外轮廓');
  }
  if (d.mainEntranceOpeningId != null) {
    final doors = d.floors
        .expand((f) => f.openings)
        .where((o) => o.id == d.mainEntranceOpeningId && o is DoorOpening);
    if (doors.length != 1) add(20, '/mainEntranceOpeningId', '主入口必须引用唯一存在的门');
  }
  final resolvedFloors = [
    for (final floor in d.floors) resolveFloorAxes(d, floor.id)!
  ];
  final globalIssues = <ValidationError>[], localIssues = <ValidationError>[];
  final reported = <({AxisDir? dir, String first, String second})>{};
  for (final axes in resolvedFloors) {
    final bad = {
      for (final issue
          in axes.issues.where((e) => e.code == 'POSITION_OUT_OF_RANGE'))
        ...issue.axisIds
    };
    for (final issue in axes.issues.where((e) =>
        e.code == 'POSITION_COLLISION' || e.code == 'SPACING_TOO_SMALL')) {
      if (issue.axisIds.any(bad.contains)) continue;
      final a = lookupAxis(axes, issue.axisIds.first).axis!,
          b = lookupAxis(axes, issue.axisIds.last).axis!;
      final key = (dir: issue.dir, first: a.id, second: b.id);
      String path(ResolvedAxis axis) {
        if (axis.kind == 'global')
          return '/axes/global/${d.axes.global.indexWhere((v) => v.id == axis.id)}/pos';
        return '/axes/floor/${d.axes.floor.indexWhere((v) => v.id == axis.id)}/pos';
      }

      final local = a.kind == 'floor' || b.kind == 'floor';
      if (!local && !reported.add(key)) continue;
      final target =
          local ? (b.kind == 'floor' ? b : a) : (b.kind == 'global' ? b : a);
      final other = identical(target, a) ? b : a;
      final error = ValidationError(
          'INV05', path(target), '轴线 ${a.id} 与 ${b.id} 的间距不足或重合',
          related: other.kind == 'boundary' ? [] : [path(other)]);
      (local ? localIssues : globalIssues).add(error);
    }
  }
  for (final error in [...globalIssues, ...localIssues]) {
    if (out.length >= 100) break;
    out.add(error);
  }
  for (var f = 0; f < d.floors.length; f++) {
    final floor = d.floors[f], axes = resolvedFloors[f];
    if (axes.issues.isNotEmpty) continue;
    final placed = <({String id, String path, Set<Cell> cells})>[];
    final validObjects = <({String id, String path, Set<Cell> cells})>[];
    for (var r = 0; r < floor.rooms.length; r++) {
      final room = floor.rooms[r], path = '/floors/$f/rooms/$r/regions';
      if (room.regions.isEmpty) {
        add(12, path, '房间必须有区域');
        continue;
      }
      final expanded = regionCells(axes, room.regions);
      if (!expanded.isSuccess) {
        for (final e in expanded.errors) {
          final pieces = e.field.split('/');
          final idx = pieces.length > 1 ? pieces[1] : '0';
          final fld = pieces.length > 2 ? pieces[2] : '';
          add(
              e.code == 'AXIS_NOT_VISIBLE'
                  ? 9
                  : e.code == 'INVALID_RESERVED_REF'
                      ? 6
                      : 8,
              '$path/$idx${fld == 'x' || fld == 'y' ? '' : '/$fld'}',
              '房间区域引用无效（${e.code}）');
        }
        continue;
      }
      if (expanded.selfOverlap || !isCanonical(axes, room.regions))
        add(12, path, '房间区域不是规范形式');
      if (!isConnected(expanded.cells)) add(12, path, '房间区域不连通');
      validObjects.add((
        id: room.id,
        path: '/floors/$f/rooms/$r',
        cells: expanded.cells,
      ));
    }
    for (var s = 0; s < floor.stairs.length; s++) {
      final stair = floor.stairs[s], resolved = resolveRect(axes, stair.region);
      if (!resolved.isSuccess) {
        for (final error in resolved.errors)
          add(
              error.code == 'AXIS_NOT_VISIBLE'
                  ? 9
                  : error.code == 'INVALID_RESERVED_REF'
                      ? 6
                      : 8,
              '/floors/$f/stairs/$s/region${error.field == 'x' || error.field == 'y' ? '' : '/${error.field}'}',
              '楼梯区域引用无效（${error.code}）');
        continue;
      }
      validObjects.add((
        id: stair.id,
        path: '/floors/$f/stairs/$s',
        cells: cellsOfRect(resolved.rect!).toSet(),
      ));
    }
    for (final obj in validObjects) {
      for (final prior in placed) {
        if (obj.cells.any(prior.cells.contains))
          add(11, obj.path, '对象 ${obj.id} 与 ${prior.id} 占用重叠',
              related: [prior.path]);
      }
      placed.add(obj);
    }
    final spans = <({String axis, int start, int end, String path})>[];
    for (var w = 0; w < floor.wallOverrides.length; w++) {
      final wall = floor.wallOverrides[w],
          res = resolveAnchor(axes, wall.anchor);
      if (!res.isSuccess) {
        for (final error in res.errors)
          add(
              error.code == 'AXIS_NOT_VISIBLE'
                  ? 9
                  : error.code == 'INVALID_RESERVED_REF'
                      ? 6
                      : 10,
              '/floors/$f/wallOverrides/$w/anchor${error.code.startsWith('ANCHOR_') ? '' : '/${error.field}'}',
              '墙例外锚点无效（${error.code}）');
        continue;
      }
      final c = res.chain!;
      for (final prev in spans)
        if (prev.axis == c.carrier.id &&
            prev.start < c.endPos &&
            c.startPos < prev.end)
          add(
            14,
            '/floors/$f/wallOverrides/$w',
            '墙例外区间重叠',
            related: [prev.path],
          );
      spans.add((
        axis: c.carrier.id,
        start: c.startPos,
        end: c.endPos,
        path: '/floors/$f/wallOverrides/$w',
      ));
    }
    for (var o = 0; o < floor.openings.length; o++) {
      final res = resolveAnchor(axes, floor.openings[o].anchor);
      if (!res.isSuccess)
        for (final error in res.errors)
          add(
              error.code == 'AXIS_NOT_VISIBLE'
                  ? 9
                  : error.code == 'INVALID_RESERVED_REF'
                      ? 6
                      : 10,
              '/floors/$f/openings/$o/anchor${error.code.startsWith('ANCHOR_') ? '' : '/${error.field}'}',
              '门窗锚点无效（${error.code}）');
    }
  }
  return List.unmodifiable(out);
}
