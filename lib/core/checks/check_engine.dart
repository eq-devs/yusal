import '../document/house_document.dart';
import '../geometry/floor_base.dart';
import '../geometry/derived_house.dart';

class CheckResult {
  const CheckResult(
      this.ruleId, this.level, this.floorId, this.objectIds, this.message,
      {this.focus});
  final String ruleId, level, message;
  final String? floorId;
  final List<String> objectIds;
  final PlanRect? focus;
}

List<CheckResult> runChecks(HouseDocument doc, DerivedHouse derived) {
  final results = <CheckResult>[];
  void add(String rule, String level, String? floor, List<String> ids,
      String message) {
    PlanRect? focus;
    String? locatedFloor = floor;
    for (final g in derived.floors) {
      if (floor != null && g.base.axes.floorId != floor) continue;
      final space = [...g.base.roomGeometry, ...g.base.stairGeometryBase]
          .where((s) => ids.contains(s.id))
          .firstOrNull;
      final opening =
          g.openings.where((p) => ids.contains(p.opening.id)).firstOrNull;
      if (space != null) {
        final p = space.labelAnchor;
        focus = PlanRect(p.x, p.y, p.x, p.y);
        if (rule == 'R02' && space.collapsedCells.isNotEmpty) {
          final c = space.collapsedCells.first;
          final x = (g.base.axes.v[c.i].pos + g.base.axes.v[c.i + 1].pos) / 2;
          final y = (g.base.axes.h[c.j].pos + g.base.axes.h[c.j + 1].pos) / 2;
          focus = PlanRect(x, y, x, y);
        }
        if (rule == 'R06')
          focus = g.stairs.firstWhere((s) => s.stairId == space.id).opening;
      } else if (opening != null) {
        final u = (opening.start + opening.end) / 2,
            cross = opening.axis.pos.toDouble();
        focus = opening.axis.dir == AxisDir.H
            ? PlanRect(u, cross, u, cross)
            : PlanRect(cross, u, cross, u);
      } else if (rule == 'R09' && g.base.unassignedCells.isNotEmpty) {
        final c = g.base.unassignedCells.first;
        focus = PlanRect(
            g.base.axes.v[c.i].pos.toDouble(),
            g.base.axes.h[c.j].pos.toDouble(),
            g.base.axes.v[c.i + 1].pos.toDouble(),
            g.base.axes.h[c.j + 1].pos.toDouble());
      }
      if (focus != null) {
        locatedFloor = g.base.axes.floorId;
        break;
      }
    }
    results.add(CheckResult(
        rule, level, locatedFloor, List.unmodifiable(ids), message,
        focus: focus));
  }

  for (var f = 0; f < doc.floors.length; f++) {
    final floor = doc.floors[f], g = derived.floors[f];
    bool touches(OpeningPlacement p, String id) => g.base.edges.any((e) =>
        e.axis.id == p.axis.id &&
        e.start.pos < p.end &&
        p.start < e.end.pos &&
        (g.base.owners[e.negative] == id || g.base.owners[e.positive] == id));
    for (final room in floor.rooms) {
      final geometry = g.base.roomGeometry.firstWhere((r) => r.id == room.id),
          min = room.type == RoomType.bedroom
              ? 2700
              : room.type == RoomType.living
                  ? 3300
                  : 0;
      if (geometry.minClearSpan < min)
        add('R01', 'suggestion', floor.id, [room.id],
            '${room.name}最窄处净宽  ${(geometry.minClearSpan / 1000).toStringAsFixed(2)} 米，建议不小于 ${(min / 1000).toStringAsFixed(2)} 米。');
      if (geometry.clearArea == 0 || geometry.hasCollapsedCell)
        add('R02', 'important', floor.id, [room.id],
            '${room.name}这里的墙已经占满了可用空间，净宽为 0。可以加宽这一格，或调整墙厚。');
      final area = room.type == RoomType.bedroom
          ? 8.0
          : room.type == RoomType.bathroom
              ? 2.5
              : 0.0;
      if (geometry.clearArea / 1e6 < area)
        add('R03', 'suggestion', floor.id, [room.id],
            '${room.name}净面积  ${(geometry.clearArea / 1e6).toStringAsFixed(1)} ㎡，建议至少 $area ㎡。');
      final access = g.openings.any((p) =>
              p.status == 'ok' &&
              p.opening.kind != OpeningKind.window &&
              touches(p, room.id)) ||
          g.base.edges.any((e) =>
              e.kind == 'open' &&
              (g.base.owners[e.negative] == room.id ||
                  g.base.owners[e.positive] == room.id));
      if (!access)
        add('R04', 'suggestion', floor.id, [room.id],
            '${room.name}还没有门，进不去。可以在墙上加一扇门，或把一段墙设为开放。');
      if (room.type == RoomType.bedroom &&
          !g.openings.any((p) =>
              p.status == 'ok' &&
              p.host?.kind == 'exterior' &&
              p.opening.kind != OpeningKind.door &&
              touches(p, room.id)))
        add('R05', 'suggestion', floor.id, [room.id],
            '${room.name}没有窗，采光和通风会很差。可以在外墙上加一扇窗。');
    }
    for (final stair in g.stairs) {
      final geometry =
          g.base.stairGeometryBase.firstWhere((s) => s.id == stair.stairId);
      if (geometry.clearArea == 0 || geometry.hasCollapsedCell)
        add('R02', 'important', floor.id, [stair.stairId], '楼梯有空间被墙占满。');
      if (!stair.fits)
        add('R06', 'important', floor.id, [stair.stairId],
            '楼梯放不下，至少需要 ${(stair.requiredA / 1000).toStringAsFixed(2)} × ${(stair.requiredB / 1000).toStringAsFixed(2)} 米净空间。');
    }
    for (final opening in g.openings)
      if (opening.status != 'ok')
        add(
            'R07',
            'important',
            floor.id,
            [opening.opening.id],
            switch (opening.status) {
                  'tooLong' => '门窗超出了墙段的长度或跨过了墙的交接点。',
                  'onOpen' => '门窗放在了开放段上。',
                  'noWall' => '门窗所在位置没有墙。',
                  _ => '门窗高度超过了本层净高。'
                } +
                '可以删除它，或移到其他墙上。');
    if (g.base.unassignedCells.isNotEmpty)
      add('R09', 'suggestion', floor.id, [],
          '${floor.name}还有 ${(g.base.unassignedNominalArea / 1e6).toStringAsFixed(1)} ㎡ 没有划分成房间。');
    final ok = g.openings.where((p) => p.status == 'ok').toList();
    for (var i = 0; i < ok.length; i++)
      for (var j = i + 1; j < ok.length; j++) {
        final a = ok[i], b = ok[j];
        if (a.host?.ref == b.host?.ref &&
            a.start < b.end &&
            b.start < a.end &&
            a.opening.sill < b.opening.sill + b.opening.height &&
            b.opening.sill < a.opening.sill + a.opening.height)
          add('R10', 'important', floor.id, [a.opening.id, b.opening.id],
              '这两扇门窗在墙上重叠了，可以挪开其中一扇。');
      }
  }
  final entrance = derived.floors
      .expand((f) => f.openings)
      .where((p) => p.opening.id == doc.mainEntranceOpeningId)
      .firstOrNull;
  if (entrance == null) {
    add('R08', 'suggestion', null, [], '还没有指定主入口，可以在首层外墙的门上设置。');
  } else if (!derived.floors.first.openings.contains(entrance) ||
      entrance.status != 'ok' ||
      entrance.host?.kind != 'exterior') {
    add('R08', 'suggestion', null, [entrance.opening.id], '主入口需要是首层外墙上的有效门。');
  }
  final order = {for (var i = 0; i < results.length; i++) results[i]: i};
  results.sort((a, b) {
    final c = a.ruleId.compareTo(b.ruleId);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return List.unmodifiable(results);
}
