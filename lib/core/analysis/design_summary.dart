import 'dart:math' as math;
import '../document/house_document.dart';
import '../geometry/derived_house.dart';
import 'house_analysis.dart';

/// Figures for comparing two designs side by side, after the layout
/// comparison of the drafting page.
class DesignSummary {
  const DesignSummary({
    required this.frontWidth,
    required this.buildingArea,
    required this.exteriorLength,
    required this.roomAreas,
    required this.spans,
    required this.bedroomsThroughLiving,
    required this.backRooms,
    required this.frontRooms,
  });

  /// Length of the side with the main entrance (bottom edge when none), mm.
  final double frontWidth;

  /// mm² and mm.
  final double buildingArea, exteriorLength;

  /// Clear area per room name (prefixed by the floor name on upper floors).
  final Map<String, double> roomAreas;

  /// Clear spans between load-bearing walls across the roof slab, mm.
  final List<double> spans;

  /// Bedrooms whose only way in is through a living room.
  final List<String> bedroomsThroughLiving;

  /// Rooms with an outside window on the back (opposite the entrance) and
  /// on the front.
  final List<String> backRooms, frontRooms;
}

DesignSummary summarizeDesign(HouseDocument doc, DerivedHouse derived,
    {String Function(Room room)? nameOf, String Function(Floor f)? floorName}) {
  String room(Room r) => nameOf?.call(r) ?? r.name;
  final w = doc.footprint.width.toDouble(), d = doc.footprint.depth.toDouble();
  final entrance = derived.floors.first.openings
      .where((p) => p.opening.id == doc.mainEntranceOpeningId)
      .firstOrNull;
  final front = switch (entrance?.axis.id) {
    '@top' => '@top',
    '@left' => '@left',
    '@right' => '@right',
    _ => '@bottom'
  };
  final back = const {
    '@top': '@bottom',
    '@bottom': '@top',
    '@left': '@right',
    '@right': '@left'
  }[front]!;
  final areas = <String, double>{};
  final throughLiving = <String>[];
  final backRooms = <String>{}, frontRooms = <String>{};
  for (var f = 0; f < doc.floors.length; f++) {
    final floor = doc.floors[f], g = derived.floors[f];
    String label(Room r) => f == 0 || floorName == null
        ? room(r)
        : '${floorName(floor)} · ${room(r)}';
    for (final r in floor.rooms) {
      final s = g.base.roomGeometry.firstWhere((x) => x.id == r.id);
      areas[label(r)] = (areas[label(r)] ?? 0) + s.clearArea;
    }
    // Which rooms each room opens into (doors and open, wall-less edges).
    final links = <String, Set<String>>{};
    void link(String? a, String? b) {
      if (a == null || b == null || a == b) return;
      (links[a] ??= {}).add(b);
      (links[b] ??= {}).add(a);
    }

    for (final p in g.openings.where(
        (p) => p.status == 'ok' && p.opening.kind != OpeningKind.window)) {
      final (a, b) = roomsBeside(p, g.base);
      link(a, b);
    }
    for (final e in g.base.edges.where((e) => e.kind == 'open'))
      link(e.negative == null ? null : g.base.owners[e.negative],
          e.positive == null ? null : g.base.owners[e.positive]);
    Room? byId(String id) => floor.rooms.where((r) => r.id == id).firstOrNull;
    for (final bed in floor.rooms.where((r) => r.type == RoomType.bedroom)) {
      final neighbours =
          (links[bed.id] ?? const <String>{}).map(byId).whereType<Room>();
      if (neighbours.isNotEmpty &&
          neighbours.every((r) => r.type == RoomType.living))
        throughLiving.add(label(bed));
    }
    for (final p in g.openings.where(
        (p) => p.status == 'ok' && p.opening.kind != OpeningKind.door)) {
      if (p.axis.id != back && p.axis.id != front) continue;
      final (a, b) = roomsBeside(p, g.base);
      final r = byId(a ?? b ?? '');
      if (r == null) continue;
      (p.axis.id == back ? backRooms : frontRooms).add(label(r));
    }
  }
  // Spans across the ground floor between load-bearing walls, in the
  // direction that has inner bearing walls (else across the short side).
  final walls = wallsOf(derived.floors.first.base, doc.extras.foundation)
      .where((x) => x.carriesLoad)
      .toList();
  List<double> spansAcross(bool vertical) {
    final faces = <(double, double)>[];
    for (final x in walls.where((x) => x.horizontal != vertical)) {
      final lo = vertical ? x.rect.left : x.rect.bottom,
          hi = vertical ? x.rect.right : x.rect.top;
      if (faces.any((f) => (f.$1 - lo).abs() < 300)) continue;
      faces.add((lo, hi));
    }
    faces.sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (var i = 0; i < faces.length - 1; i++) faces[i + 1].$1 - faces[i].$2
    ];
  }

  final innerVertical = walls.any((x) => !x.horizontal && x.role == WallRole.bearing),
      innerHorizontal = walls.any((x) => x.horizontal && x.role == WallRole.bearing);
  final spans = innerVertical && !innerHorizontal
      ? spansAcross(true)
      : innerHorizontal && !innerVertical
          ? spansAcross(false)
          : spansAcross(w <= d);
  return DesignSummary(
      frontWidth: front == '@top' || front == '@bottom' ? w : d,
      buildingArea: w * d,
      exteriorLength: 2 * (w + d),
      roomAreas: areas,
      spans: [for (final s in spans) math.max(0, s)],
      bedroomsThroughLiving: throughLiving,
      backRooms: backRooms.toList(),
      frontRooms: frontRooms.toList());
}
