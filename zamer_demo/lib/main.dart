import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'solver.dart';

void main() => runApp(const ZamerApp());

class C {
  static const bg = Color(0xFF0F1115);
  static const panel = Color(0xFF181B21);
  static const line = Color(0xFF2A2F38);
  static const ink = Color(0xFFECEFF4);
  static const dim = Color(0xFF8A93A3);
  static const accent = Color(0xFFFF8A3D);
  static const ok = Color(0xFF4CD98A);
  static const warn = Color(0xFFFFC145);
  static const bad = Color(0xFFFF5470);
  static const blue = Color(0xFF5AA9FF);
}

class ZamerApp extends StatelessWidget {
  const ZamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zamer 量房',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.bg,
        colorScheme:
            const ColorScheme.dark(primary: C.accent, surface: C.panel),
        useMaterial3: true,
      ),
      home: const MeasurePage(),
    );
  }
}

enum Mode { sketch, measure, result }

class MeasurePage extends StatefulWidget {
  const MeasurePage({super.key});

  @override
  State<MeasurePage> createState() => _MeasurePageState();
}

class _MeasurePageState extends State<MeasurePage> {
  Mode mode = Mode.sketch;
  final corners = <P>[];

  /// Wall i (corner i to i+1) reading in metres.
  final walls = <int, double>{};
  final diagonals = <Measurement>[];
  int selectedWall = 0;
  bool diagonalMode = false;
  int? diagonalStart;
  SolveResult? result;
  bool showRaw = true;
  final input = TextEditingController();
  final rng = math.Random();
  bool demo = false;

  /// Sketch pixels per metre, used only by the simulated laser meter.
  static const pxPerMetre = 50.0;

  int get n => corners.length;

  void reset() {
    setState(() {
      mode = Mode.sketch;
      corners.clear();
      walls.clear();
      diagonals.clear();
      selectedWall = 0;
      diagonalMode = false;
      diagonalStart = null;
      result = null;
      demo = false;
      input.clear();
    });
  }

  void loadDemo() {
    reset();
    setState(() {
      demo = true;
      corners.addAll(DemoRoom.sketch);
      for (final m in DemoRoom.measurements) {
        if (m.diagonal) {
          diagonals.add(m);
        } else {
          walls[m.a] = m.metres;
        }
      }
      mode = Mode.measure;
      selectedWall = 0;
    });
    solve();
  }

  // ---- sketching -------------------------------------------------------

  P snapToAxis(P prev, P p) {
    final d = p - prev;
    final a = math.atan2(d.y, d.x);
    final q = (a / (math.pi / 4)).roundToDouble() * (math.pi / 4);
    if ((a - q).abs() < 9 * math.pi / 180) {
      return prev + P(math.cos(q), math.sin(q)) * d.len;
    }
    return p;
  }

  void onSketchTap(P p) {
    if (n >= 3 && (p - corners.first).len < 28) {
      HapticFeedback.mediumImpact();
      setState(() {
        mode = Mode.measure;
        selectedWall = 0;
      });
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => corners.add(n == 0 ? p : snapToAxis(corners.last, p)));
  }

  // ---- measuring -------------------------------------------------------

  int? hitCorner(P p) {
    for (var i = 0; i < n; i++) {
      if ((corners[i] - p).len < 28) return i;
    }
    return null;
  }

  int? hitWall(P p) {
    int? best;
    var bestD = 30.0;
    for (var i = 0; i < n; i++) {
      final d = _segDist(p, corners[i], corners[(i + 1) % n]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  static double _segDist(P p, P a, P b) {
    final ab = b - a, ap = p - a;
    final t = ((ap.x * ab.x + ap.y * ab.y) / (ab.x * ab.x + ab.y * ab.y))
        .clamp(0.0, 1.0);
    return (p - (a + ab * t)).len;
  }

  void onMeasureTap(P p) {
    if (diagonalMode) {
      final c = hitCorner(p);
      if (c == null) return;
      if (diagonalStart == null) {
        setState(() => diagonalStart = c);
      } else if (c != diagonalStart) {
        final a = diagonalStart!;
        setState(() => diagonalStart = null);
        _askDiagonal(a, c);
      }
      return;
    }
    final w = hitWall(p);
    if (w != null) {
      setState(() {
        selectedWall = w;
        input.text = walls[w]?.toStringAsFixed(3) ?? '';
      });
    }
  }

  double simulatedReading(int a, int b) {
    final metres = (corners[b] - corners[a]).len / pxPerMetre;
    final rounded = (metres * 20).round() / 20; // the "real" wall, to 5 cm
    return rounded + (rng.nextDouble() - 0.5) * 0.006; // ±3 mm laser noise
  }

  void setWall(double v) {
    HapticFeedback.lightImpact();
    setState(() {
      walls[selectedWall] = v;
      result = null;
      for (var k = 1; k <= n; k++) {
        final next = (selectedWall + k) % n;
        if (!walls.containsKey(next)) {
          selectedWall = next;
          break;
        }
      }
      input.text = walls[selectedWall]?.toStringAsFixed(3) ?? '';
    });
  }

  Future<void> _askDiagonal(int a, int b) async {
    final ctl = TextEditingController();
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text('对角线 ${_label(a)} → ${_label(b)}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(suffixText: 'm', hintText: '例如 7.071'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, simulatedReading(a, b)),
            child: const Text('模拟测距仪'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctl.text.replaceAll(',', '.'))),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (v != null && v > 0) {
      setState(() {
        diagonals.add(Measurement(a, b, v, diagonal: true));
        diagonalMode = false;
        result = null;
      });
    }
  }

  void solve() {
    if (walls.length < n) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('还有 ${n - walls.length} 面墙没量')),
      );
      return;
    }
    final ms = [
      for (var i = 0; i < n; i++) Measurement(i, (i + 1) % n, walls[i]!),
      ...diagonals,
    ];
    final r = RoomSolver(corners, ms).solve();
    HapticFeedback.heavyImpact();
    setState(() {
      result = r;
      mode = Mode.result;
      showRaw = true;
    });
  }

