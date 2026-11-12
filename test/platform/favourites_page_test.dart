import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/ui/me/me_page.dart';
import 'package:yusal/platform/ui/profile/profile_page.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

void main() {
  testWidgets('a house I hearted shows up under 我的 › 收藏', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final b = MockBackend(latency: Duration.zero)..signInAs(SeedIds.roofTeam);
    await b.toggleLike('post_aigerim');
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const FavouritesPage())));
    await t.pumpAndSettle();
    expect(find.text('房子'), findsOneWidget);
    expect(find.byKey(const Key('fav-house-post_aigerim')), findsOneWidget);
    expect(find.text('还没有收藏'), findsNothing);
  });

  testWidgets('houses, workers and demands all show in one place', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final b = MockBackend(latency: Duration.zero)..signInAs(SeedIds.owner2);
    if (!(await b.liked('post_aigerim'))) await b.toggleLike('post_aigerim');
    for (final id in ['prof_mason', 'dem_wall']) {
      if (!(await b.favourites()).contains(id)) await b.toggleFavourite(id);
    }
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const FavouritesPage())));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('fav-house-post_aigerim')), findsOneWidget);
    await t.scrollUntilVisible(
        find.byKey(const Key('fav-profile-prof_mason')), 200);
    expect(find.byKey(const Key('fav-profile-prof_mason')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('fav-demand-dem_wall')), 200);
    expect(find.byKey(const Key('fav-demand-dem_wall')), findsOneWidget);
  });

  testWidgets('the heart on a worker profile saves it', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final b = MockBackend(latency: Duration.zero)..signInAs(SeedIds.owner2);
    if ((await b.favourites()).contains('prof_mason')) {
      await b.toggleFavourite('prof_mason');
    }
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const ProfilePage(profileId: 'prof_mason'))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('profile-favourite')));
    await t.pumpAndSettle();
    expect(await b.favourites(), contains('prof_mason'));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('with nothing saved, the page says where to save from',
      (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final b = MockBackend(latency: Duration.zero)..signInAs(SeedIds.roofTeam);
    for (final id in await b.likedPosts()) {
      await b.toggleLike(id);
    }
    for (final id in await b.favourites()) {
      await b.toggleFavourite(id);
    }
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const FavouritesPage())));
    await t.pumpAndSettle();
    expect(find.text('还没有收藏'), findsOneWidget);
  });
}
