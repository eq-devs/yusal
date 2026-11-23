import 'dart:math' as math;

/// A 2D point in metres (or sketch pixels before solving).
class P {
  const P(this.x, this.y);
  final double x, y;
  P operator +(P o) => P(x + o.x, y + o.y);
  P operator -(P o) => P(x - o.x, y - o.y);
  P operator *(double s) => P(x * s, y * s);
  double get len => math.sqrt(x * x + y * y);
  P rotate(double a) =>
      P(x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a));
}

/// One tape or laser reading between two corners.
class Measurement {
  const Measurement(this.a, this.b, this.metres, {this.diagonal = false});
  final int a, b;
  final double metres;
  final bool diagonal;
}

/// What the solver concluded about one measurement.
class MeasurementCheck {
  MeasurementCheck(
      this.m, this.fitted, this.looExpected, this.costDrop, this.looCorners);
  final Measurement m;

  /// Corners solved without this reading (local frame).
  final List<P> looCorners;

  /// Length of this segment in the adjusted plan.
  final double fitted;

  /// What the other readings say this one should be (leave-one-out).
  final double? looExpected;

  /// How much the total misfit drops when this reading is ignored.
  final double costDrop;

  double get residual => m.metres - fitted;
  double? get looError => looExpected == null ? null : m.metres - looExpected!;
}

class SolveResult {
  SolveResult({
    required this.corners,
    required this.checks,
    required this.rawGap,
    required this.rawTraverse,
    required this.area,
    required this.suspects,
    required this.rightAngles,
  });

  final List<P> corners;
  final List<MeasurementCheck> checks;

  /// How far the raw walk (measured lengths + snapped angles) misses its start.
  final double rawGap;
  final List<P> rawTraverse;
  final double area;

  /// Readings that most likely hold a mistake (more than one when the data
  /// cannot tell them apart).
  final List<MeasurementCheck> suspects;
  final List<bool> rightAngles;
}

/// Closes a hand-measured room by weighted least squares.
///
/// Unknowns are the corner coordinates. Each reading says "the distance
/// between corner a and b is d" (σ = 4 mm). Each corner that was sketched
/// close to a multiple of 90° is assumed square (σ = 0.2°); other corners
/// keep their sketched angle only weakly (σ = 20°). Levenberg–Marquardt
/// finds the shape that fits everything best; leave-one-out solves then
/// show which reading disagrees with the rest.
class RoomSolver {
  RoomSolver(this.sketch, this.measurements);

  final List<P> sketch;
  final List<Measurement> measurements;

  static const sigmaLen = 0.004;
  static const sigmaSquare = 0.2 * math.pi / 180;
  static const sigmaFree = 20 * math.pi / 180;
  static const snapTol = 12 * math.pi / 180;

  int get n => sketch.length;

  late final List<double> _angleTarget = [];
  late final List<double> _angleSigma = [];
  late final List<bool> _square = [];

