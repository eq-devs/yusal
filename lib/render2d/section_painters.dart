import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/tokens.dart';
import '../core/document/house_document.dart';

/// Construction sections drawn like the sheets of a drawing set. Each
/// painter works in its own view units (like an SVG viewBox) and is scaled
/// to the width it gets; [SectionView] keeps the aspect ratio.

class SectionView extends StatelessWidget {
  const SectionView({super.key, required this.painter});
  final SectionPainter painter;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = math.min(c.maxWidth, painter.viewW * 1.15);
        return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
                width: w,
                height: w * painter.viewH / painter.viewW,
                child: CustomPaint(painter: painter)));
      });
}

abstract class SectionPainter extends CustomPainter {
  SectionPainter(this.t);
  final Tokens t;
  double get viewW;
  double get viewH;
  void draw(Canvas canvas);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / viewW);
    draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  Paint get edge => Paint()
    ..style = PaintingStyle.stroke
    ..color = t.ink
    ..strokeWidth = 0.8;
  Paint get leader => Paint()
    ..style = PaintingStyle.stroke
    ..color = t.muted
    ..strokeWidth = 0.7;

  void text(Canvas canvas, String value, Offset at,
      {double size = 11,
      Color? color,
      bool monospace = false,
      TextAlign align = TextAlign.left,
      double angle = 0,
      bool halo = false,
      double? maxWidth}) {
    final style = monospace
        ? mono(size: size, color: color ?? t.muted)
        : TextStyle(
            fontFamily: fontBody,
            fontFamilyFallback: bodyFallback,
            fontSize: size,
            height: 1.2,
            color: color ?? t.ink);
    final tp = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxWidth == null ? 1 : 2,
        ellipsis: '…')
      ..layout(maxWidth: maxWidth ?? double.infinity);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final dx = switch (align) {
      TextAlign.right => -tp.width,
      TextAlign.center => -tp.width / 2,
      _ => 0.0
    };
    final offset = Offset(dx, -tp.height + 3);
    if (halo)
      canvas.drawRect((offset & tp.size).inflate(1.5), Paint()..color = t.panel);
    tp.paint(canvas, offset);
    canvas.restore();
  }

  void fillMaterial(Canvas canvas, Rect r, LayerMaterial m) =>
      paintMaterial(canvas, r, m, t);
}

/// Hatch for a construction material, after the drawing conventions:
/// concrete speckle, block diagonals, insulation waves, earth, sand dots.
void paintMaterial(Canvas canvas, Rect r, LayerMaterial m, Tokens t) {
  final pen = Paint()
    ..color = t.furnLine
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;
  final dot = Paint()..color = t.furnLine;
  canvas.save();
  canvas.clipRect(r);
  switch (m) {
    case LayerMaterial.conc:
      canvas.drawRect(r, Paint()..color = t.furn);
      final rnd = math.Random(7);
      for (var x = r.left; x < r.right; x += 10)
        for (var y = r.top; y < r.bottom; y += 10) {
          canvas.drawCircle(Offset(x + 2 + rnd.nextDouble() * 3, y + 3), 0.9, dot);
          canvas.drawCircle(Offset(x + 7, y + 7 + rnd.nextDouble() * 2), 0.6, dot);
          final p = Path()
            ..moveTo(x + 5, y + 1)
            ..lineTo(x + 7, y + 3)
            ..lineTo(x + 5, y + 4)
            ..close();
          canvas.drawPath(p, dot);
        }
    case LayerMaterial.block:
      canvas.drawRect(r, Paint()..color = t.panel);
      for (var d = -r.height; d < r.width; d += 8)
        canvas.drawLine(Offset(r.left + d, r.bottom),
            Offset(r.left + d + r.height, r.top), pen);
    case LayerMaterial.ins:
      canvas.drawRect(r, Paint()..color = t.roomHi);
      for (var y = r.top + 4; y < r.bottom; y += 8) {
        final p = Path()..moveTo(r.left, y);
        for (var x = r.left; x < r.right; x += 12) {
          p.quadraticBezierTo(x + 3, y - 4, x + 6, y);
          p.quadraticBezierTo(x + 9, y + 4, x + 12, y);
        }
        canvas.drawPath(p, pen);
      }
    case LayerMaterial.earth:
      canvas.drawRect(r, Paint()..color = t.panel);
      for (var d = -r.height; d < r.width; d += 10) {
        canvas.drawLine(Offset(r.left + d, r.bottom),
            Offset(r.left + d + r.height, r.top), pen);
        canvas.drawLine(Offset(r.left + d + 4, r.bottom),
            Offset(r.left + d + 4 + r.height, r.top), pen);
      }
    case LayerMaterial.sand:
      canvas.drawRect(r, Paint()..color = t.panel);
      for (var x = r.left; x < r.right; x += 6)
        for (var y = r.top; y < r.bottom; y += 6) {
          canvas.drawCircle(Offset(x + 1.5, y + 1.5), 0.6, dot);
          canvas.drawCircle(Offset(x + 4.5, y + 4.2), 0.5, dot);
        }
    case LayerMaterial.plaster:
      canvas.drawRect(r, Paint()..color = t.furn);
    case LayerMaterial.metal:
      canvas.drawRect(r, Paint()..color = t.wall);
    case LayerMaterial.wood:
      canvas.drawRect(r, Paint()..color = t.roomHi);
      for (var y = r.top + 3; y < r.bottom; y += 6)
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), pen);
    case LayerMaterial.film:
      canvas.drawRect(r, Paint()..color = t.chk);
    case LayerMaterial.gyp:
      canvas.drawRect(r, Paint()..color = t.roomHi);
  }
  canvas.restore();
}

