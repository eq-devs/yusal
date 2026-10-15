import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// Kazakh textiles drawn procedurally for the 3D views, after the drafting
/// page: кілем (rug), тұскиіз (wall hanging), құрақ көрпе (patchwork),
/// сандық (chest) and алаша (striped runner). The main motif is the
/// қошқар мүйіз (ram's horn).
enum Textile { kilem, tus, kurak, sandyq, alasha }

final _cache = <(Textile, int), ui.Image>{};

/// The texture for [textile] in colour [variant] (0–2), made once.
ui.Image textileImage(Textile textile, int variant) =>
    _cache[(textile, variant % 3)] ??= _draw(textile, variant % 3);

Color _c(int argb) => Color(argb);

ui.Image _draw(Textile textile, int v) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final (w, h) = switch (textile) {
    Textile.kilem => (512, 512),
    Textile.tus => (512, 340),
    Textile.kurak => (256, 256),
    Textile.sandyq => (512, 256),
    Textile.alasha => (256, 256),
  };
  switch (textile) {
    case Textile.kilem:
      const sets = [
        (0xff8E1C1C, 0xff1D2A48, 0xffE9D9B4, 0xffB5452A),
        (0xff6E1630, 0xff2C1A12, 0xffE2C27A, 0xff9C3B2A),
        (0xff1F3B5A, 0xff7A1B1B, 0xffEBD8AE, 0xff2F5C70),
      ];
      final (base, border, orn, acc) = sets[v];
      _kilem(canvas, _c(base), _c(border), _c(orn), _c(acc));
    case Textile.tus:
      const sets = [
        (0xff2B0E16, [0xffD8A23A, 0xffC23B32, 0xff3E8A5E]),
        (0xff14233A, [0xffE0B04E, 0xffD2553A, 0xffE8DCC4]),
        (0xff3B1A10, [0xffD8A23A, 0xffE8DCC4, 0xff3E8A5E]),
      ];
      final (base, cols) = sets[v];
      _tus(canvas, _c(base), [for (final c in cols) _c(c)]);
    case Textile.kurak:
      const sets = [
        [0xffB0302A, 0xffE3B341, 0xff2E6A8E, 0xff3F7D4F, 0xffE8DCC4],
        [0xff7A2338, 0xffD8A23A, 0xff1F4E6E, 0xffC9573A],
        [0xff2E6A8E, 0xffE8DCC4, 0xffB0302A, 0xff5E8A3A, 0xffD8A23A],
      ];
      _kurak(canvas, [for (final c in sets[v]) _c(c)]);
    case Textile.sandyq:
      const sets = [
        (0xff7A1E1E, 0xffD9B45A),
        (0xff1F5E63, 0xffD9B45A),
        (0xff5E3A1E, 0xffD9B45A),
      ];
      final (base, metal) = sets[v];
      _sandyq(canvas, _c(base), _c(metal));
    case Textile.alasha:
      _alasha(canvas);
  }
  return recorder.endRecording().toImageSync(w, h);
}

void _horn(Canvas x, double cx, double cy, double s, Color col, double lw) {
  final pen = Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = lw
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final d in [-1.0, 1.0]) {
    final p = Path()
      ..moveTo(cx, cy + s * .45)
      ..quadraticBezierTo(cx, cy - s * .05, cx + d * s * .25, cy - s * .35);
    final ox = cx + d * s * .38, oy = cy - s * .18;
    final a0 = math.atan2(-.17, -d * .13), r0 = math.sqrt(.13 * .13 + .17 * .17) * s;
    for (var i = 1; i <= 46; i++) {
      final t = i / 46, a = a0 + d * t * math.pi * 2.3, r = r0 * (1 - .72 * t);
      p.lineTo(ox + math.cos(a) * r, oy + math.sin(a) * r);
    }
    x.drawPath(p, pen);
  }
}

void _dia(Canvas x, double cx, double cy, double rx, double ry, Color fill) =>
    x.drawPath(
        Path()
          ..moveTo(cx, cy - ry)
          ..lineTo(cx + rx, cy)
          ..lineTo(cx, cy + ry)
          ..lineTo(cx - rx, cy)
          ..close(),
        Paint()..color = fill);

void _hornRing(Canvas x, double cx, double cy, double s, Color col, double lw) {
  for (var k = 0; k < 4; k++) {
    x.save();
    x.translate(cx, cy);
    x.rotate(k * math.pi / 2);
    _horn(x, 0, -s * .55, s, col, lw);
    x.restore();
  }
}

