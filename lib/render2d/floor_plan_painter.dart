import 'package:flutter/material.dart';
import '../core/document/house_document.dart';
import '../core/geometry/floor_base.dart';
import '../core/axis/axis_resolver.dart';
import '../core/geometry/derived_house.dart';
import 'dart:math' as math;

const roomColors = {
  RoomType.living: Color(0xffe6cba4),
  RoomType.bedroom: Color(0xffb6cbb7),
  RoomType.kitchen: Color(0xfff2d499),
  RoomType.bathroom: Color(0xffaacae0),
  RoomType.dining: Color(0xffdbc3c7),
  RoomType.custom: Color(0xffc9c6dc)
};

class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter(this.base, this.labels, this.colors,
      {this.preview = const [],
      this.openings = const [],
      this.stairs = const [],
      this.focus,
      this.northAngleDeg = 0});
  final FloorBase base;
  final PlanRect? focus;
  final int northAngleDeg;
  final Map<String, String> labels;
  final Map<String, Color> colors;
  final List<Cell> preview;
  final List<OpeningPlacement> openings;
  final List<StairGeometry> stairs;
  double scale(Size size) => math
      .min((size.width - 96) / base.axes.v.last.pos,
          (size.height - 96) / base.axes.h.last.pos)
      .clamp(0.001, 0.4);
  Offset origin(Size size) => Offset(
      (size.width - base.axes.v.last.pos * scale(size)) / 2,
      (size.height + base.axes.h.last.pos * scale(size)) / 2);
  Offset point(double x, double y, Size size) =>
      origin(size) + Offset(x * scale(size), -y * scale(size));
  ({double x, double y}) worldPoint(Offset point, Size size) {
    final offset = point - origin(size), factor = scale(size);
    return (x: offset.dx / factor, y: -offset.dy / factor);
  }

  Rect rectangle(PlanRect r, Size size) => Rect.fromPoints(
      point(r.left, r.top, size), point(r.right, r.bottom, size));
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final angle = northAngleDeg * math.pi / 180;
    final center = Offset(size.width - 25, 30);
    final vector = Offset(math.sin(angle), -math.cos(angle));
    paint
      ..color = const Color(0xff404a40)
      ..strokeWidth = 2;
    canvas.drawLine(center - vector * 8, center + vector * 12, paint);
    final tip = center + vector * 12;
    final normal = Offset(-vector.dy, vector.dx);
    canvas.drawLine(tip, tip - vector * 5 + normal * 4, paint);
    canvas.drawLine(tip, tip - vector * 5 - normal * 4, paint);
    final northLabel = TextPainter(
        text: const TextSpan(
            text: '北',
            style: TextStyle(color: Color(0xff404a40), fontSize: 11)),
        textDirection: TextDirection.ltr)
      ..layout();
    northLabel.paint(canvas, Offset(size.width - 31, 48));
    for (final entry in base.owners.entries) {
      final c = entry.key;
      final r = PlanRect(
          base.axes.v[c.i].pos.toDouble(),
          base.axes.h[c.j].pos.toDouble(),
          base.axes.v[c.i + 1].pos.toDouble(),
          base.axes.h[c.j + 1].pos.toDouble());
      paint.color = colors[entry.value] ?? const Color(0xffeceeea);
      canvas.drawRect(rectangle(r, size), paint);
      paint
        ..color = const Color(0xffd1d5cd)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawRect(rectangle(r, size), paint);
      paint.style = PaintingStyle.fill;
    }
    for (var i = 0; i < base.wallRects.length; i++) {
      paint.color = base.wallSegments[i].kind == 'temporary'
          ? const Color(0xffb9beb6)
          : const Color(0xff404a40);
      canvas.drawRect(rectangle(base.wallRects[i], size), paint);
    }
    for (final placement in openings) {
      final horizontal = placement.axis.dir == AxisDir.H;
      final axis = placement.axis.pos.toDouble();
      Offset at(double u, double cross) =>
          horizontal ? point(u, cross, size) : point(cross, u, size);
      final start = at(placement.start, axis), end = at(placement.end, axis);
      if (placement.status != 'ok') {
        canvas.drawLine(
            start,
            end,
            Paint()
              ..color = Colors.red
              ..strokeWidth = 4);
        continue;
      }
      final wallIndex =
          base.wallSegments.indexWhere((s) => s.ref == placement.host!.ref);
      final wall = base.wallRects[wallIndex];
      final cut = horizontal
          ? PlanRect(placement.start, wall.bottom, placement.end, wall.top)
          : PlanRect(wall.left, placement.start, wall.right, placement.end);
      canvas.drawRect(
          rectangle(cut, size), Paint()..color = const Color(0xfff6f7f3));
      final opening = placement.opening;
      if (opening is DoorOpening) {
        final hinge = opening.hinge == Hinge.start ? start : end;
        final sign = opening.opensTo == OpeningSide.positiveSide ? 1.0 : -1.0;
        final span = (placement.end - placement.start) * scale(size);
        final leaf = horizontal
            ? hinge + Offset(0, -sign * span)
            : hinge + Offset(sign * span, 0);
        final p = Paint()
          ..color = const Color(0xff917350)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(hinge, leaf, p);
        final angle0 = horizontal
            ? (opening.hinge == Hinge.start ? 0.0 : math.pi)
            : (opening.hinge == Hinge.start ? -math.pi / 2 : math.pi / 2);
        final angle1 = horizontal
            ? (sign > 0 ? -math.pi / 2 : math.pi / 2)
            : (sign > 0 ? 0.0 : math.pi);
        var sweep = angle1 - angle0;
        while (sweep > math.pi) sweep -= 2 * math.pi;
        while (sweep < -math.pi) sweep += 2 * math.pi;
        canvas.drawArc(Rect.fromCircle(center: hinge, radius: span), angle0,
            sweep, false, p);
      } else {
        canvas.drawLine(
            start,
            end,
            Paint()
              ..color = const Color(0xff5c9eb8)
              ..strokeWidth = 3);
      }
    }
    for (final stair in stairs) {
      for (final step in [...stair.steps, ...stair.landings]) {
        canvas.drawRect(
            rectangle(step.rect, size),
            Paint()
              ..color = const Color(0xff9ca69a)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
    void text(String value, Offset at, {double font = 13}) {
      final t = TextPainter(
          text: TextSpan(
              text: value,
              style: TextStyle(
                  color: const Color(0xff384437),
                  fontSize: font,
                  fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center)
        ..layout();
      t.paint(canvas, at - Offset(t.width / 2, t.height / 2));
    }

    for (final room in base.roomGeometry) {
      text(
          '${labels[room.id] ?? ''}\n${(room.clearArea / 1000000).toStringAsFixed(1)} ㎡',
          point(room.labelAnchor.x, room.labelAnchor.y, size));
    }
    for (var i = 0; i < base.axes.nx; i++) {
      final a = base.axes.v[i], b = base.axes.v[i + 1];
      text('${((b.pos - a.pos) / 1000).toStringAsFixed(2)} m',
          point((a.pos + b.pos) / 2, -450, size),
          font: 11);
    }
    text('${(base.axes.h.last.pos / 1000).toStringAsFixed(2)} m',
        Offset(origin(size).dx - 25, size.height / 2),
        font: 11);
    if (focus != null) {
      paint
        ..style = PaintingStyle.stroke
        ..color = Colors.redAccent
        ..strokeWidth = 3;
      final rect = rectangle(focus!, size);
      if (rect.width == 0 && rect.height == 0)
        canvas.drawCircle(rect.center, 18, paint);
      else
        canvas.drawRect(rect.inflate(4), paint);
      paint.style = PaintingStyle.fill;
    }
    for (final c in preview) {
      paint.color = const Color(0xff70886c).withValues(alpha: 0.35);
      canvas.drawRect(
          Rect.fromPoints(
              point(base.axes.v[c.i].pos.toDouble(),
                  base.axes.h[c.j + 1].pos.toDouble(), size),
              point(base.axes.v[c.i + 1].pos.toDouble(),
                  base.axes.h[c.j].pos.toDouble(), size)),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) => true;
}
