import 'dart:developer' show Timeline;

/// Whether the engine measures its own work. Off unless built with
/// `--dart-define=YUSAL_PERF=true`, so a normal build pays nothing: every
/// call below is then a plain call of the work it wraps.
const bool perfBuild = bool.fromEnvironment('YUSAL_PERF');

/// What one named piece of work has cost since the last [EnginePerf.reset].
class PerfEntry {
  PerfEntry(this.name);
  final String name;
  int count = 0;
  int totalMicros = 0;
  int maxMicros = 0;
  int lastMicros = 0;

  double get meanMs => count == 0 ? 0 : totalMicros / count / 1000;
  double get maxMs => maxMicros / 1000;
  double get lastMs => lastMicros / 1000;

  Map<String, Object> toJson() => {
        'count': count,
        'meanMs': double.parse(meanMs.toStringAsFixed(3)),
        'maxMs': double.parse(maxMs.toStringAsFixed(3)),
        'lastMs': double.parse(lastMs.toStringAsFixed(3)),
      };
}

/// One piece of work that took longer than [EnginePerf.slowMicros].
typedef SlowMark = ({String name, int micros});

/// Timings and sizes the engine reports about itself: how long commands,
/// derivation and painting take, and how large the 3D scene is. Read by the
/// on-screen meter and by the baseline benchmark; nothing in the engine
/// reads it back.
class EnginePerf {
  EnginePerf._();
  static final EnginePerf instance = EnginePerf._();

  /// On in a perf build; tests and the benchmark switch it on by hand.
  static bool enabled = perfBuild;

  /// Work slower than this is kept in [slow]: a third of a 60 Hz frame.
  static const slowMicros = 5000;
  static const _slowKept = 40;

  final Map<String, PerfEntry> _timings = {};
  final Map<String, int> _sizes = {};
  final List<SlowMark> _slow = [];

  /// Bumped with every record, so a listener can tell whether to redraw.
  int revision = 0;

  Iterable<PerfEntry> get timings => _timings.values;
  Map<String, int> get sizes => Map.unmodifiable(_sizes);
  List<SlowMark> get slow => List.unmodifiable(_slow);
  PerfEntry? timing(String name) => _timings[name];

  void record(String name, int micros) {
    final e = (_timings[name] ??= PerfEntry(name))
      ..count += 1
      ..totalMicros += micros
      ..lastMicros = micros;
    if (micros > e.maxMicros) e.maxMicros = micros;
    if (micros >= slowMicros) {
      if (_slow.length == _slowKept) _slow.removeAt(0);
      _slow.add((name: name, micros: micros));
    }
    revision++;
  }

  /// Notes the latest size of something, such as the faces of the scene.
  void size(String name, int value) {
    _sizes[name] = value;
    revision++;
  }

  void reset() {
    _timings.clear();
    _sizes.clear();
    _slow.clear();
    revision++;
  }

  /// Everything measured, for a report file or the clipboard.
  Map<String, Object> toJson() => {
        'timings': {
          for (final e
              in _timings.values.toList()
                ..sort((a, b) => a.name.compareTo(b.name)))
            e.name: e.toJson()
        },
        'sizes': {
          for (final k in _sizes.keys.toList()..sort()) k: _sizes[k]!,
        },
        'slow': [
          for (final s in _slow)
            {
              'name': s.name,
              'ms': double.parse((s.micros / 1000).toStringAsFixed(3))
            }
        ],
      };
}

/// Runs [work], and when measuring is on records what it took under [name]
/// and marks it on the DevTools timeline.
@pragma('vm:prefer-inline')
T timed<T>(String name, T Function() work) {
  if (!EnginePerf.enabled) return work();
  final watch = Stopwatch()..start();
  try {
    return Timeline.timeSync(name, work);
  } finally {
    EnginePerf.instance.record(name, watch.elapsedMicroseconds);
  }
}

/// Notes a size under [name] when measuring is on; [value] is only worked
/// out then.
@pragma('vm:prefer-inline')
void sized(String name, int Function() value) {
  if (EnginePerf.enabled) EnginePerf.instance.size(name, value());
}
