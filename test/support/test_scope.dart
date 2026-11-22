import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/app.dart';
import 'package:yusal/features/auth/page.dart';
import 'package:yusal/features/houses/model/my_house.dart';
import 'package:yusal/features/houses/state/my_houses.dart';
import 'package:yusal/features/shared/state/session.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'http.dart';
import 'mock/backend.dart';

export 'http.dart';
export 'mock/backend.dart';

/// The provider overrides for [repos]: a [Backend] fake or a [TestHttp].
List<Override> overridesFor(Object repos) => switch (repos) {
      final TestHttp h => h.overrides,
      final Backend b => mockOverrides(b),
      _ => throw ArgumentError.value(repos, 'repos'),
    };

/// What the app root gives every page, for tests that pump a page alone:
/// the backend behind every repository provider, the design store and,
/// optionally, a sign-in page (none by default).
class TestScope extends StatelessWidget {
  const TestScope(
      {super.key,
      required this.repos,
      this.store,
      this.loginPage,
      required this.child});

  /// A [Backend] fake or a [TestHttp].
  final Object repos;
  final ProjectStore? store;
  final WidgetBuilder? loginPage;
  final Widget child;

  @override
  Widget build(BuildContext context) => ProviderScope(overrides: [
        ...overridesFor(repos),
        if (store != null) projectStoreProvider.overrideWithValue(store!),
        loginPageProvider.overrideWithValue(loginPage),
      ], child: child);
}

/// The whole app over [repos] (a [Backend] fake or a [TestHttp]) and
/// [store], signing in through the real login page.
Widget testApp(Object repos, {ProjectStore? store, Key? key}) => ProviderScope(
    key: key,
    overrides: [
      ...overridesFor(repos),
      if (store != null) projectStoreProvider.overrideWithValue(store),
      loginPageProvider.overrideWithValue((_) => const LoginPage()),
    ],
    child: const HouseApp());

/// Reads [provider] once against [repos] and [store], as a page would.
Future<T> readOnce<T>(Backend repos, ProjectStore store,
    ProviderListenable<Future<T>> provider) async {
  final container = ProviderContainer(overrides: [
    ...mockOverrides(repos),
    projectStoreProvider.overrideWithValue(store),
  ]);
  try {
    return await container.read(provider);
  } finally {
    container.dispose();
  }
}

/// My houses for the signed-in account of [repos].
Future<List<MyHouse>> loadMyHouses(Backend repos, ProjectStore store) =>
    readOnce(repos, store, myHousesProvider.future);
