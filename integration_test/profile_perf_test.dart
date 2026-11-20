// Frame cost of scrolling the profile page and the Me tab, on real frames.
//
//   flutter drive --profile -d <device> \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/profile_perf_test.dart
//
// Reports the median and 90th-percentile UI-thread (build + layout + paint)
// and raster time per frame for each scenario.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart' show HouseApp;
import 'package:yusal/shared/ui/widgets.dart' show Avatar, debugFrostedGlass;
import '../test/support/mock/mock_backend.dart';
import '../test/support/mock/mock_seed.dart';
import 'package:yusal/features/profile/profile_page.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/features/shell/shell.dart';
import 'package:yusal/storage/project_store.dart';

import '../test/storage_test.dart' show MemoryFiles;

void appNavigatorPush(WidgetTester t, Widget page) {
  t.state<NavigatorState>(find.byType(Navigator).first).push(
      platformRoute<void>((_) => page));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile scroll frame cost', (t) async {
    // --dart-define=YUSAL_FROST=on|off forces the glass blur for an A/B run;
    // unset follows the platform.
    const frost = String.fromEnvironment('YUSAL_FROST');
    if (frost.isNotEmpty) debugFrostedGlass = frost == 'on';
    addTearDown(() => debugFrostedGlass = null);
    // A phone-sized page wherever this runs, so a desktop window does not
    // switch the shell to its side rail.
    if (t.view.physicalSize.width / t.view.devicePixelRatio > 500) {
      t.view.physicalSize = const Size(402, 874) * t.view.devicePixelRatio;
      addTearDown(t.view.resetPhysicalSize);
    }
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => frames.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final report = <String, dynamic>{};

    Future<void> flush() async {
      // Timings arrive in batches, up to a second late.
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1500)));
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
    }

    Future<void> scenario(String name, Future<void> Function(int i) step,
        {int count = 160}) async {
      for (var i = 0; i < 20; i++) await step(i);
      await flush();
      frames.clear();
      for (var i = 0; i < count; i++) await step(i);
      await flush();
      double ms(Duration d) => d.inMicroseconds / 1000;
      List<double> sorted(double Function(FrameTiming) f) =>
          frames.map(f).toList()..sort();
      final ui = sorted((f) => ms(f.buildDuration)),
          raster = sorted((f) => ms(f.rasterDuration));
      double at(List<double> v, double q) =>
          v.isEmpty ? 0 : v[((v.length - 1) * q).round()];
      report[name] = {
        'frames': frames.length,
        'ui_ms_p50': at(ui, 0.5),
        'ui_ms_p90': at(ui, 0.9),
        'raster_ms_p50': at(raster, 0.5),
        'raster_ms_p90': at(raster, 0.9),
      };
      frames.clear();
    }

    Future<void> mount(Widget home, String account) async {
      final b = MockBackend(latency: Duration.zero)..signInAs(account);
      await t.pumpWidget(PlatformScope(
          key: UniqueKey(),
          repos: b,
          store: ProjectStore(fileSystem: MemoryFiles()),
          child: MaterialApp(
              builder: (_, child) => AppScope(child: child!), home: home)));
      // Entrances play out; fixed pumps, since some pages never settle.
      for (var i = 0; i < 90; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    // A finger dragging the page up and down, one move per frame.
    Future<void> scrollScenario(String name) async {
      final view = t.view.physicalSize / t.view.devicePixelRatio;
      final g = await t.startGesture(Offset(view.width / 2, view.height / 2));
      await g.moveBy(const Offset(0, -30));
      await t.pump();
      await scenario(name, (i) async {
        await g.moveBy(Offset(0, (i ~/ 20).isEven ? -9 : 9));
        await t.pump();
      });
      await g.up();
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    await mount(const ProfilePage(profileId: 'prof_mason'), SeedIds.owner2);
    expect(find.byKey(const Key('profile-favourite')), findsOneWidget);
    await scrollScenario('profile page scroll');

    await mount(const PlatformShell(initialTab: ShellTab.me), SeedIds.mason);
    await scrollScenario('me tab scroll');

    // The whole app as it ships: voice orb, theme, routes.
    final b = MockBackend(latency: Duration.zero)..signInAs(SeedIds.mason);
    await t.pumpWidget(ProviderScope(
        key: UniqueKey(),
        child: HouseApp(
            repos: b, store: ProjectStore(fileSystem: MemoryFiles()))));
    Future<void> rest() async {
      for (var i = 0; i < 90; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    await rest();
    // The first screen people see: the house feed under the tab bar.
    await scrollScenario('app explore scroll');
    await t.tap(find.byType(ShellBarTab).last);
    await rest();
    report['app me tab: frame still scheduled at rest'] =
        t.binding.hasScheduledFrame;
    await scrollScenario('app me tab scroll');
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(ProviderScope(
        key: UniqueKey(),
        child: HouseApp(
            repos: b, store: ProjectStore(fileSystem: MemoryFiles()))));
    await rest();
    appNavigatorPush(t, const ProfilePage(profileId: 'prof_mason'));
    await rest();
    expect(find.byType(Avatar), findsWidgets);
    report['app profile page: frame still scheduled at rest'] =
        t.binding.hasScheduledFrame;
    await scrollScenario('app profile page scroll');

    SchedulerBinding.instance.removeTimingsCallback(collect);
    binding.reportData = report;
  });
}