  static String _label(int i) => String.fromCharCode(65 + i);

  // ---- UI --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LayoutBuilder(builder: (ctx, box) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        final p = P(d.localPosition.dx, d.localPosition.dy);
                        if (mode == Mode.sketch) onSketchTap(p);
                        if (mode == Mode.measure) onMeasureTap(p);
                      },
                      child: CustomPaint(
                        key: const Key('plan'),
                        size: Size(box.maxWidth, box.maxHeight),
                        painter: PlanPainter(this),
                      ),
                    );
                  }),
                ),
              ),
            ),
            _panel(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final steps = ['画草图', '量尺寸', '自动闭合'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Zamer',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: C.ink,
                      letterSpacing: -0.5)),
              const SizedBox(width: 6),
              const Text('量房',
                  style: TextStyle(
                      fontSize: 16,
                      color: C.accent,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  onPressed: reset,
                  icon: const Icon(Icons.refresh, color: C.dim),
                  tooltip: '重来'),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: mode.index == i
                        ? C.accent.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${i + 1}. ${steps[i]}',
                      style: TextStyle(
                          fontSize: 12,
                          color: mode.index == i
                              ? C.accent
                              : (mode.index > i ? C.ok : C.dim),
                          fontWeight: FontWeight.w600)),
                ),
                if (i < 2)
                  const Icon(Icons.chevron_right, size: 16, color: C.line),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.line),
        ),
        child: switch (mode) {
          Mode.sketch => _sketchPanel(),
          Mode.measure => _measurePanel(),
          Mode.result => _resultPanel(),
        },
      ),
    );
  }

  Widget _sketchPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            n == 0
                ? '点屏幕放下第一个墙角'
                : n < 3
                    ? '继续点下一个墙角'
                    : '点回起点 A 闭合房间',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: C.ink)),
        const SizedBox(height: 4),
        const Text('草图不用画准，只用来告诉 App 有几面墙、怎么连。接近横平竖直会自动对齐。',
            style: TextStyle(color: C.dim, fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loadDemo,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('看示例房间'),
            ),
          ),
          const SizedBox(width: 8),
          if (n > 0)
            OutlinedButton(
              onPressed: () => setState(() => corners.removeLast()),
              child: const Text('撤销'),
            ),
        ]),
      ],
    );
  }

  Widget _measurePanel() {
    final done = walls.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text(
            diagonalMode
                ? (diagonalStart == null ? '点对角线的起点墙角' : '点对角线的终点墙角')
                : '墙 ${_label(selectedWall)}${_label((selectedWall + 1) % n)}',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: C.ink),
          ),
          const Spacer(),
          Text('$done / $n 面墙 · ${diagonals.length} 条对角线',
              style: const TextStyle(color: C.dim, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        if (!diagonalMode)
          Row(children: [
            Expanded(
              child: TextField(
                controller: input,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: 'm',
                  hintText: '手动输入',
                  filled: true,
                  fillColor: C.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (t) {
                  final v = double.tryParse(t.replaceAll(',', '.'));
                  if (v != null && v > 0) setWall(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: C.blue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
              onPressed: () => setWall(
                  simulatedReading(selectedWall, (selectedWall + 1) % n)),
              icon: const Icon(Icons.bluetooth),
              label: const Text('模拟测距仪'),
            ),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                diagonalMode = !diagonalMode;
                diagonalStart = null;
              }),
              icon: Icon(diagonalMode ? Icons.close : Icons.call_made),
              label: Text(diagonalMode ? '取消' : '加对角线校验'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: done == n ? solve : null,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('自动闭合'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _resultPanel() {
    final r = result!;
    final maxRes = r.checks
        .where((c) => !r.suspects.any((s) => identical(s.m, c.m)))
        .fold<double>(0, (m, c) => math.max(m, c.residual.abs()));
    Widget stat(String k, String v, Color col) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(color: C.dim, fontSize: 11)),
            const SizedBox(height: 2),
            Text(v,
                style: TextStyle(
                    color: col, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          stat('原始闭合差', '${(r.rawGap * 100).toStringAsFixed(1)} cm',
              r.rawGap > 0.02 ? C.bad : C.warn),
          stat('调整后最大误差', '${(maxRes * 1000).toStringAsFixed(1)} mm', C.ok),
          stat('面积', '${r.area.toStringAsFixed(2)} m²', C.ink),
        ]),
        const SizedBox(height: 12),
        if (r.suspects.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.bad.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: C.bad),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(_suspectText(r),
                      style: const TextStyle(
                          color: C.ink, fontSize: 13, height: 1.35))),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: C.ok.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.check_circle_outline, color: C.ok),
              SizedBox(width: 10),
              Expanded(
                  child: Text('所有读数互相吻合，误差已平均分配到各面墙。',
                      style: TextStyle(color: C.ink, fontSize: 13))),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => showRaw = !showRaw),
              child: Text(showRaw ? '隐藏原始走线' : '显示原始走线'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => setState(() => mode = Mode.measure),
              child: const Text('返回修改'),
            ),
          ),
        ]),
      ],
    );
  }

  String _suspectText(SolveResult r) {
    String name(Measurement m) => m.diagonal
        ? '对角线 ${_label(m.a)}${_label(m.b)}'
        : '墙 ${_label(m.a)}${_label(m.b)}';
    if (r.suspects.length == 1) {
      final s = r.suspects.first;
      final diff = (s.looError! * 100).abs().toStringAsFixed(1);
      return '${name(s.m)} 很可能量错了：你量的是 ${s.m.metres.toStringAsFixed(3)} m，'
          '其他读数推算应为 ${s.looExpected!.toStringAsFixed(3)} m（差 $diff cm）。'
          '平面图已按其他读数生成，建议重量这一面。';
    }
    return '${r.suspects.map((s) => name(s.m)).join(' 或 ')} 其中有一个量错了，'
        '现有读数分不出是哪一个。加一条经过它们的对角线就能定位。';
  }
}