  static double turnAt(List<P> pts, int k) {
    final n = pts.length;
    final a = pts[(k - 1 + n) % n], b = pts[k], c = pts[(k + 1) % n];
    final u = b - a, v = c - b;
    return math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y);
  }

  void _prepareAngles() {
    for (var k = 0; k < n; k++) {
      final t = turnAt(sketch, k);
      final q = (t / (math.pi / 2)).roundToDouble() * (math.pi / 2);
      if ((t - q).abs() < snapTol && q != 0) {
        _angleTarget.add(q);
        _angleSigma.add(sigmaSquare);
        _square.add(true);
      } else {
        _angleTarget.add(t);
        _angleSigma.add(sigmaFree);
        _square.add(false);
      }
    }
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }

  List<P> _unpack(List<double> p) =>
      [for (var i = 0; i < n; i++) P(p[2 * i], p[2 * i + 1])];

  List<double> _residuals(List<double> p, List<Measurement> ms) {
    final pts = _unpack(p);
    final r = <double>[];
    for (final m in ms) {
      r.add(((pts[m.b] - pts[m.a]).len - m.metres) / sigmaLen);
    }
    for (var k = 0; k < n; k++) {
      r.add(_wrap(turnAt(pts, k) - _angleTarget[k]) / _angleSigma[k]);
    }
    return r;
  }

  static double _cost(List<double> r) => r.fold(0.0, (s, e) => s + e * e);

  /// Unknowns that stay put to remove translation and rotation: x0, y0, y1.
  static const _fixed = {0, 1, 3};

  List<double> _solve(List<double> start, List<Measurement> ms) {
    var p = [...start];
    var r = _residuals(p, ms);
    var cost = _cost(r);
    var lambda = 1e-3;
    final free = [
      for (var i = 0; i < 2 * n; i++)
        if (!_fixed.contains(i)) i
    ];
    final m = free.length;
    for (var iter = 0; iter < 200; iter++) {
      // Numeric Jacobian.
      final jac = List.generate(r.length, (_) => List<double>.filled(m, 0));
      for (var c = 0; c < m; c++) {
        final i = free[c];
        const h = 1e-7;
        final q = [...p];
        q[i] += h;
        final rq = _residuals(q, ms);
        for (var row = 0; row < r.length; row++) {
          jac[row][c] = (rq[row] - r[row]) / h;
        }
      }
      final jtj = List.generate(m, (_) => List<double>.filled(m, 0));
      final jtr = List<double>.filled(m, 0);
      for (var row = 0; row < r.length; row++) {
        final jr = jac[row];
        for (var a = 0; a < m; a++) {
          if (jr[a] == 0) continue;
          jtr[a] += jr[a] * r[row];
          for (var b = 0; b < m; b++) {
            jtj[a][b] += jr[a] * jr[b];
          }
        }
      }
      var improved = false;
      for (var tries = 0; tries < 10; tries++) {
        final aMat = [
          for (var a = 0; a < m; a++)
            [
              for (var b = 0; b < m; b++)
                jtj[a][b] + (a == b ? lambda * (jtj[a][a] + 1e-6) : 0.0)
            ]
        ];
        final delta = _gauss(aMat, [for (final v in jtr) -v]);
        if (delta == null) {
          lambda *= 10;
          continue;
        }
        final q = [...p];
        for (var c = 0; c < m; c++) {
          q[free[c]] += delta[c];
        }
        final rq = _residuals(q, ms);
        final cq = _cost(rq);
        if (cq < cost) {
          final rel = (cost - cq) / (cost + 1e-12);
          p = q;
          r = rq;
          cost = cq;
          lambda = math.max(lambda / 10, 1e-9);
          improved = true;
          if (rel < 1e-12) return p;
          break;
        }
        lambda *= 10;
      }
      if (!improved) break;
    }
    return p;
  }

  static List<double>? _gauss(List<List<double>> a, List<double> b) {
    final n = b.length;
    for (var col = 0; col < n; col++) {
      var piv = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[piv][col].abs()) piv = r;
      }
      if (a[piv][col].abs() < 1e-14) return null;
      final tmp = a[col];
      a[col] = a[piv];
      a[piv] = tmp;
      final tb = b[col];
      b[col] = b[piv];
      b[piv] = tb;
      for (var r = col + 1; r < n; r++) {
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c < n; c++) {
          a[r][c] -= f * a[col][c];
        }
        b[r] -= f * b[col];
      }
    }
    final x = List<double>.filled(n, 0);
    for (var r = n - 1; r >= 0; r--) {
      var s = b[r];
      for (var c = r + 1; c < n; c++) {
        s -= a[r][c] * x[c];
      }
      x[r] = s / a[r][r];
    }
    return x;
  }

  SolveResult solve() {
    _prepareAngles();

    // Start from the sketch, scaled to the readings and turned so that wall 0
    // lies along +x (the gauge the solver keeps fixed).
    final ratios = <double>[];
    for (final m in measurements) {
      final s = (sketch[m.b] - sketch[m.a]).len;
      if (s > 0) ratios.add(m.metres / s);
    }
    ratios.sort();
    final scale = ratios.isEmpty ? 1.0 : ratios[ratios.length ~/ 2];
    final w0 = sketch[1] - sketch[0];
    final turn = -math.atan2(w0.y, w0.x);
    final start = <double>[];
    for (final s in sketch) {
      final q = ((s - sketch[0]) * scale).rotate(turn);
      start
        ..add(q.x)
        ..add(q.y);
    }

    final full = _solve(start, measurements);
    final fullCost = _cost(_residuals(full, measurements));
    final ptsLocal = _unpack(full);

    // Leave-one-out: what do the other readings say about each one?
    final checks = <MeasurementCheck>[];
    for (var i = 0; i < measurements.length; i++) {
      final m = measurements[i];
      final rest = [...measurements]..removeAt(i);
      final p = _solve(full, rest);
      final c = _cost(_residuals(p, rest));
      final pts = _unpack(p);
      checks.add(MeasurementCheck(
        m,
        (ptsLocal[m.b] - ptsLocal[m.a]).len,
        (pts[m.b] - pts[m.a]).len,
        fullCost - c,
        pts,
      ));
    }

    final ranked = [...checks]
      ..sort((a, b) => b.costDrop.compareTo(a.costDrop));
    final suspects = <MeasurementCheck>[];
    if (ranked.isNotEmpty) {
      final top = ranked.first;
      if (top.costDrop > 16 && (top.looError ?? 0).abs() > 0.012) {
        for (final c in ranked) {
          if (c.costDrop > top.costDrop * 0.85) suspects.add(c);
        }
      }
    }

    // Raw walk with measured lengths and snapped angles, to show the gap.
    final raw = <P>[const P(0, 0)];
    var heading = 0.0;
    for (var i = 0; i < n; i++) {
      final m = measurements.firstWhere(
        (m) => !m.diagonal && m.a == i && m.b == (i + 1) % n,
        orElse: () => Measurement(
            i, (i + 1) % n, (sketch[(i + 1) % n] - sketch[i]).len * scale),
      );
      raw.add(raw.last + P(math.cos(heading), math.sin(heading)) * m.metres);
      heading += _angleTarget[(i + 1) % n];
    }

    // One clear outlier: drop it and keep the plan the other readings give.
    final best = suspects.length == 1 ? suspects.first.looCorners : ptsLocal;
    final fitted = [
      for (final c in checks)
        MeasurementCheck(c.m, (best[c.m.b] - best[c.m.a]).len, c.looExpected,
            c.costDrop, c.looCorners)
    ];
    final fittedSuspects = [
      for (final s in suspects) fitted[checks.indexOf(s)]
    ];

    // Turn back to the sketch orientation for display.
    // Keep walls axis-aligned: undo the turn only to the nearest 90°.
    final back = (-turn / (math.pi / 2)).roundToDouble() * (math.pi / 2);
    final corners = [for (final q in best) q.rotate(back)];
    final rawT = [for (final q in raw) q.rotate(back)];

    var area = 0.0;
    for (var i = 0; i < n; i++) {
      final a = corners[i], b = corners[(i + 1) % n];
      area += a.x * b.y - b.x * a.y;
    }

    return SolveResult(
      corners: corners,
      checks: fitted,
      rawGap: (raw.last - raw.first).len,
      rawTraverse: rawT,
      area: area.abs() / 2,
      suspects: fittedSuspects,
      rightAngles: [..._square],
    );
  }
}

/// A demo L-shaped room: true size 6.20 × 5.10 m with a 2.40 × 1.70 m notch.
/// Wall 4 was misread by 4.2 cm; the two diagonals let the solver find it.
class DemoRoom {
  static const sketch = [
    P(60, 80),
    P(318, 86),
    P(322, 228),
    P(222, 224),
    P(226, 296),
    P(64, 290),
  ];
  static const measurements = [
    Measurement(0, 1, 6.204),
    Measurement(1, 2, 3.398),
    Measurement(2, 3, 2.402),
    Measurement(3, 4, 1.703),
    Measurement(4, 5, 3.842), // misread, really 3.800
    Measurement(5, 0, 5.098),
    Measurement(0, 2, 7.071, diagonal: true),
    Measurement(3, 5, 4.163, diagonal: true),
  ];
}
