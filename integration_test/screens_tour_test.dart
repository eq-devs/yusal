import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

/// A slow walk through the main screens on a real device or simulator, so
/// they can be looked at (or captured with `xcrun simctl io booted
/// screenshot`): each screen is held for a few seconds and announced with a
/// `SCREEN <name>` line.
///
///   flutter test integration_test/screens_tour_test.dart -d <device> \
///       --dart-define=TOUR_LANG=kk --dart-define=TOUR_NIGHT=true
const _lang = String.fromEnvironment('TOUR_LANG', defaultValue: 'ru');
const _night = bool.fromEnvironment('TOUR_NIGHT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tour of the main screens', (t) async {
    final store = ProjectStore();
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);
    AppSettings.instance.lang = AppLang.values.byName(_lang);
    AppSettings.instance.theme = _night ? ThemeChoice.night : ThemeChoice.day;
    var n = 0;
    final id = await store.createProject(createKazakhTemplate(
        DateTime.now().toUtc().toIso8601String(), () => 'tour_${n++}',
        name: 'Tour house', names: kazakhTemplateNames()));

    Future<void> hold(String name) async {
      await t.pumpAndSettle();
      // ignore: avoid_print
      print('SCREEN $name');
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    try {
      final backend = MockBackend(latency: Duration.zero)
        ..signInAs(SeedIds.owner);
      await t.pumpWidget(
          ProviderScope(child: HouseApp(repos: backend, store: store)));
      await hold('discover');
      await t.tap(find.byType(NavigationDestination).at(1));
      await hold('houses');
      await t.tap(find.text('Tour house'));
      for (var i = 0;
          i < 50 && find.byKey(const ValueKey('tab-ext')).evaluate().isEmpty;
          i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await hold('editor');
      await t.tap(find.byKey(const ValueKey('tab-ext')));
      await hold('editor-3d');
      await t.tap(find.byType(BackButton).first);
      await hold('houses-again');
      await t.tap(find.byType(NavigationDestination).at(2));
      await hold('messages');
      await t.tap(find.byType(NavigationDestination).at(3));
      await hold('me');
      await t.tap(find.byType(NavigationDestination).at(0));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('explore-seg-1')));
      await hold('work');
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await store.deleteProject(id);
      await LastOpenProject.write(previous);
      AppSettings.instance.lang = AppLang.zh;
      AppSettings.instance.theme = ThemeChoice.auto;
    }
  });
}
