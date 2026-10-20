import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/settings.dart';
import '../app/tokens.dart';
import '../core/analysis/site_analysis.dart';
import '../core/document/house_document.dart';
import '../core/geometry/floor_base.dart';
import 'planning_names.dart';

/// Plot millimetres to canvas pixels: the plot fits the canvas with room
/// for dimensions; y grows up the drawing (the street is at the bottom).
class SiteView {
  SiteView(this.site, this.size, {this.margin = 44});
  final SitePlan site;
  final Size size;
  final double margin;
  double get scale => math.max(
      0.0001,
      math.min((size.width - 2 * margin) / site.width,
          (size.height - 2 * margin - 18) / site.depth));
  Offset get origin => Offset(
      (size.width - site.width * scale) / 2,
      (size.height + site.depth * scale) / 2 - 9);
  Offset point(double x, double y) =>
      origin + Offset(x * scale, -y * scale);
  Offset world(Offset p) =>
      Offset((p.dx - origin.dx) / scale, -(p.dy - origin.dy) / scale);
  Rect rect(PlanRect r) =>
      Rect.fromPoints(point(r.left, r.top), point(r.right, r.bottom));
}

class SitePlanPainter extends CustomPainter {
  SitePlanPainter(
      {required this.doc,
      required this.site,
      required this.tokens,
      this.selected,
      this.highlights = const [],
      this.pulse})
      : super(repaint: pulse);
  final HouseDocument doc;

  /// The plot as shown, with any item or the house being dragged.
  final SitePlan site;
  final Tokens tokens;

  /// Selected item id, or '@house'.
  final String? selected;
  final List<PlanRect> highlights;
  final Animation<double>? pulse;

