import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/ui/home/post_page.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

/// Phone-width layouts in all three languages: an overflow fails the test.
void main() {
  for (final lang in AppLang.values) {
    testWidgets('house page at phone width in $lang', (t) async {
      SharedPreferences.setMockInitialValues({});
      AppSettings.instance.lang = lang;
      t.binding.platformDispatcher.defaultRouteNameTestValue = '/h/post_aigerim';
      addTearDown(t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repos = MockBackend(
          clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
          latency: Duration.zero,
          autoReviewDelay: Duration.zero);
      await t.pumpWidget(ProviderScope(
          child: HouseApp(
              repos: repos, store: ProjectStore(fileSystem: MemoryFiles()))));
      await t.pumpAndSettle();
      expect(find.byType(PostPage), findsOneWidget);
      await t.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await t.pumpAndSettle();
      await t.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await t.pumpAndSettle();
    });

    testWidgets('feed, design, inbox and me tabs at phone width in $lang',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      AppSettings.instance.lang = lang;
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repos = MockBackend(
          clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
          latency: Duration.zero,
          autoReviewDelay: Duration.zero);
      repos.signInAs(SeedIds.owner);
      await t.pumpWidget(ProviderScope(
          child: HouseApp(
              repos: repos, store: ProjectStore(fileSystem: MemoryFiles()))));
      await t.pumpAndSettle();
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
      await t.pumpAndSettle();
      for (final i in [1, 2, 3]) {
        await t.tap(find.byType(NavigationDestination).at(i));
        await t.pumpAndSettle();
      }
      await t.drag(find.byType(ListView).first, const Offset(0, -900));
      await t.pumpAndSettle();
    });
  }
}