class PlanPainter extends CustomPainter {
  PlanPainter(this.s);
  final _MeasurePageState s;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF13161B));
    _grid(canvas, size);
    if (s.mode == Mode.result && s.result != null) {
      _result(canvas, size, s.result!);
    } else {
      _sketch(canvas, size);
    }
  }

  void _grid(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFF1B1F26)
      ..strokeWidth = 1;
    const step = _MeasurePageState.pxPerMetre / 2;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
  }

  Offset o(P p) => Offset(p.x, p.y);

  void _sketch(Canvas canvas, Size size) {
    final pts = s.corners;
    final n = pts.length;
    if (n == 0) return;
    final closed = s.mode != Mode.sketch;
    final wallCount = closed ? n : n - 1;
    for (var i = 0; i < wallCount; i++) {
      final a = pts[i], b = pts[(i + 1) % n];
      final measured = s.walls.containsKey(i);
      final selected =
          s.mode == Mode.measure && !s.diagonalMode && s.selectedWall == i;
      final paint = Paint()
        ..color = selected ? C.accent : (measured ? C.ink : C.dim)
        ..strokeWidth = selected ? 6 : 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(o(a), o(b), paint);
      if (measured) {
        _label(canvas, a, b, '${s.walls[i]!.toStringAsFixed(3)} m',
            selected ? C.accent : C.ink);
      } else if (selected) {
        _label(canvas, a, b, '?', C.accent);
      }
    }
    for (final d in s.diagonals) {
      _dashed(canvas, o(pts[d.a]), o(pts[d.b]), C.blue.withValues(alpha: 0.8));
      _label(canvas, pts[d.a], pts[d.b], '${d.metres.toStringAsFixed(3)} m',
          C.blue,
          offset: 0);
    }
    for (var i = 0; i < n; i++) {
      final hot =
          s.diagonalStart == i || (s.mode == Mode.sketch && i == 0 && n >= 3);
      canvas.drawCircle(
          o(pts[i]), hot ? 10 : 7, Paint()..color = hot ? C.accent : C.ink);
      canvas.drawCircle(o(pts[i]), hot ? 5 : 3.5, Paint()..color = C.bg);
      _text(canvas, _MeasurePageState._label(i),
          o(pts[i]) + const Offset(10, -22), C.dim, 12);
    }
  }

  void _result(Canvas canvas, Size size, SolveResult r) {
    // Fit the solved plan (metres) into the canvas.
    final all = [...r.corners, if (s.showRaw) ...r.rawTraverse];
    var minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final p in all) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    const pad = 64.0;
    final k = math.min((size.width - 2 * pad) / (maxX - minX),
        (size.height - 2 * pad) / (maxY - minY));
    final ox = (size.width - (maxX - minX) * k) / 2 - minX * k;
    final oy = (size.height - (maxY - minY) * k) / 2 - minY * k;
    P map(P p) => P(p.x * k + ox, p.y * k + oy);
    final pts = [for (final p in r.corners) map(p)];
    final n = pts.length;

    // Floor fill.
    final path = Path()..moveTo(pts[0].x, pts[0].y);
    for (final p in pts.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = C.accent.withValues(alpha: 0.07));

    if (s.showRaw) {
      final raw = [for (final p in r.rawTraverse) map(p)];
      for (var i = 0; i < raw.length - 1; i++) {
        _dashed(
            canvas, o(raw[i]), o(raw[i + 1]), C.bad.withValues(alpha: 0.55));
      }
      canvas.drawCircle(o(raw.last), 5, Paint()..color = C.bad);
      _text(canvas, '原始走线终点 · 差 ${(r.rawGap * 100).toStringAsFixed(1)} cm',
          o(raw.last) + const Offset(8, 4), C.bad, 11);
    }

    final suspect = {for (final x in r.suspects) x.m};
    for (final c in r.checks.where((c) => c.m.diagonal)) {
      final bad = suspect.contains(c.m);
      _dashed(canvas, o(pts[c.m.a]), o(pts[c.m.b]),
          (bad ? C.bad : C.blue).withValues(alpha: 0.6));
    }

    for (final c in r.checks.where((c) => !c.m.diagonal)) {
      final a = pts[c.m.a], b = pts[c.m.b];
      final bad = suspect.contains(c.m);
      final e = c.residual.abs();
      final col = bad ? C.bad : (e < 0.005 ? C.ok : C.warn);
      canvas.drawLine(
          o(a),
          o(b),
          Paint()
            ..color = C.ink
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.square);
      canvas.drawLine(
          o(a),
          o(b),
          Paint()
            ..color = col
            ..strokeWidth = 3);
      final text = bad
          ? '${c.m.metres.toStringAsFixed(3)} → ${c.fitted.toStringAsFixed(3)}'
          : c.fitted.toStringAsFixed(3);
      _label(canvas, a, b, text, bad ? C.bad : C.ink, outside: true, poly: pts);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(o(pts[i]), 4, Paint()..color = C.ink);
      if (r.rightAngles[i]) _rightMark(canvas, pts, i);
    }
  }

  void _rightMark(Canvas canvas, List<P> pts, int i) {
    final n = pts.length;
    final b = pts[i];
    P unit(P v) => v * (1 / v.len);
    final u = unit(pts[(i - 1 + n) % n] - b) * 10,
        v = unit(pts[(i + 1) % n] - b) * 10;
    final p = Path()
      ..moveTo(b.x + u.x, b.y + u.y)
      ..lineTo(b.x + u.x + v.x, b.y + u.y + v.y)
      ..lineTo(b.x + v.x, b.y + v.y);
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = C.dim
          ..strokeWidth = 1);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color col) {
    final paint = Paint()
      ..color = col
      ..strokeWidth = 1.6;
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    for (var t = 0.0; t < len; t += 10) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + 5, len), paint);
    }
  }

  void _label(Canvas canvas, P a, P b, String text, Color col,
      {double offset = 18, bool outside = false, List<P>? poly}) {
    final mid = (a + b) * 0.5;
    final d = b - a;
    var nrm = P(-d.y, d.x) * (1 / (d.len == 0 ? 1 : d.len));
    if (outside && poly != null) {
      // Push the label away from the room's centre.
      var cx = 0.0, cy = 0.0;
      for (final p in poly) {
        cx += p.x;
        cy += p.y;
      }
      final c = P(cx / poly.length, cy / poly.length);
      final toMid = mid - c;
      if (toMid.x * nrm.x + toMid.y * nrm.y < 0) nrm = nrm * -1;
    }
    final at = mid + nrm * offset;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: col,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
        center: Offset(at.x, at.y),
        width: tp.width + 10,
        height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = const Color(0xE6101318));
    tp.paint(canvas, rect.topLeft + const Offset(5, 2));
  }

  void _text(Canvas canvas, String t, Offset at, Color col, double size) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              color: col, fontSize: size, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