/// Roof or floor build-up: layers top to bottom, labels with thickness.
class LayerStackPainter extends SectionPainter {
  LayerStackPainter(super.t, this.layers, this.names,
      {this.scale = 0.22, this.minH = 16});
  final List<Layer> layers;
  final List<String> names;
  final double scale, minH;
  double h(Layer l) => math.max(minH, l.thickness * scale);
  @override
  double get viewW => 360;
  @override
  double get viewH => 22 + layers.fold(0.0, (s, l) => s + h(l));
  @override
  void draw(Canvas canvas) {
    var y = 10.0;
    const bx = 14.0, bw = 110.0;
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i], hh = h(l);
      final r = Rect.fromLTWH(bx, y, bw, hh);
      fillMaterial(canvas, r, l.material);
      canvas.drawRect(r, edge);
      final ty = y + hh / 2;
      canvas.drawLine(Offset(bx + bw, ty), Offset(bx + bw + 14, ty), leader);
      text(canvas, names[i], Offset(bx + bw + 18, ty + 5),
          size: 11, maxWidth: viewW - bx - bw - 18 - 34);
      if (l.thickness > 0)
        text(canvas, '${l.thickness}', Offset(viewW - 4, ty + 5),
            monospace: true, size: 10, align: TextAlign.right);
      y += hh;
    }
  }
}

/// Wall build-up across its thickness, outside on the left.
class WallSectionPainter extends SectionPainter {
  WallSectionPainter(super.t, this.layers, this.names,
      {required this.outside, required this.inside});
  final List<Layer> layers;
  final List<String> names;
  final String outside, inside;
  static const top = 34.0, hh = 150.0, sc = 0.62;
  @override
  double get viewW => 360;
  @override
  double get viewH => top + hh + 16 + layers.length * 16 + 6;
  @override
  void draw(Canvas canvas) {
    var x = 26.0;
    final total = layers.fold(0, (s, l) => s + l.thickness);
    final scale = math.min(sc, 300 / math.max(1, total));
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i], w = math.max(6.0, l.thickness * scale);
      final r = Rect.fromLTWH(x, top, w, hh);
      fillMaterial(canvas, r, l.material);
      canvas.drawRect(r, edge);
      final lx = x + w / 2, ly = top + hh + 16 + i * 16;
      canvas.drawPath(
          Path()
            ..moveTo(lx, top + hh)
            ..lineTo(lx, ly - 4)
            ..lineTo(lx + 8, ly - 4),
          leader);
      text(canvas, '${names[i]} · ${l.thickness}', Offset(lx + 11, ly),
          size: 11, maxWidth: viewW - lx - 14);
      x += w;
    }
    text(canvas, outside, const Offset(26, 22), size: 10, color: t.muted);
    text(canvas, inside, Offset(x, 22),
        size: 10, color: t.muted, align: TextAlign.right);
    canvas.drawLine(const Offset(26, 28), Offset(x, 28), leader);
    text(canvas, '$total', Offset((26 + x) / 2, 24),
        monospace: true, size: 10, align: TextAlign.center);
  }
}

