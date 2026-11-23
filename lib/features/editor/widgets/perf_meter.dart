import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:yusal/features/editor/engine/core/perf/engine_perf.dart';

/// What the last frames cost: time building and rasterising, in
/// microseconds, over a sliding window.
class FrameWindow {
  FrameWindow([this.capacity = 120]);
  final int capacity;
  final List<int> _build = [];
  final List<int> _raster = [];

  void add(int buildMicros, int rasterMicros) {
    if (_build.length == capacity) {
      _build.removeAt(0);
      _raster.removeAt(0);
    }
    _build.add(buildMicros);
    _raster.add(rasterMicros);
  }

  void clear() {
    _build.clear();
    _raster.clear();
  }

  int get frames => _build.length;
  double get buildMeanMs => _mean(_build);
  double get rasterMeanMs => _mean(_raster);
  double get buildMaxMs => _max(_build);
  double get rasterMaxMs => _max(_raster);

  /// Frames whose build and raster together took longer than [budgetMs].
  int over(double budgetMs) {
    var n = 0;
    for (var i = 0; i < _build.length; i++) {
      if ((_build[i] + _raster[i]) / 1000 > budgetMs) n++;
    }
    return n;
  }

  Map<String, Object> toJson() => {
        'frames': frames,
        'buildMeanMs': _round(buildMeanMs),
        'buildMaxMs': _round(buildMaxMs),
        'rasterMeanMs': _round(rasterMeanMs),
        'rasterMaxMs': _round(rasterMaxMs),
        'over16ms': over(16.7),
      };

  static double _mean(List<int> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length / 1000;
  static double _max(List<int> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b) / 1000;
  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}

/// The lines the meter shows for what [perf] and [frames] hold now.
List<String> perfMeterLines(EnginePerf perf, FrameWindow frames) {
  String ms(double v) => v.toStringAsFixed(1).padLeft(6);
  final head = 'frame  build${ms(frames.buildMeanMs)}/${ms(frames.buildMaxMs)}'
      '  raster${ms(frames.rasterMeanMs)}/${ms(frames.rasterMaxMs)}'
      '  >16ms ${frames.over(16.7)}/${frames.frames}';
  final out = <String>[head];
  const fixed = [
    'paint.plan2d',
    'paint.scene3d',
    'scene3d.build',
    'scene3d.bsp',
    'derive.house',
    'derive.floorBase',
  ];
  for (final name in fixed) {
    final e = perf.timing(name);
    if (e != null) {
      out.add(
          '${name.padRight(17)}${ms(e.meanMs)}/${ms(e.maxMs)}  x${e.count}');
    }
  }
  final commands = perf.timings
      .where((e) => e.name.startsWith('command.'))
      .toList()
    ..sort((a, b) => b.maxMicros.compareTo(a.maxMicros));
  for (final e in commands.take(4)) {
    out.add('${e.name.substring(8).padRight(17)}'
        '${ms(e.meanMs)}/${ms(e.maxMs)}  x${e.count}');
  }
  final s = perf.sizes;
  if (s.containsKey('scene3d.faces')) {
    out.add('3d faces ${s['scene3d.faces']}  verts ${s['scene3d.vertices']}'
        '  bsp ${s['scene3d.bspFragments'] ?? '-'}'
        '  drawn ${s['scene3d.drawn'] ?? '-'}');
  }
  return out;
}

/// Shows what the engine measures over [child], in a build made with
/// `--dart-define=YUSAL_PERF=true`; in any other build it is [child] alone.
/// Each row is mean / longest in milliseconds. A tap copies the full report
/// to the clipboard, a long press starts the numbers again.
class PerfMeter extends StatefulWidget {
  const PerfMeter({super.key, required this.child, this.show = perfBuild});
  final Widget child;
  final bool show;

  @override
  State<PerfMeter> createState() => _PerfMeterState();
}

class _PerfMeterState extends State<PerfMeter> {
  final frames = FrameWindow();
  Timer? timer;
  int seen = -1;
  bool copied = false;

  @override
  void initState() {
    super.initState();
    if (widget.show) start();
  }

  @override
  void didUpdateWidget(PerfMeter old) {
    super.didUpdateWidget(old);
    if (widget.show && timer == null) start();
    if (!widget.show && timer != null) stop();
  }

  void start() {
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    // Polled, so the meter never asks for a frame because it was drawn.
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = EnginePerf.instance.revision;
      if (now != seen && mounted) setState(() => seen = now);
    });
  }

  void stop() {
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    timer?.cancel();
    timer = null;
  }

  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      frames.add(
          t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
    }
  }

  @override
  void dispose() {
    if (timer != null) stop();
    super.dispose();
  }

  Future<void> copy() async {
    final report = {
      ...EnginePerf.instance.toJson(),
      'frame': frames.toJson(),
    };
    await Clipboard.setData(ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(report)));
    if (!mounted) return;
    setState(() => copied = true);
    Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => copied = false);
    });
  }

  void reset() {
    EnginePerf.instance.reset();
    frames.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;
    final lines = perfMeterLines(EnginePerf.instance, frames);
    return Stack(children: [
      widget.child,
      Positioned(
          left: 4,
          bottom: 4,
          child: SafeArea(
              child: GestureDetector(
                  key: const Key('perf-meter'),
                  onTap: copy,
                  onLongPress: reset,
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: const Color(0xcc000000),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(copied ? 'copied' : lines.join('\n'),
                          style: const TextStyle(
                              color: Color(0xffffffff),
                              fontSize: 9,
                              height: 1.25,
                              fontFamily: 'JetBrainsMono',
                              decoration: TextDecoration.none)))))),
    ]);
  }
}
