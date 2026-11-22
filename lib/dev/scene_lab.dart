// 3D test bench: opens the 3D view straight on a sample house, with frame
// timings, draw counts and an automatic orbit for measuring. No sign-in,
// backend or Firebase.
//
//   flutter run -d macos -t lib/dev/scene_lab.dart --profile
import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show exit;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/commands/house_templates.dart';
import '../core/commands/kz_template.dart';
import '../core/document/house_document.dart';
import '../core/geometry/derived_house.dart';
import '../render3d/scene_view.dart';

void main() => runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: SceneLab()));

class SceneLab extends StatefulWidget {
  const SceneLab({super.key});
  @override
  State<SceneLab> createState() => _SceneLabState();
}

class _SceneLabState extends State<SceneLab> {
  static HouseDocument make(String key) {
    var n = 0;
    String id() => 'lab${n++}';
    const now = '2026-11-16T00:00:00Z';
    return key == 'kz'
        ? createKazakhTemplate(now, id)
        : createTemplate(key, now, id);
  }

  final houses = {
    for (final k in ['kz', 'two', 'five', 'three']) k: make(k)
  };
  String house = 'kz';
  late DerivedHouse derived = deriveHouse(houses[house]!);
  SceneSettings settings = const SceneSettings();
  bool walk = false;
  String view = 'iso';
  int token = 0;
  final scene = GlobalKey<SceneViewState>();

