import 'package:flutter/material.dart';
import '../app/settings.dart';
import '../app/tokens.dart';
import '../core/analysis/house_analysis.dart';
import '../core/document/house_document.dart';
import '../core/geometry/floor_base.dart';
import '../core/axis/axis_resolver.dart';
import '../core/geometry/derived_house.dart';
import 'furniture_names.dart';
import 'dart:math' as math;

/// Kept for previews and older callers; the drafting plan fills every room
/// with the sheet colour and marks the selected one.
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
      this.draft,
      this.draftIsLine = false,
      this.draftInvalid = false,
      this.showGridDimensions = false,
      this.resizeHandles = false,
      this.wallHandle,
      this.wallSeed,
      this.wallAttachments = const [],
      this.handleScale = 1,
      this.editableWall,
      this.draftLabel,
      this.draftConnected = false,
      this.draftEnd,
      this.coach,
      this.viewport,
      this.viewportInsets = EdgeInsets.zero,
      this.northAngleDeg = 0,
      this.tokens = Tokens.light,
      this.bearingMin = 240,
      this.furniture = const [],
      this.selectedFurniture,
      this.selectedRoom,
      this.showFurniture = true,
      this.showDimensions = true,
      this.foundation,
      this.sleeves = const [],
      this.highlights = const [],
      this.pulse,
      this.measure = const [],
      this.furnitureDraft,
      this.showLabels = true})
      : super(repaint: pulse);
  final FloorBase base;
  final PlanRect? focus, draft, wallHandle, editableWall;
  final Offset? wallSeed, draftEnd;
  final bool draftConnected;

  /// First-use guide: a dashed arrow from a wall attachment into the house.
  final (Offset, Offset)? coach;
  final List<Offset> wallAttachments;
  final double handleScale;
  final String? draftLabel;
  final bool draftIsLine, draftInvalid, resizeHandles, showGridDimensions;
  final ({double scale, Offset origin})? viewport;
  final EdgeInsets viewportInsets;
  final int northAngleDeg;
  final Map<String, String> labels;
  final Map<String, Color> colors;
  final List<Cell> preview;
  final List<OpeningPlacement> openings;
  final List<StairGeometry> stairs;

  final Tokens tokens;

  /// Inner walls at least this thick are drawn hatched as load-bearing.
  final int bearingMin;
  final List<FurnitureItem> furniture;
  final String? selectedFurniture, selectedRoom;
  final bool showFurniture, showDimensions;

  /// Foundation strips to overlay; null hides the layer.
  final FoundationTakeoff? foundation;
  final List<Sleeve> sleeves;

  /// Plan areas to flash (issue locations), with [pulse] 0–1 for the beat.
  final List<PlanRect> highlights;
  final Animation<double>? pulse;

  /// Measuring tape: zero, one or two plan points.
  final List<Offset> measure;

  /// Furniture being placed or dragged, drawn on top.
  final FurnitureItem? furnitureDraft;

  /// Room names, furniture names and the north arrow; off for thumbnails.
  final bool showLabels;

  double scale(Size size) =>
      viewport?.scale ??
      math
          .min(
              (size.width -
                      viewportInsets.horizontal -
                      (viewportInsets == EdgeInsets.zero ? 96 : 48)) /
                  base.axes.v.last.pos,
              (size.height -
                      viewportInsets.vertical -
                      (viewportInsets == EdgeInsets.zero ? 96 : 48)) /
                  base.axes.h.last.pos)
          .clamp(0.001, 0.4);
  Offset origin(Size size) =>
      viewport?.origin ??
      Offset(
          viewportInsets.left +
              (size.width -
                      viewportInsets.horizontal -
                      base.axes.v.last.pos * scale(size)) /
                  2,
          viewportInsets.top +
              (size.height -
                      viewportInsets.vertical +
                      base.axes.h.last.pos * scale(size)) /
                  2);
  Offset point(double x, double y, Size size) =>
      origin(size) + Offset(x * scale(size), -y * scale(size));
  ({double x, double y}) worldPoint(Offset point, Size size) {
    final offset = point - origin(size), factor = scale(size);
    return (x: offset.dx / factor, y: -offset.dy / factor);
  }

  Rect rectangle(PlanRect r, Size size) => Rect.fromPoints(
      point(r.left, r.top, size), point(r.right, r.bottom, size));

  /// Screen pixels at the current zoom, for strokes and text that keep
  /// their on-screen size.
  double px(double value) => value / handleScale;

  void dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 5, double gap = 4}) {
    final length = (b - a).distance;
    if (length == 0) return;
    final unit = (b - a) / length;
    for (var d = 0.0; d < length; d += px(dash + gap))
      canvas.drawLine(a + unit * d,
          a + unit * math.min(length, d + px(dash)), paint);
  }

  void dashedRect(Canvas canvas, Rect r, Paint paint,
      {double dash = 5, double gap = 4}) {
    dashedLine(canvas, r.topLeft, r.topRight, paint, dash: dash, gap: gap);
    dashedLine(canvas, r.topRight, r.bottomRight, paint, dash: dash, gap: gap);
    dashedLine(canvas, r.bottomRight, r.bottomLeft, paint,
        dash: dash, gap: gap);
    dashedLine(canvas, r.bottomLeft, r.topLeft, paint, dash: dash, gap: gap);
  }

  void label(Canvas canvas, String value, Offset at,
      {double font = 13,
      Color? color,
      FontWeight weight = FontWeight.w600,
      double? maxWidth,
      double angle = 0,
      int? maxLines,
      bool monospace = false,
      Color? halo}) {
    final style = monospace
        ? mono(size: px(font), weight: weight, color: color ?? tokens.ink)
        : TextStyle(
            fontFamily: fontBody,
            fontFamilyFallback: bodyFallback,
            color: color ?? tokens.ink,
            fontSize: px(font),
            height: 1.25,
            fontWeight: weight);
    final t = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxWidth == null ? null : maxLines ?? 3,
        ellipsis: maxWidth == null ? null : '…',
        textAlign: TextAlign.center)
      ..layout(maxWidth: maxWidth ?? double.infinity);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    if (halo != null) {
      final box = Rect.fromCenter(
          center: Offset.zero,
          width: t.width + px(6),
          height: t.height + px(2));
      canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(px(3))),
          Paint()..color = halo);
    }
    t.paint(canvas, Offset(-t.width / 2, -t.height / 2));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = tokens;
    final paint = Paint();
    final width = base.axes.v.last.pos.toDouble(),
        depth = base.axes.h.last.pos.toDouble();
    final s = scale(size);

    // Site pieces (terrace, porch) sit under the house.
    if (showFurniture)
      for (final f in furniture.where((f) =>
          f.kind == FurnitureKind.terrace || f.kind == FurnitureKind.porch))
        drawFurniture(canvas, size, f);

    // One path per space so adjacent cells do not show anti-aliased seams.
    final fills = <String?, Path>{};
    for (final entry in base.owners.entries) {
      final c = entry.key;
      final r = PlanRect(
          base.axes.v[c.i].pos.toDouble(),
          base.axes.h[c.j].pos.toDouble(),
          base.axes.v[c.i + 1].pos.toDouble(),
          base.axes.h[c.j + 1].pos.toDouble());
      (fills[entry.value] ??= Path()).addRect(rectangle(r, size));
    }
    for (final entry in fills.entries) {
      paint.color = entry.key != null && entry.key == selectedRoom
          ? t.roomHi
          : colors[entry.key] ??
              (entry.key == null ? Tokens.mix(t.line, 0.35, t.panel) : t.room);
      canvas.drawPath(entry.value, paint);
    }
    if (showGridDimensions)
      for (final entry in base.owners.entries) {
        final c = entry.key;
        final r = PlanRect(
            base.axes.v[c.i].pos.toDouble(),
            base.axes.h[c.j].pos.toDouble(),
            base.axes.v[c.i + 1].pos.toDouble(),
            base.axes.h[c.j + 1].pos.toDouble());
        canvas.drawRect(
            rectangle(r, size),
            Paint()
              ..color = t.line
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8);
      }

    if (showFurniture) {
      final flat = furniture
          .where((f) =>
              f.kind != FurnitureKind.terrace && f.kind != FurnitureKind.porch)
          .toList()
        ..sort((a, b) => (isFlatFurniture(a.kind) ? 0 : 1)
            .compareTo(isFlatFurniture(b.kind) ? 0 : 1));
      for (final f in flat) drawFurniture(canvas, size, f);
    }

    // Walls in plan cut: load-bearing hatched, partitions solid.
    final walls = wallsOf(base, FoundationSpec(bearingMin: bearingMin));
    final hatched = Path(), solid = Path(), temporary = Path();
    for (final w in walls) {
      final r = rectangle(w.rect, size);
      switch (w.role) {
        case WallRole.exterior || WallRole.bearing:
          hatched.addRect(r);
        case WallRole.partition:
          solid.addRect(r);
        case WallRole.temporary:
          temporary.addRect(r);
      }
    }
    canvas.drawPath(temporary, Paint()..color = Tokens.mix(t.wall, 0.3, t.panel));
    canvas.drawPath(solid, Paint()..color = t.wall);
    canvas.drawPath(hatched, Paint()..color = t.wall);
    canvas.save();
    canvas.clipPath(hatched);
    final bounds = hatched.getBounds(), hatch = Paint()
      ..color = t.bg
      ..strokeWidth = math.max(0.6, px(1.1));
    final step = px(6);
    for (var d = -bounds.height; d < bounds.width; d += step)
      canvas.drawLine(Offset(bounds.left + d, bounds.bottom),
          Offset(bounds.left + d + bounds.height, bounds.top), hatch);
    canvas.restore();

    // Open (wall-less) edges between rooms: dashed arch lines.
    final arch = Paint()
      ..color = t.accent
      ..strokeWidth = px(1.5);
    for (final e in base.edges.where((e) => e.kind == 'open')) {
      final a = e.axis.dir == AxisDir.H
              ? point(e.start.pos.toDouble(), e.axis.pos.toDouble(), size)
              : point(e.axis.pos.toDouble(), e.start.pos.toDouble(), size),
          b = e.axis.dir == AxisDir.H
              ? point(e.end.pos.toDouble(), e.axis.pos.toDouble(), size)
              : point(e.axis.pos.toDouble(), e.end.pos.toDouble(), size);
      dashedLine(canvas, a, b, arch, dash: 6, gap: 4);
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
              ..color = t.crit
              ..strokeWidth = px(4));
        continue;
      }
      final wallIndex =
          base.wallSegments.indexWhere((s) => s.ref == placement.host!.ref);
      final wall = base.wallRects[wallIndex];
      final cutRect = horizontal
          ? PlanRect(placement.start, wall.bottom, placement.end, wall.top)
          : PlanRect(wall.left, placement.start, wall.right, placement.end);
      final cut = rectangle(cutRect, size);
      final opening = placement.opening;
      if (opening is DoorOpening) {
        canvas.drawRect(cut, Paint()..color = t.room);
        final hinge = opening.hinge == Hinge.start ? start : end;
        final sign = opening.opensTo == OpeningSide.positiveSide ? 1.0 : -1.0;
        final span = (placement.end - placement.start) * s;
        final leaf = horizontal
            ? hinge + Offset(0, -sign * span)
            : hinge + Offset(sign * span, 0);
        canvas.drawLine(
            hinge,
            leaf,
            Paint()
              ..color = t.ink
              ..strokeWidth = px(1.8));
        final angle0 = horizontal
            ? (opening.hinge == Hinge.start ? 0.0 : math.pi)
            : (opening.hinge == Hinge.start ? -math.pi / 2 : math.pi / 2);
        final angle1 = horizontal
            ? (sign > 0 ? -math.pi / 2 : math.pi / 2)
            : (sign > 0 ? 0.0 : math.pi);
        var sweep = angle1 - angle0;
        while (sweep > math.pi) sweep -= 2 * math.pi;
        while (sweep < -math.pi) sweep += 2 * math.pi;
        // Dashed swing arc.
        final arc = Paint()
          ..color = t.muted
          ..style = PaintingStyle.stroke
          ..strokeWidth = px(1);
        const pieces = 14;
        for (var k = 0; k < pieces; k += 2)
          canvas.drawArc(Rect.fromCircle(center: hinge, radius: span),
              angle0 + sweep * k / pieces, sweep / pieces, false, arc);
      } else {
        canvas.drawRect(cut, Paint()..color = t.panel);
        canvas.drawRect(
            cut,
            Paint()
              ..color = t.wall
              ..style = PaintingStyle.stroke
              ..strokeWidth = px(0.8));
        final glass = Paint()
          ..color = t.chk
          ..strokeWidth = px(1.2);
        final normal = horizontal ? Offset(0, px(2.2)) : Offset(px(2.2), 0);
        canvas.drawLine(start - normal, end - normal, glass);
        canvas.drawLine(start + normal, end + normal, glass);
        if (opening is SlidingOpening) {
          final mid = (start + end) / 2,
              along = (end - start) / (end - start).distance;
          final leafPaint = Paint()
            ..color = t.ink
            ..strokeWidth = px(1.8);
          canvas.drawLine(start - normal * 1.4,
              mid + along * px(4) - normal * 1.4, leafPaint);
          canvas.drawLine(mid - along * px(4) + normal * 1.4,
              end + normal * 1.4, leafPaint);
        }
      }
    }
    for (final stair in stairs) {
      for (final step in [...stair.steps, ...stair.landings]) {
        canvas.drawRect(
            rectangle(step.rect, size),
            Paint()
              ..color = t.furnLine
              ..style = PaintingStyle.stroke
              ..strokeWidth = px(1));
      }
    }

    if (foundation != null) {
      for (final strip in foundation!.strips) {
        final r = rectangle(strip.rect, size);
        final color = strip.exists ? t.ok : t.crit;
        if (!strip.exists)
          canvas.drawRect(
              r, Paint()..color = color.withValues(alpha: 0.22));
        dashedRect(
            canvas,
            r,
            Paint()
              ..color = color
              ..strokeWidth = px(1.6),
            dash: 6,
            gap: 4);
      }
      for (final sl in sleeves) {
        final c = point(sl.x.toDouble(), sl.y.toDouble(), size);
        canvas.drawCircle(c, math.max(px(4), sl.diameter / 2 * s * 1.6),
            Paint()..color = t.chk);
        canvas.drawCircle(
            c,
            math.max(px(4), sl.diameter / 2 * s * 1.6),
            Paint()
              ..color = t.panel
              ..style = PaintingStyle.stroke
              ..strokeWidth = px(1));
        label(canvas, '${sleeveName(sl.kind)} Ø${sl.diameter}',
            c + Offset(0, px(14)),
            font: 10, color: t.chk, monospace: true, halo: t.panel);
      }
    }

    for (final room in showLabels ? base.roomGeometry : <SpaceGeometry>[]) {
      final largest = room.clearRects.isEmpty
          ? null
          : room.clearRects.reduce((a, b) => a.area >= b.area ? a : b);
      final available = largest == null ? 80.0 : (largest.right - largest.left) * s;
      // Fit the label to the room as seen on screen: drop the dimensions,
      // then the area, then the name, rather than spill over walls.
      final screenWidth = available * handleScale,
          screenHeight = largest == null
              ? 60.0
              : (largest.top - largest.bottom) * s * handleScale;
      if (screenWidth < 28 || screenHeight < 18) continue;
      final name = labels[room.id] ?? '';
      final showArea = screenHeight >= 36 && screenWidth >= 44;
      final showSize = room.clearRects.length == 1 &&
          screenWidth >= 110 &&
          screenHeight >= 64;
      final area = '${dec((room.clearArea / 1e6).toStringAsFixed(1))} $unitM2';
      final net = largest == null
          ? ''
          : '${tr('净', 'таза')} ${m2dp(largest.right - largest.left)} × ${m2dp(largest.top - largest.bottom)} $unitM';
      // Long names shrink to one line before they would break mid-word.
      final room_ = math.max(px(24), available - px(8));
      final nameWidth = textWidth(name, px(14), FontWeight.w700);
      final nameFont =
          nameWidth <= room_ ? 14.0 : math.max(10.0, 14 * room_ / nameWidth);
      final tall = largest == null ? 0.0 : (largest.top - largest.bottom) * s;
      if (textWidth(name, px(10), FontWeight.w700) > room_ &&
          tall > textWidth(name, px(12), FontWeight.w700) + px(12)) {
        // Too narrow for the name (a corridor): run it along the room.
        label(canvas, name, point(room.labelAnchor.x, room.labelAnchor.y, size),
            font: 12, weight: FontWeight.w700, angle: -math.pi / 2);
        continue;
      }
      final lineGap = px(9);
      final lines = 1 + (showArea ? 1 : 0) + (showSize ? 1 : 0);
      final boxWidth = math.min(
              room_,
              [
                textWidth(name, px(nameFont), FontWeight.w700),
                if (showArea) textWidth(area, px(12), FontWeight.w400, monospace: true),
                if (showSize) textWidth(net, px(11), FontWeight.w400),
              ].reduce(math.max)) +
          px(6);
      final anchor =
          labelSpot(room, largest, size, Size(boxWidth, lineGap * 2 * lines));
      var y = anchor.dy - lineGap * (lines - 1);
      label(canvas, name, Offset(anchor.dx, y),
          font: nameFont,
          weight: FontWeight.w700,
          maxWidth: room_,
          maxLines: 2);
      if (showArea) {
        y += lineGap * 2;
        label(canvas, area, Offset(anchor.dx, y),
            font: 12, color: t.muted, weight: FontWeight.w400, monospace: true);
      }
      if (showSize) {
        y += lineGap * 2;
        label(canvas, net, Offset(anchor.dx, y),
            font: 11, color: t.muted, weight: FontWeight.w400);
      }
    }

    if (showGridDimensions) {
      final grid = Paint()
        ..color = t.chk.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      for (final axis in base.axes.all.where((a) => a.kind != 'boundary')) {
        final first = axis.dir == AxisDir.V
            ? point(axis.pos.toDouble(), 0, size)
            : point(0, axis.pos.toDouble(), size);
        final last = axis.dir == AxisDir.V
            ? point(axis.pos.toDouble(), depth, size)
            : point(width, axis.pos.toDouble(), size);
        canvas.drawLine(first, last, grid);
      }
      for (var i = 0; i < base.axes.nx; i++) {
        final a = base.axes.v[i], b = base.axes.v[i + 1];
        label(canvas, '${m2dp(b.pos - a.pos)} $unitM',
            point((a.pos + b.pos) / 2, 0, size) + Offset(0, px(30)),
            font: 11, color: t.dim, monospace: true);
      }
    } else if (showDimensions) {
      drawDimensions(canvas, size, walls, width, depth);
    }

    // North arrow beside the top-right corner.
    if (showLabels) drawNorth(canvas, size, width, depth);
    drawOverlays(canvas, size, width, depth);
  }

  void drawNorth(Canvas canvas, Size size, double width, double depth) {
    final t = tokens;
    final angle = northAngleDeg * math.pi / 180;
    final center = point(width, depth, size) + Offset(px(30), -px(30));
    final vector = Offset(math.sin(angle), -math.cos(angle));
    final normal = Offset(-vector.dy, vector.dx);
    final arrow = Path()
      ..moveTo(center.dx + vector.dx * px(11), center.dy + vector.dy * px(11))
      ..lineTo(center.dx - vector.dx * px(7) + normal.dx * px(5),
          center.dy - vector.dy * px(7) + normal.dy * px(5))
      ..lineTo(center.dx - vector.dx * px(3), center.dy - vector.dy * px(3))
      ..lineTo(center.dx - vector.dx * px(7) - normal.dx * px(5),
          center.dy - vector.dy * px(7) - normal.dy * px(5))
      ..close();
    canvas.drawPath(arrow, Paint()..color = t.wall);
    label(canvas, tr('北', 'С'), center + vector * px(20),
        font: 11, weight: FontWeight.w700);
  }

  void drawOverlays(Canvas canvas, Size size, double width, double depth) {
    final t = tokens;

    if (wallHandle != null) {
      final rect = rectangle(wallHandle!, size);
      canvas.drawLine(
          rect.topLeft,
          rect.bottomRight,
          Paint()
            ..color = t.accent
            ..strokeWidth = 4);
      canvas.drawCircle(rect.center, 13, Paint()..color = t.accent);
      final cross = Paint()
        ..color = t.accentInk
        ..strokeWidth = 2;
      canvas.drawLine(
          rect.center - const Offset(6, 0), rect.center + const Offset(6, 0), cross);
      canvas.drawLine(
          rect.center - const Offset(0, 6), rect.center + const Offset(0, 6), cross);
    }
    if (resizeHandles) {
      // Round grips with two-way arrows: drag right edge for width, top
      // edge for length.
      final right = point(width, depth / 2, size),
          top = point(width / 2, depth, size);
      for (final (center, horizontal) in [(right, true), (top, false)]) {
        final r = px(16);
        canvas.drawCircle(center, r + px(2), Paint()..color = t.panel);
        canvas.drawCircle(center, r, Paint()..color = t.accent);
        final pen = Paint()
          ..color = t.accentInk
          ..strokeWidth = px(2)
          ..strokeCap = StrokeCap.round;
        final axis = horizontal ? const Offset(1, 0) : const Offset(0, 1),
            normal = Offset(axis.dy, axis.dx);
        final reach = px(8), head = px(4);
        canvas.drawLine(center - axis * reach, center + axis * reach, pen);
        for (final sign in [-1.0, 1.0]) {
          final tip = center + axis * reach * sign;
          canvas.drawLine(tip, tip - axis * head * sign + normal * head, pen);
          canvas.drawLine(tip, tip - axis * head * sign - normal * head, pen);
        }
      }
    }
    void pill(String value, Offset at, Color color) {
      final tp = TextPainter(
          text: TextSpan(
              text: value,
              style: TextStyle(
                  fontFamily: fontBody,
                  fontFamilyFallback: bodyFallback,
                  color: color,
                  fontSize: px(14),
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      final box = Rect.fromCenter(
          center: at, width: tp.width + px(16), height: tp.height + px(8));
      final shape = RRect.fromRectAndRadius(box, Radius.circular(px(10)));
      canvas.drawRRect(shape, Paint()..color = t.panel.withValues(alpha: 0.94));
      canvas.drawRRect(
          shape,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(1.2));
      tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
    }

    if (coach != null) {
      final a = point(coach!.$1.dx, coach!.$1.dy, size),
          b = point(coach!.$2.dx, coach!.$2.dy, size);
      final guide = Paint()
        ..color = t.accent.withValues(alpha: 0.8)
        ..strokeWidth = px(3)
        ..strokeCap = StrokeCap.round;
      final length = (b - a).distance, unit = (b - a) / length;
      final dash = px(10);
      for (var d = px(24); d < length - dash; d += dash * 2)
        canvas.drawLine(a + unit * d, a + unit * (d + dash), guide);
      final n = Offset(-unit.dy, unit.dx) * px(8);
      canvas.drawLine(b, b - unit * px(12) + n, guide);
      canvas.drawLine(b, b - unit * px(12) - n, guide);
    }
    if (draft != null) {
      final rect = rectangle(draft!, size);
      final tone = draftInvalid ? t.crit : t.accent;
      canvas.drawRect(rect, Paint()..color = tone.withValues(alpha: 0.15));
      canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = tone
            ..strokeWidth = 3);
      if (draftIsLine && draftLabel != null) {
        // Beside the middle of the line: never under the start handle or
        // the finger at the free end.
        final vertical = rect.width < rect.height;
        pill(draftLabel!,
            rect.center + (vertical ? Offset(-px(34), 0) : Offset(0, -px(24))),
            tone);
      } else {
        label(
            canvas,
            draftLabel ??
                (draftIsLine
                    ? tr('松手分房', 'Жіберсеңіз бөлінеді')
                    : '${dec(((draft!.right - draft!.left) / 1000).toStringAsFixed(1))} × '
                        '${dec(((draft!.top - draft!.bottom) / 1000).toStringAsFixed(1))} $unitM'),
            Offset(rect.center.dx, rect.top - 18),
            font: 13,
            color: tone);
      }
    }
    if (draftEnd != null) {
      final end = point(draftEnd!.dx, draftEnd!.dy, size);
      final tone = draftInvalid ? t.crit : t.ok;
      if (draftConnected && !draftInvalid) {
        canvas.drawCircle(
            end,
            px(13),
            Paint()
              ..color = tone
              ..style = PaintingStyle.stroke
              ..strokeWidth = px(3));
        canvas.drawCircle(end, px(6), Paint()..color = tone);
      } else {
        canvas.drawCircle(end, px(7), Paint()..color = t.panel);
        canvas.drawCircle(
            end,
            px(7),
            Paint()
              ..color = tone
              ..style = PaintingStyle.stroke
              ..strokeWidth = px(2));
      }
    }
    if (editableWall != null) {
      final a = point(editableWall!.left, editableWall!.bottom, size),
          b = point(editableWall!.right, editableWall!.top, size);
      final color = draftInvalid ? t.crit : t.accent;
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = color.withValues(alpha: 0.45)
            ..strokeWidth = px(10)
            ..strokeCap = StrokeCap.round);
      final grips = wallGrips(a, b, zoom: handleScale);
      for (final p in [grips.start, grips.end]) {
        if (p != a && p != b)
          canvas.drawLine(
              (p - a).distance < (p - b).distance ? a : b,
              p,
              Paint()
                ..color = color.withValues(alpha: 0.6)
                ..strokeWidth = px(2));
      }
      for (final p in [
        grips.start,
        grips.end,
        if (grips.middle != null) grips.middle!
      ]) {
        canvas.drawCircle(p, px(12), Paint()..color = t.panel);
        canvas.drawCircle(p, px(9), Paint()..color = color);
      }
      if (draftLabel != null && draft == null)
        pill(
            draftLabel!,
            (a + b) / 2 +
                ((a - b).dx.abs() < (a - b).dy.abs()
                    ? Offset(-px(38), 0)
                    : Offset(0, -px(26))),
            color);
    }
    for (final attachment in wallAttachments) {
      final center = point(attachment.dx, attachment.dy, size);
      final radius = px(13);
      canvas.drawCircle(center, radius + px(2), Paint()..color = t.panel);
      canvas.drawCircle(center, radius, Paint()..color = t.accent);
      final pen = Paint()
        ..color = t.accentInk
        ..strokeWidth = px(2);
      final span = px(5);
      canvas.drawLine(center - Offset(span, 0), center + Offset(span, 0), pen);
      canvas.drawLine(center - Offset(0, span), center + Offset(0, span), pen);
    }
    if (wallSeed != null) {
      final center = point(wallSeed!.dx, wallSeed!.dy, size);
      canvas.drawCircle(center, px(23), Paint()..color = t.panel);
      canvas.drawCircle(center, px(21), Paint()..color = t.accent);
      final plus = Paint()
        ..color = t.accentInk
        ..strokeWidth = px(2.5)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center - Offset(px(8), 0), center + Offset(px(8), 0), plus);
      canvas.drawLine(center - Offset(0, px(8)), center + Offset(0, px(8)), plus);
    }
    if (furnitureDraft != null) drawFurniture(canvas, size, furnitureDraft!,
        ghost: true);
    for (final h in highlights) {
      final r = rectangle(h, size);
      final glow = 0.55 + 0.45 * (1 - (pulse?.value ?? 0));
      canvas.drawRect(
          r, Paint()..color = t.accent.withValues(alpha: 0.28 * glow));
      canvas.drawRect(
          r,
          Paint()
            ..color = t.accent.withValues(alpha: glow)
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(3));
    }
    if (focus != null) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..color = t.crit
        ..strokeWidth = px(3);
      final rect = rectangle(focus!, size);
      if (rect.width == 0 && rect.height == 0)
        canvas.drawCircle(rect.center, px(18), stroke);
      else
        canvas.drawRect(rect.inflate(px(4)), stroke);
    }
    for (final c in preview) {
      canvas.drawRect(
          Rect.fromPoints(
              point(base.axes.v[c.i].pos.toDouble(),
                  base.axes.h[c.j + 1].pos.toDouble(), size),
              point(base.axes.v[c.i + 1].pos.toDouble(),
                  base.axes.h[c.j].pos.toDouble(), size)),
          Paint()..color = t.accent.withValues(alpha: 0.3));
    }
    if (measure.isNotEmpty) {
      final a = point(measure.first.dx, measure.first.dy, size);
      final dot = Paint()..color = t.crit;
      canvas.drawCircle(a, px(4), dot);
      if (measure.length > 1) {
        final b = point(measure[1].dx, measure[1].dy, size);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..color = t.crit
              ..strokeWidth = px(2));
        canvas.drawCircle(b, px(4), dot);
        final mm = (measure[1] - measure[0]).distance.round();
        label(canvas, '$mm $unitMm', (a + b) / 2 - Offset(0, px(12)),
            font: 13, color: t.crit, monospace: true, halo: t.panel);
      }
    }
  }

  double textWidth(String text, double fontSize, FontWeight weight,
      {bool monospace = false}) {
    final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: monospace
                ? mono(size: fontSize, weight: weight)
                : TextStyle(
                    fontFamily: fontBody,
                    fontFamilyFallback: bodyFallback,
                    fontSize: fontSize,
                    fontWeight: weight)),
        textDirection: TextDirection.ltr)
      ..layout();
    return tp.width;
  }

  /// Rugs big enough to carry their name along the lower edge (like the
  /// drafting page, above 12 m²).
  static bool captionedRug(FurnitureItem f) =>
      f.kind == FurnitureKind.rug && f.width * f.depth > 12e6;

  /// Where a room's label of [box] size goes: inside its largest clear
  /// rectangle, clear of raised furniture and rug captions, preferring the
  /// middle.
  Offset labelSpot(SpaceGeometry room, PlanRect? largest, Size size, Size box) {
    final centre = point(room.labelAnchor.x, room.labelAnchor.y, size);
    if (largest == null || !showFurniture) return centre;
    final obstacles = <Rect>[];
    for (final f in furniture) {
      if (f.right <= largest.left ||
          f.x >= largest.right ||
          f.top <= largest.bottom ||
          f.y >= largest.top ||
          f.kind == FurnitureKind.wallRug ||
          f.kind == FurnitureKind.alasha) continue;
      final r = rectangle(
          PlanRect(f.x.toDouble(), f.y.toDouble(), f.right.toDouble(),
              f.top.toDouble()),
          size);
      if (f.kind == FurnitureKind.rug) {
        if (captionedRug(f))
          obstacles.add(Rect.fromLTRB(r.left, r.bottom - px(20), r.right, r.bottom));
        continue;
      }
      obstacles.add(r);
    }
    if (obstacles.isEmpty) return centre;
    final bounds = rectangle(largest, size).deflate(px(3));
    final halfW = math.min(box.width / 2, bounds.width / 2),
        halfH = math.min(box.height / 2, bounds.height / 2);
    final inner = Rect.fromLTRB(bounds.left + halfW, bounds.top + halfH,
        bounds.right - halfW, bounds.bottom - halfH);
    if (inner.width < 0 || inner.height < 0) return centre;
    var best = centre, bestScore = -double.infinity;
    const steps = 10;
    for (var i = 0; i <= steps; i++)
      for (var j = 0; j <= steps; j++) {
        final p = Offset(inner.left + inner.width * i / steps,
            inner.top + inner.height * j / steps);
        final label = Rect.fromCenter(
            center: p, width: halfW * 2, height: halfH * 2);
        var overlap = 0.0, clearance = double.infinity;
        for (final r in obstacles) {
          final o = label.intersect(r);
          if (o.width > 0 && o.height > 0) overlap += o.width * o.height;
          final dx = math.max(0.0, math.max(r.left - label.right, label.left - r.right)),
              dy = math.max(0.0, math.max(r.top - label.bottom, label.top - r.bottom));
          clearance = math.min(clearance, math.sqrt(dx * dx + dy * dy));
        }
        final score = -overlap * 4 / (handleScale * handleScale) +
            math.min(clearance, px(14)) * 2 -
            (p - centre).distance * 0.15;
        if (score > bestScore) {
          bestScore = score;
          best = p;
        }
      }
    return best;
  }

  /// Chains of wall-face dimensions on four sides plus the overall sizes,
  /// in millimetres, like a construction drawing.
  void drawDimensions(Canvas canvas, Size size, List<WallInfo> walls,
      double width, double depth) {
    final t = tokens, pen = Paint()
      ..color = t.dim
      ..strokeWidth = math.max(0.6, px(0.9));
    const eps = 1.0;
    List<double> faces(bool vertical, bool Function(PlanRect) touches,
        double extent) {
      final out = <double>{0, extent};
      for (final w in walls.where((w) =>
          w.role != WallRole.temporary &&
          (vertical ? !w.horizontal : w.horizontal) &&
          touches(w.rect))) {
        if (vertical) {
          out.addAll([w.rect.left, w.rect.right]);
        } else {
          out.addAll([w.rect.bottom, w.rect.top]);
        }
      }
      return out.where((v) => v >= -eps && v <= extent + eps).toList()..sort();
    }

    void chain(List<double> stops, bool horizontal, double offset, {
      required bool before,
    }) {
      // [offset] in screen pixels from the outer face.
      for (var i = 0; i < stops.length - 1; i++) {
        final a = stops[i], b = stops[i + 1];
        if (b - a < 1) continue;
        final p0 = horizontal
                ? point(a, before ? depth : 0, size)
                : point(before ? 0 : width, a, size),
            p1 = horizontal
                ? point(b, before ? depth : 0, size)
                : point(before ? 0 : width, b, size);
        final shift = horizontal
            ? Offset(0, before ? -px(offset) : px(offset))
            : Offset(before ? -px(offset) : px(offset), 0);
        final q0 = p0 + shift, q1 = p1 + shift;
        canvas.drawLine(q0, q1, pen);
        final tick = px(4);
        for (final q in [q0, q1]) {
          canvas.drawLine(q + Offset(-tick, tick), q + Offset(tick, -tick), pen);
          canvas.drawLine(
              horizontal ? q + Offset(0, -tick * 1.4) : q + Offset(-tick * 1.4, 0),
              horizontal ? q + Offset(0, tick * 1.4) : q + Offset(tick * 1.4, 0),
              pen);
        }
        final lengthPx = (q1 - q0).distance;
        final text = '${(b - a).round()}';
        if (lengthPx < px(text.length * 6.0 + 4)) continue;
        final mid = (q0 + q1) / 2;
        label(
            canvas,
            text,
            horizontal
                ? mid + Offset(0, -px(7))
                : mid + Offset(-px(7), 0),
            font: 10,
            color: t.dim,
            weight: FontWeight.w400,
            monospace: true,
            halo: t.panel.withValues(alpha: 0.85),
            angle: horizontal ? 0 : -math.pi / 2);
      }
    }

    final top = faces(true, (r) => r.top >= depth - 600, width),
        bottom = faces(true, (r) => r.bottom <= 600, width),
        left = faces(false, (r) => r.left <= 600, depth),
        right = faces(false, (r) => r.right >= width - 600, depth);
    chain(top, true, 22, before: true);
    chain([0, width], true, 42, before: true);
    chain(bottom, true, 26, before: false);
    chain(left, false, 22, before: true);
    chain([0, depth], false, 42, before: true);
    chain(right, false, 22, before: false);
  }

  void drawFurniture(Canvas canvas, Size size, FurnitureItem f,
      {bool ghost = false}) {
    final t = tokens;
    final r = rectangle(
        PlanRect(f.x.toDouble(), f.y.toDouble(), f.right.toDouble(),
            f.top.toDouble()),
        size);
    final selected = f.id == selectedFurniture;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = selected || ghost ? t.accent : t.furnLine
      ..strokeWidth = px(selected ? 2 : 1);
    final fill = Paint();
    final kz = Tokens.mix(t.rug, 0.30, t.furn);
    double alpha(double a) => ghost ? a * 0.6 : a;
    switch (f.kind) {
      case FurnitureKind.terrace || FurnitureKind.porch:
        fill.color = t.furn.withValues(alpha: alpha(0.45));
        canvas.drawRect(r, fill);
        final planks = Paint()
          ..color = t.furnLine.withValues(alpha: 0.5)
          ..strokeWidth = px(0.8);
        final vertical = r.height > r.width;
        for (var d = px(12); d < (vertical ? r.width : r.height); d += px(12))
          vertical
              ? canvas.drawLine(Offset(r.left + d, r.top),
                  Offset(r.left + d, r.bottom), planks)
              : canvas.drawLine(Offset(r.left, r.top + d),
                  Offset(r.right, r.top + d), planks);
        if (selected || ghost) canvas.drawRect(r, stroke);
      case FurnitureKind.rug:
        fill.color = Tokens.mix(t.rug, 0.16, t.room).withValues(alpha: alpha(1));
        canvas.drawRect(r, fill);
        canvas.drawRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = selected ? t.accent : t.rug
              ..strokeWidth = px(selected ? 2 : 1.4));
        final inner = r.deflate(math.min(px(7), r.shortestSide / 6));
        dashedRect(
            canvas,
            inner,
            Paint()
              ..color = t.rug
              ..strokeWidth = px(0.9),
            dash: 4,
            gap: 3);
        final d = r.shortestSide * 0.22, c = r.center;
        canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - d)
              ..lineTo(c.dx + d, c.dy)
              ..lineTo(c.dx, c.dy + d)
              ..lineTo(c.dx - d, c.dy)
              ..close(),
            Paint()
              ..style = PaintingStyle.stroke
              ..color = t.rug
              ..strokeWidth = px(0.9));
      case FurnitureKind.alasha:
        fill.color = Tokens.mix(t.rug, 0.16, t.room).withValues(alpha: alpha(1));
        canvas.drawRect(r, fill);
        dashedRect(
            canvas,
            r,
            Paint()
              ..color = selected ? t.accent : t.rug
              ..strokeWidth = px(1.2),
            dash: 4,
            gap: 3);
      case FurnitureKind.wallRug:
        canvas.drawRect(
            r.width < r.height
                ? Rect.fromLTRB(r.left - px(1.5), r.top, r.right + px(1.5), r.bottom)
                : Rect.fromLTRB(r.left, r.top - px(1.5), r.right, r.bottom + px(1.5)),
            Paint()..color = t.rug.withValues(alpha: alpha(1)));
        if (selected) canvas.drawRect(r.inflate(px(3)), stroke);
      case FurnitureKind.dastarkhan:
        fill.color = t.furn.withValues(alpha: alpha(1));
        canvas.drawOval(r, fill);
        canvas.drawOval(r, stroke);
      case FurnitureKind.korpe ||
            FurnitureKind.cushion ||
            FurnitureKind.sandyq:
        fill.color = kz.withValues(alpha: alpha(1));
        canvas.drawRect(r, fill);
        canvas.drawRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = selected ? t.accent : t.rug
              ..strokeWidth = px(selected ? 2 : 1));
      default:
        fill.color = t.furn.withValues(alpha: alpha(1));
        canvas.drawRect(r, fill);
        canvas.drawRect(r, stroke);
        final detail = Paint()
          ..style = PaintingStyle.stroke
          ..color = t.furnLine
          ..strokeWidth = px(0.8);
        switch (f.kind) {
          case FurnitureKind.bed || FurnitureKind.singleBed:
            // Pillows at the end nearest the longer edge's wall: right side.
            final long = r.width >= r.height;
            final pillow = long
                ? Rect.fromLTWH(r.right - r.width * 0.16, r.top + r.height * 0.1,
                    r.width * 0.12, r.height * 0.8)
                : Rect.fromLTWH(r.left + r.width * 0.1, r.top + r.height * 0.04,
                    r.width * 0.8, r.height * 0.12);
            canvas.drawRRect(
                RRect.fromRectAndRadius(pillow, Radius.circular(px(3))), detail);
            canvas.drawLine(
                long
                    ? Offset(r.right - r.width * 0.2, r.top)
                    : Offset(r.left, r.top + r.height * 0.2),
                long
                    ? Offset(r.right - r.width * 0.2, r.bottom)
                    : Offset(r.right, r.top + r.height * 0.2),
                detail);
          case FurnitureKind.bathtub:
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    r.deflate(r.shortestSide * 0.12),
                    Radius.circular(r.shortestSide * 0.3)),
                detail);
          case FurnitureKind.toilet:
            canvas.drawOval(
                Rect.fromCenter(
                    center: r.center + Offset(0, r.height * 0.1),
                    width: r.width * 0.75,
                    height: r.height * 0.6),
                detail);
          case FurnitureKind.basin || FurnitureKind.sink:
            canvas.drawOval(r.deflate(r.shortestSide * 0.18), detail);
          case FurnitureKind.stove:
            for (final dx in [0.3, 0.7])
              for (final dy in [0.3, 0.7])
                canvas.drawCircle(
                    Offset(r.left + r.width * dx, r.top + r.height * dy),
                    r.shortestSide * 0.13,
                    detail);
          case FurnitureKind.wardrobe ||
                FurnitureKind.pantry ||
                FurnitureKind.shelf ||
                FurnitureKind.shoeCabinet:
            canvas.drawLine(r.topLeft, r.bottomRight, detail);
          case FurnitureKind.shower:
            canvas.drawLine(r.topLeft, r.bottomRight, detail);
            canvas.drawLine(r.topRight, r.bottomLeft, detail);
          default:
        }
    }
    final name = f.label ?? furnitureName(f.kind);
    final w = r.width, h = r.height;
    if (!showLabels) {
      // Previews draw shapes only.
    } else if (f.kind == FurnitureKind.rug) {
      // Rug names sit along the lower edge, clear of what stands on them.
      if (captionedRug(f) && w > px(name.length * 7.0 + 16) && h > px(40))
        label(canvas, name, Offset(r.center.dx, r.bottom - px(11)),
            font: 10.5, color: t.rug, weight: FontWeight.w600);
    } else if (f.kind == FurnitureKind.terrace ||
        f.kind == FurnitureKind.porch) {
      // Outside the house: name on the far edge, away from the dimensions.
      final depth = base.axes.h.last.pos;
      final y = f.y >= depth
          ? r.top + px(10)
          : f.top <= 0
              ? r.bottom - px(10)
              : r.center.dy;
      if (w > px(name.length * 6.0))
        label(canvas, name, Offset(r.center.dx, y),
            font: 10, color: t.muted, weight: FontWeight.w400);
    } else if (f.kind != FurnitureKind.wallRug &&
        f.kind != FurnitureKind.cushion &&
        (w > px(36) || h > px(60))) {
      final vertical = h > w * 1.6;
      final room = vertical ? h : w;
      if (room > px(name.length * 7.0)) {
        label(canvas, name, r.center,
            font: 9.5,
            color: t.muted,
            weight: FontWeight.w400,
            angle: vertical ? -math.pi / 2 : 0,
            maxWidth: (vertical ? h : w) - px(4),
            maxLines: 1);
      }
    }
    if (selected && !ghost) {
      // Corner grip for resizing and a round grip for turning.
      final grip = Paint()..color = t.accent;
      canvas.drawCircle(r.bottomRight, px(7), Paint()..color = t.panel);
      canvas.drawCircle(r.bottomRight, px(5.5), grip);
      final turn = Offset(r.center.dx, r.top - px(18));
      canvas.drawLine(
          Offset(r.center.dx, r.top),
          turn,
          Paint()
            ..color = t.accent
            ..strokeWidth = px(1.5));
      canvas.drawCircle(turn, px(7), Paint()..color = t.panel);
      canvas.drawCircle(
          turn,
          px(6),
          Paint()
            ..color = t.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(2));
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) => true;
}

/// Screen grips for editing one wall from [a] to [b] (canvas-local pixels).
/// Short walls get their end grips pushed apart and lose the middle grip so
/// each grip keeps a finger-sized target; the wall body still moves the wall.
({Offset start, Offset end, Offset? middle}) wallGrips(Offset a, Offset b,
    {required double zoom, double minimumGap = 44}) {
  final length = (b - a).distance * zoom;
  if (length >= minimumGap * 2) return (start: a, end: b, middle: (a + b) / 2);
  final direction =
      length == 0 ? const Offset(1, 0) : (b - a) / (b - a).distance;
  final center = (a + b) / 2, half = minimumGap / zoom;
  return (
    start: center - direction * half,
    end: center + direction * half,
    middle: null
  );
}