  void _text(Canvas canvas, String value, Offset at,
      {double font = 11,
      Color? color,
      FontWeight weight = FontWeight.w500,
      bool mono_ = false,
      double angle = 0,
      double? maxWidth}) {
    final style = mono_
        ? mono(size: font, color: color ?? tokens.ink, weight: weight)
        : TextStyle(
            fontFamily: fontBody,
            fontFamilyFallback: bodyFallback,
            fontSize: font,
            color: color ?? tokens.ink,
            fontWeight: weight);
    final p = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxWidth == null ? null : 2,
        ellipsis: maxWidth == null ? null : '…',
        textAlign: TextAlign.center)
      ..layout(maxWidth: maxWidth ?? double.infinity);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
    canvas.restore();
  }

  String _m(double mm) => dec((mm / 1000).toStringAsFixed(1));

  double _textWidth(String value, double font) => (TextPainter(
          text: TextSpan(
              text: value,
              style: TextStyle(
                  fontFamily: fontBody,
                  fontFamilyFallback: bodyFallback,
                  fontSize: font,
                  fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr)
        ..layout())
      .width;

  void _dim(Canvas canvas, Offset a, Offset b, String text, {bool vertical = false}) {
    final paint = Paint()
      ..color = tokens.dim
      ..strokeWidth = 1;
    canvas.drawLine(a, b, paint);
    final tick = vertical ? const Offset(4, 0) : const Offset(0, 4);
    for (final p in [a, b]) canvas.drawLine(p - tick, p + tick, paint);
    if ((b - a).distance < 22) return;
    final mid = (a + b) / 2;
    final box = Rect.fromCenter(center: mid, width: text.length * 6.6 + 8, height: 14);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()..color = tokens.panel);
    _text(canvas, text, mid, font: 10, color: tokens.dim, mono_: true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = tokens;
    final v = SiteView(site, size);
    final plot = v.rect(PlanRect(0, 0, site.width.toDouble(), site.depth.toDouble()));
    canvas.drawRect(plot, Paint()..color = Tokens.mix(t.ok, 0.07, t.panel));
    // Street along the bottom.
    final street = Rect.fromLTRB(plot.left - 30, plot.bottom + 4, plot.right + 30, plot.bottom + 22);
    canvas.drawRect(street, Paint()..color = Tokens.mix(t.line, 0.6, t.panel));
    _text(canvas, tr('街道', 'Көше'), street.center, font: 10, color: t.muted);

    // Areas first, then buildings, so outbuildings sit on the yard.
    final items = [...site.items]..sort((a, b) =>
        (siteBuildings.contains(a.kind) ? 1 : 0)
            .compareTo(siteBuildings.contains(b.kind) ? 1 : 0));
    for (final item in items) {
      if (item.kind == SiteKind.gate) continue;
      final r = v.rect(itemRect(item));
      final fill = switch (item.kind) {
        SiteKind.garden => Tokens.mix(t.ok, 0.28, t.panel),
        SiteKind.yard => Tokens.mix(t.line, 0.55, t.panel),
        SiteKind.well || SiteKind.septic => Tokens.mix(t.chk, 0.25, t.panel),
        SiteKind.greenhouse => Tokens.mix(t.chk, 0.12, t.panel),
        _ => t.furn,
      };
      canvas.drawRect(r, Paint()..color = fill);
      canvas.drawRect(
          r,
          Paint()
            ..color = siteBuildings.contains(item.kind) ? t.wall : t.furnLine
            ..style = PaintingStyle.stroke
            ..strokeWidth = siteBuildings.contains(item.kind) ? 1.6 : 1);
      if (item.kind == SiteKind.garden) {
        final rows = Paint()
          ..color = Tokens.mix(t.ok, 0.6, t.panel)
          ..strokeWidth = 1;
        for (var y = r.top + 6; y < r.bottom - 2; y += 7)
          canvas.drawLine(Offset(r.left + 3, y), Offset(r.right - 3, y), rows);
      }
      if (item.kind == SiteKind.well) {
        canvas.drawCircle(r.center, math.min(r.width, r.height) / 2 - 1,
            Paint()
              ..color = t.chk
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
      final name = item.label ?? siteName(item.kind);
      final fits = _textWidth(name, 10.5) <= r.width - 6 && r.height > 14;
      if (fits)
        _text(canvas, name, r.center, font: 10.5, weight: FontWeight.w600);
      else
        // Small pieces (well, toilet) get their name beside them.
        _text(canvas, name, Offset(r.right + 4 + _textWidth(name, 10) / 2, r.center.dy),
            font: 10, color: t.dim);
    }

    // Fence with gaps at the gates.
    final gates = site.items.where((i) => i.kind == SiteKind.gate).toList();
    final fence = Paint()
      ..color = t.wall
      ..strokeWidth = site.fence ? 2.2 : 1
      ..style = PaintingStyle.stroke;
    if (!site.fence) fence.color = t.furnLine;
    final corners = [
      (0.0, 0.0),
      (site.width.toDouble(), 0.0),
      (site.width.toDouble(), site.depth.toDouble()),
      (0.0, site.depth.toDouble())
    ];
    for (var k = 0; k < 4; k++) {
      final a = corners[k], b = corners[(k + 1) % 4];
      final horizontal = a.$2 == b.$2;
      final cuts = <(double, double)>[];
      for (final g in gates) {
        final r = itemRect(g);
        final across = horizontal ? a.$2 : a.$1;
        final near = horizontal
            ? (r.bottom - 600 <= across && r.top + 600 >= across)
            : (r.left - 600 <= across && r.right + 600 >= across);
        if (near)
          cuts.add(horizontal ? (r.left, r.right) : (r.bottom, r.top));
      }
      final lo = horizontal ? math.min(a.$1, b.$1) : math.min(a.$2, b.$2),
          hi = horizontal ? math.max(a.$1, b.$1) : math.max(a.$2, b.$2);
      cuts.sort((x, y) => x.$1.compareTo(y.$1));
      var from = lo;
      for (final (c0, c1) in [...cuts, (hi, hi)]) {
        final to = c0.clamp(lo, hi);
        if (to > from) {
          final p0 = horizontal ? v.point(from, a.$2) : v.point(a.$1, from),
              p1 = horizontal ? v.point(to, a.$2) : v.point(a.$1, to);
          canvas.drawLine(p0, p1, fence);
        }
        from = math.max(from, c1.clamp(lo, hi));
      }
    }
    for (final g in gates) {
      final r = v.rect(itemRect(g));
      canvas.drawRect(
          r,
          Paint()
            ..color = t.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
      _text(canvas, g.label ?? siteName(g.kind), r.center + const Offset(0, -12),
          font: 10, color: t.muted);
    }

    // The house: its ground-floor outline, roof overhang dashed.
    final house = houseOnPlot(doc, site);
    final hr = v.rect(house);
    final ground = deriveFloorBase(doc, doc.floors.first.id);
    final shape = Path();
    for (final r in ground.outside.isEmpty
        ? [PlanRect(0, 0, doc.footprint.width.toDouble(), doc.footprint.depth.toDouble())]
        : insideRects(ground))
      shape.addRect(v.rect(PlanRect(r.left + site.houseX, r.bottom + site.houseY,
          r.right + site.houseX, r.top + site.houseY)));
    canvas.drawPath(shape, Paint()..color = t.room);
    for (final w in ground.wallRects.asMap().entries
        .where((e) => ground.wallSegments[e.key].kind == 'exterior'))
      canvas.drawRect(
          v.rect(PlanRect(w.value.left + site.houseX, w.value.bottom + site.houseY,
              w.value.right + site.houseX, w.value.top + site.houseY)),
          Paint()..color = t.wall);
    if (doc.roof.pitched) {
      final o = doc.roof.overhang!.toDouble();
      final roof = v.rect(PlanRect(house.left - o, house.bottom - o,
          house.right + o, house.top + o));
      final dash = Paint()
        ..color = t.muted
        ..strokeWidth = 1;
      for (final (a, b) in [
        (roof.topLeft, roof.topRight),
        (roof.topRight, roof.bottomRight),
        (roof.bottomRight, roof.bottomLeft),
        (roof.bottomLeft, roof.topLeft)
      ]) {
        final length = (b - a).distance, unit = (b - a) / length;
        for (var d = 0.0; d < length; d += 8)
          canvas.drawLine(a + unit * d, a + unit * math.min(length, d + 4), dash);
      }
    }
    _text(canvas, doc.meta.name, hr.center + const Offset(0, -7),
        font: 12, weight: FontWeight.w700, maxWidth: math.max(30, hr.width - 6));
    _text(
        canvas,
        '${_m(house.right - house.left)} × ${_m(house.top - house.bottom)} ${tr('米', 'м')}',
        hr.center + const Offset(0, 9),
        font: 10,
        color: t.muted,
        mono_: true);

    // Distances from the house to the plot edges.
    final midY = (house.bottom + house.top) / 2, midX = (house.left + house.right) / 2;
    _dim(canvas, v.point(0, midY), v.point(house.left, midY), _m(house.left));
    _dim(canvas, v.point(house.right, midY), v.point(site.width.toDouble(), midY),
        _m(site.width - house.right));
    _dim(canvas, v.point(midX, 0), v.point(midX, house.bottom), _m(house.bottom),
        vertical: true);
    _dim(canvas, v.point(midX, house.top), v.point(midX, site.depth.toDouble()),
        _m(site.depth - house.top),
        vertical: true);
    // Plot size along the top and the left.
    _text(canvas, '${_m(site.width.toDouble())} ${tr('米', 'м')}',
        Offset(plot.center.dx, plot.top - 12),
        font: 11, color: t.dim, mono_: true);
    _text(canvas, '${_m(site.depth.toDouble())} ${tr('米', 'м')}',
        Offset(plot.left - 14, plot.center.dy),
        font: 11, color: t.dim, mono_: true, angle: -math.pi / 2);

    // Selection and flashing issue areas.
    final selectedRect = selected == '@house'
        ? hr
        : site.items
            .where((i) => i.id == selected)
            .map((i) => v.rect(itemRect(i)))
            .firstOrNull;
    if (selectedRect != null)
      canvas.drawRect(
          selectedRect.inflate(3),
          Paint()
            ..color = t.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    final beat = pulse?.value ?? 0;
    for (final h in highlights)
      canvas.drawRect(
          v.rect(h).inflate(4),
          Paint()
            ..color = t.crit.withValues(alpha: 0.25 + 0.5 * beat)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);

    // North arrow at the top right.
    final angle = doc.footprint.northAngleDeg * math.pi / 180;
    final c = Offset(size.width - 28, 46);
    final dir = Offset(math.sin(angle), -math.cos(angle));
    final path = Path()
      ..moveTo(c.dx + dir.dx * 14, c.dy + dir.dy * 14)
      ..lineTo(c.dx - dir.dx * 10 + dir.dy * 6, c.dy - dir.dy * 10 - dir.dx * 6)
      ..lineTo(c.dx - dir.dx * 5, c.dy - dir.dy * 5)
      ..lineTo(c.dx - dir.dx * 10 - dir.dy * 6, c.dy - dir.dy * 10 + dir.dx * 6)
      ..close();
    canvas.drawPath(path, Paint()..color = t.ink);
    _text(canvas, tr('北', 'С'), c + dir * 24, font: 11, weight: FontWeight.w700);
  }

  @override
  bool shouldRepaint(covariant SitePlanPainter old) => true;
}