/// Strip foundation section at 0.25 px per millimetre: wall, waterproofing,
/// reinforced concrete with its cage, cushion, insulation and levels.
class FoundationSectionPainter extends SectionPainter {
  FoundationSectionPainter(super.t, this.spec, this.wall, this.labels);
  final FoundationSpec spec;
  final int wall;

  /// ground, wall, damp, topBars, floor, stirrups, concrete, bottomBars,
  /// cover, cushion, blind, xps.
  final Map<String, String> labels;
  static const k = 0.25, x0 = 170.0, y0 = 80.0;
  double get b => spec.width * k;
  double get yG => y0 + spec.plinth * k;
  double get yB => y0 + spec.height * k;
  double get yC => yB + spec.cushion * k;
  double get right => x0 + b + 120;
  @override
  double get viewW => math.max(640, right + 230);
  @override
  double get viewH => yC + 55;
  @override
  void draw(Canvas canvas) {
    final ext = spec.cushionExtra * k, cover = spec.cover * k;
    final earth = Paint()..color = t.panel;
    // Earth outside and under the floor.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, viewW, viewH));
    paintMaterial(canvas, Rect.fromLTRB(0, yG, x0 - 12.5, viewH),
        LayerMaterial.earth, t);
    paintMaterial(canvas, Rect.fromLTRB(x0 + b, y0 + 62.5, right, viewH),
        LayerMaterial.earth, t);
    canvas.restore();
    canvas.drawRect(Rect.fromLTRB(0, yG, x0 - 12.5, viewH),
        Paint()..color = earth.color.withValues(alpha: 0.45));
    // Cushion, foundation, insulation, wall.
    final cushion = Rect.fromLTRB(x0 - ext, yB, x0 + b + ext, yC);
    fillMaterial(canvas, cushion, LayerMaterial.sand);
    canvas.drawRect(cushion, edge);
    final found = Rect.fromLTRB(x0, y0, x0 + b, yB);
    fillMaterial(canvas, found, LayerMaterial.conc);
    canvas.drawRect(found, edge);
    final xps = Rect.fromLTRB(x0 - 12.5, yG - 10, x0, yB);
    fillMaterial(canvas, xps, LayerMaterial.ins);
    canvas.drawRect(xps, edge);
    final tw = math.min(b, wall * k);
    final wallRect =
        Rect.fromLTRB(x0 + (b - tw) / 2, 8, x0 + (b + tw) / 2, y0 - 1.5);
    fillMaterial(canvas, wallRect, LayerMaterial.block);
    canvas.drawRect(wallRect, edge);
    canvas.drawRect(Rect.fromLTRB(x0 - 2, y0 - 2.5, x0 + b + 2, y0 + 0.5),
        Paint()..color = t.chk);
    // Warm blind area outside, floor build-up inside.
    final blind = Path()
      ..moveTo(60, yG - 10)
      ..lineTo(x0 - 12.5, yG - 13.5)
      ..lineTo(x0 - 12.5, yG + 1)
      ..lineTo(60, yG + 1)
      ..close();
    canvas.save();
    canvas.clipPath(blind);
    paintMaterial(canvas, blind.getBounds(), LayerMaterial.conc, t);
    canvas.restore();
    canvas.drawPath(blind, edge);
    final blindIns = Rect.fromLTRB(60, yG + 1, x0 - 12.5, yG + 13.5);
    fillMaterial(canvas, blindIns, LayerMaterial.ins);
    canvas.drawRect(blindIns, edge);
    for (final (top, bottom, m) in [
      (y0, y0 + 12.5, LayerMaterial.plaster),
      (y0 + 12.5, y0 + 37.5, LayerMaterial.conc),
      (y0 + 37.5, y0 + 62.5, LayerMaterial.ins),
    ]) {
      final r = Rect.fromLTRB(x0 + b, top, right, bottom);
      fillMaterial(canvas, r, m);
      canvas.drawRect(r, edge);
    }
    // Reinforcement cage.
    final cage = Rect.fromLTRB(x0 + cover, y0 + cover, x0 + b - cover, yB - cover);
    canvas.drawRRect(
        RRect.fromRectAndRadius(cage, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = t.rebar
          ..strokeWidth = 1.6);
    List<double> xs(int n) => [
          for (var i = 0; i < n; i++)
            n == 1
                ? x0 + b / 2
                : cage.left + 2.5 + i * (cage.width - 5) / (n - 1)
        ];
    final bar = Paint()..color = t.rebar;
    final topY = cage.top + 2.5, bottomY = cage.bottom - 2.5;
    for (final x in xs(spec.topBars)) canvas.drawCircle(Offset(x, topY), 2.6, bar);
    for (final x in xs(spec.bottomBars))
      canvas.drawCircle(Offset(x, bottomY), 2.6, bar);
    // Dimensions and levels.
    void vd(double x, double a, double c, String l) {
      canvas.drawPath(
          Path()
            ..moveTo(x, a)
            ..lineTo(x, c)
            ..moveTo(x - 4, a)
            ..lineTo(x + 4, a)
            ..moveTo(x - 4, c)
            ..lineTo(x + 4, c)
            ..moveTo(x - 3, a + 3)
            ..lineTo(x + 3, a - 3)
            ..moveTo(x - 3, c + 3)
            ..lineTo(x + 3, c - 3),
          leader);
      text(canvas, l, Offset(x - 4, (a + c) / 2),
          monospace: true, size: 10, angle: -math.pi / 2, align: TextAlign.center);
    }

    void hd(double a, double c, double y, String l) {
      canvas.drawPath(
          Path()
            ..moveTo(a, y)
            ..lineTo(c, y)
            ..moveTo(a, y - 4)
            ..lineTo(a, y + 4)
            ..moveTo(c, y - 4)
            ..lineTo(c, y + 4)
            ..moveTo(a - 3, y + 3)
            ..lineTo(a + 3, y - 3)
            ..moveTo(c - 3, y + 3)
            ..lineTo(c + 3, y - 3),
          leader);
      text(canvas, l, Offset((a + c) / 2, y - 3),
          monospace: true, size: 10, align: TextAlign.center);
    }

    void level(double y, String l, double to) {
      final dash = Paint()
        ..color = t.muted
        ..strokeWidth = 0.7;
      for (var x = 58.0; x < to; x += 5)
        canvas.drawLine(Offset(x, y), Offset(math.min(to, x + 3), y), dash);
      text(canvas, l, Offset(60, y - 2), monospace: true, size: 10, halo: true);
    }

    vd(24, y0, yB, '${spec.height}');
    vd(46, y0, yG, '${spec.plinth}');
    vd(46, yG, yB, '${spec.height - spec.plinth}');
    vd(46, yB, yC, '${spec.cushion}');
    hd(x0, x0 + b, yC + 19, '${spec.width}');
    hd(x0 - ext, x0 + b + ext, yC + 39,
        '${spec.width + 2 * spec.cushionExtra}');
    String elev(int mm) =>
        mm == 0 ? '±0.000' : '−${(mm / 1000).toStringAsFixed(3)}';
    level(y0, elev(0), x0);
    level(yG, '${elev(spec.plinth)} ${labels['ground']}', x0 - 12.5);
    level(yB, elev(spec.height), x0 - ext);
    level(yC, elev(spec.height + spec.cushion), x0 - ext);
    // Leaders to the right-hand notes.
    final lx = right + 12;
    var ly = 30.0;
    void note(Offset from, String key) {
      final l = labels[key];
      if (l == null) return;
      canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..lineTo(lx - 10, ly - 4)
            ..lineTo(lx - 4, ly - 4),
          leader);
      text(canvas, l, Offset(lx, ly), size: 11, maxWidth: viewW - lx - 4);
      ly += math.max(16, (yC - 30) / 10);
    }

    note(Offset(wallRect.right, 40), 'wall');
    note(Offset(x0 + b + 1, y0 - 1), 'damp');
    note(Offset(xs(spec.topBars).last, topY), 'topBars');
    note(Offset(right - 20, y0 + 30), 'floor');
    note(Offset(cage.right, (cage.top + cage.bottom) / 2 - 20), 'stirrups');
    note(Offset(x0 + b * 0.6, (y0 + yB) / 2 + 10), 'concrete');
    note(Offset(xs(spec.bottomBars).last, bottomY), 'bottomBars');
    note(Offset(x0 + b - 2, yB - 2), 'cover');
    note(Offset(x0 + b + ext * 0.5, (yB + yC) / 2), 'cushion');
    text(canvas, labels['blind'] ?? '', Offset(60, yG - 20), size: 10.5, halo: true);
    text(canvas, labels['xps'] ?? '', Offset(60, (yG + yB) / 2 + 20),
        size: 10.5, halo: true);
  }
}