void _kilem(Canvas x, Color base, Color border, Color orn, Color acc) {
  const w = 512.0;
  x.drawRect(const Rect.fromLTWH(0, 0, w, w), Paint()..color = border);
  x.drawRect(const Rect.fromLTWH(48, 48, w - 96, w - 96), Paint()..color = base);
  for (var i = 0; i < 8; i++) {
    final p = 32.0 + i * 64;
    for (final (px, py, rot) in [
      (p, 24.0, 0.0),
      (p, w - 24, math.pi),
      (24.0, p, -math.pi / 2),
      (w - 24, p, math.pi / 2)
    ]) {
      x.save();
      x.translate(px, py);
      x.rotate(rot);
      _horn(x, 0, 4, 30, orn, 3);
      x.restore();
    }
  }
  final frame = Paint()
    ..color = orn
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  x.drawRect(const Rect.fromLTWH(56, 56, w - 112, w - 112), frame);
  x.drawRect(const Rect.fromLTWH(66, 66, w - 132, w - 132), frame..strokeWidth = 2);
  _dia(x, w / 2, w / 2, 150, 150, border);
  _dia(x, w / 2, w / 2, 128, 128, acc);
  _dia(x, w / 2, w / 2, 70, 70, border);
  _hornRing(x, w / 2, w / 2, 64, orn, 5);
  for (final (cx, cy) in [(66.0, 66.0), (w - 66, 66.0), (66.0, w - 66), (w - 66, w - 66)]) {
    _dia(x, cx, cy, 60, 60, acc);
    _horn(x, cx, cy, 34, orn, 3);
  }
  for (final (cx, cy) in [(w / 2, 100.0), (w / 2, w - 100), (100.0, w / 2), (w - 100, w / 2)])
    _dia(x, cx, cy, 18, 18, orn);
}

void _tus(Canvas x, Color base, List<Color> cols) {
  const w = 512.0, h = 340.0;
  x.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = base);
  x.drawRect(
      const Rect.fromLTWH(14, 14, w - 28, h - 28),
      Paint()
        ..color = cols[0]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5);
  for (var i = 0; i < 12; i++) {
    final px = 36.0 + i * 40;
    _horn(x, px, 34, 22, cols[i % 3], 2.4);
    _horn(x, px, h - 30, 22, cols[(i + 1) % 3], 2.4);
  }
  x.save();
  x.translate(w / 2, h / 2);
  for (var k = 0; k < 4; k++) {
    x.save();
    x.rotate(k * math.pi / 2);
    _horn(x, 0, -58, 80, cols[k % 3], 5);
    x.restore();
  }
  x.restore();
  _dia(x, w / 2, h / 2, 20, 20, cols[1]);
  for (final s in [-1.0, 1.0]) {
    x.save();
    x.translate(w / 2 + s * 160, h / 2);
    for (var k = 0; k < 4; k++) {
      x.save();
      x.rotate(k * math.pi / 2);
      _horn(x, 0, -34, 48, cols[(k + 1) % 3], 3.5);
      x.restore();
    }
    x.restore();
  }
}

void _kurak(Canvas x, List<Color> cols) {
  const w = 256.0, n = 8, s = w / n;
  for (var i = 0; i < n; i++)
    for (var j = 0; j < n; j++) {
      final a = cols[(i * 3 + j) % cols.length],
          b = cols[(i + j * 2 + 1) % cols.length];
      x.drawRect(Rect.fromLTWH(i * s, j * s, s, s), Paint()..color = a);
      final p = Path();
      if ((i + j) % 2 == 1) {
        p
          ..moveTo(i * s, j * s)
          ..lineTo(i * s + s, j * s)
          ..lineTo(i * s, j * s + s);
      } else {
        p
          ..moveTo(i * s + s, j * s)
          ..lineTo(i * s + s, j * s + s)
          ..lineTo(i * s, j * s + s);
      }
      x.drawPath(p, Paint()..color = b);
    }
  final seam = Paint()
    ..color = const Color(0x59FFFFFF)
    ..strokeWidth = 1;
  for (var i = 0; i <= n; i++) {
    x.drawLine(Offset(i * s, 0), Offset(i * s, w), seam);
    x.drawLine(Offset(0, i * s), Offset(w, i * s), seam);
  }
}

void _sandyq(Canvas x, Color base, Color metal) {
  const w = 512.0, h = 256.0;
  x.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = base);
  final m = Paint()..color = metal;
  for (final y in [18.0, h - 30]) x.drawRect(Rect.fromLTWH(0, y, w, 12), m);
  for (final xx in [24.0, w - 36]) x.drawRect(Rect.fromLTWH(xx, 0, 12, h), m);
  for (var i = 0; i < 3; i++) _hornRing(x, w * (i + 1) / 4, h / 2, 40, metal, 4);
  for (var i = 0; i < 24; i++) x.drawCircle(Offset(10 + i * 21.5, 24), 3, m);
  x.drawRect(Rect.fromLTWH(w / 2 - 16, h / 2 - 24, 32, 40), m);
  x.drawCircle(Offset(w / 2, h / 2 - 6), 6, Paint()..color = base);
}

void _alasha(Canvas x) {
  const w = 256.0, h = 256.0;
  const cs = [0xff7E1E1E, 0xffE8DCC4, 0xff1E2A3A, 0xffC98A2B, 0xff7E1E1E, 0xff2F5C4A];
  const hs = [22.0, 8.0, 14.0, 6.0, 26.0, 8.0];
  var y = 0.0, i = 0;
  while (y < h) {
    x.drawRect(Rect.fromLTWH(0, y, w, hs[i % 6]), Paint()..color = _c(cs[i % cs.length]));
    y += hs[i % 6];
    i++;
  }
  for (var k = 0; k < 8; k++) _dia(x, 16.0 + k * 32, 92, 10, 6, _c(0xffE8DCC4));
}