  // Frame timings, averaged over the last second.
  final builds = <double>[], rasters = <double>[];
  String stats = '';
  Timer? statsTimer, spin;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final p = scene.currentState?.painter;
      double avg(List<double> v) =>
          v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
      double worst(List<double> v) => v.isEmpty ? 0 : v.reduce(math.max);
      setState(() => stats = 'UI ${avg(builds).toStringAsFixed(1)} ms '
          '(max ${worst(builds).toStringAsFixed(1)})   '
          'GPU ${avg(rasters).toStringAsFixed(1)} ms '
          '(max ${worst(rasters).toStringAsFixed(1)})   '
          'frames ${builds.length}/s·2\n'
          'faces ${scene.currentState?.model.faces.length ?? 0}   '
          'drawn ${p?.items.length ?? 0}   culled ${p?.culled ?? 0}');
      if (!bench) {
        builds.clear();
        rasters.clear();
      }
    });
    if (bench) runBench();
  }

  void onTimings(List<FrameTiming> t) {
    for (final f in t) {
      builds.add(f.buildDuration.inMicroseconds / 1000);
      rasters.add(f.rasterDuration.inMicroseconds / 1000);
    }
  }

  /// `--dart-define=LAB_BENCH=true`: run every house through each mode
  /// while turning, print the timings and quit.
  static const bench = bool.fromEnvironment('LAB_BENCH');

  /// With LAB_BENCH: turn as a finger does (interactive quality).
  static const drag = bool.fromEnvironment('LAB_DRAG');

  Future<void> runBench() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final modes = <String, (SceneSettings, bool, double)>{
      'full': (const SceneSettings(), false, 1),
      'close': (const SceneSettings(), false, 0.35),
      'noroof': (const SceneSettings(roof: false), false, 1),
      'cut': (const SceneSettings(cut: true), false, 1),
      'cutclose': (const SceneSettings(cut: true), false, 0.35),
      'found': (const SceneSettings(foundation: true), false, 1),
      'walk': (const SceneSettings(), true, 1),
    };
    // ignore: avoid_print
    print('BENCH house mode uiAvg uiMax gpuAvg gpuMax drawn culled');
    for (final h in houses.keys)
      for (final m in modes.entries) {
        setState(() {
          house = h;
          derived = deriveHouse(houses[h]!);
          settings = m.value.$1;
          walk = m.value.$2;
          view = 'iso';
          token++;
        });
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final s = scene.currentState!;
        if (m.value.$3 != 1) {
          // ignore: invalid_use_of_protected_member
          s.setState(() => s.distance *= m.value.$3);
        }
        builds.clear();
        rasters.clear();
        // As under a finger: the interactive-quality frames.
        if (drag) s.touching = 1;
        final sw = Stopwatch()..start();
        var drawn = 0, culled = 0, n = 0;
        while (sw.elapsedMilliseconds < 2500) {
          // ignore: invalid_use_of_protected_member
          s.setState(() {
            if (walk) {
              s.wYaw += 0.03;
            } else {
              s.yaw += 0.03;
            }
          });
          await SchedulerBinding.instance.endOfFrame;
          drawn += s.painter?.items.length ?? 0;
          culled += s.painter?.culled ?? 0;
          n++;
        }
        s.touching = 0;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        double avg(List<double> v) =>
            v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
        double worst(List<double> v) => v.isEmpty ? 0 : v.reduce(math.max);
        // ignore: avoid_print
        print('BENCH $h ${m.key} ${avg(builds).toStringAsFixed(2)} '
            '${worst(builds).toStringAsFixed(2)} ${avg(rasters).toStringAsFixed(2)} '
            '${worst(rasters).toStringAsFixed(2)} ${drawn ~/ n} ${culled ~/ n}');
      }
    exit(0);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    statsTimer?.cancel();
    spin?.cancel();
    super.dispose();
  }

  /// Turn the house steadily, as a finger would, to measure a busy frame.
  void toggleSpin() {
    if (spin != null) {
      spin!.cancel();
      setState(() => spin = null);
      return;
    }
    spin = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final s = scene.currentState;
      if (s == null) return;
      // ignore: invalid_use_of_protected_member
      s.setState(() => s.yaw += 0.02);
    });
    setState(() {});
  }

  Widget chip(String label, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: FilterChip(
          label: Text(label), selected: on, onSelected: (_) => tap()));

  @override
  Widget build(BuildContext context) {
    final doc = houses[house]!;
    return Scaffold(
        body: Column(children: [
      Expanded(
          child: Stack(children: [
        Positioned.fill(
            child: SceneView(
                key: scene,
                doc: doc,
                derived: derived,
                roomName: (r) => r.name,
                settings: settings,
                walk: walk,
                view: view,
                viewToken: token,
                onPick: (_) {})),
        Positioned(
            left: 12,
            top: 12,
            child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black.withValues(alpha: 0.65),
                child: Text(stats,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'JetBrainsMono',
                        fontSize: 12)))),
      ])),
      Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(children: [
            for (final k in houses.keys)
              chip(
                  k,
                  house == k,
                  () => setState(() {
                        house = k;
                        derived = deriveHouse(houses[k]!);
                        token++;
                      })),
            const SizedBox(width: 12),
            for (final v in ['iso', 'front', 'back', 'side', 'top'])
              chip(
                  v,
                  view == v && !walk,
                  () => setState(() {
                        walk = false;
                        view = v;
                        token++;
                      })),
            chip('walk', walk, () => setState(() => walk = !walk)),
            const SizedBox(width: 12),
            chip(
                'roof',
                settings.roof,
                () => setState(
                    () => settings = settings.copyWith(roof: !settings.roof))),
            chip(
                'cut',
                settings.cut,
                () => setState(
                    () => settings = settings.copyWith(cut: !settings.cut))),
            chip(
                'floor 1 only',
                settings.maxFloor == 0,
                () => setState(() => settings = settings.copyWith(
                    maxFloor: settings.maxFloor == 0 ? 999 : 0))),
            chip(
                'furniture',
                settings.furniture,
                () => setState(() => settings =
                    settings.copyWith(furniture: !settings.furniture))),
            chip(
                'foundation',
                settings.foundation,
                () => setState(() => settings =
                    settings.copyWith(foundation: !settings.foundation))),
            chip(
                'night',
                settings.night,
                () => setState(() => settings =
                    settings.copyWith(hour: settings.night ? 11 : 22))),
            const SizedBox(width: 12),
            chip('auto orbit', spin != null, toggleSpin),
          ])),
    ]));
  }
}
