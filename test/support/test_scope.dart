import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/app.dart';
import 'package:yusal/features/houses/model/my_house.dart';
import 'package:yusal/features/houses/state/my_houses.dart';
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
/// the backend behind every repository provider and the design store.
class TestScope extends StatelessWidget {
  const TestScope(
      {super.key, required this.repos, this.store, required this.child});

  /// A [Backend] fake or a [TestHttp].
  final Object repos;
  final ProjectStore? store;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (store != null) ProjectStore.app = store!;
    return ProviderScope(overrides: overridesFor(repos), child: child);
  }
}

/// The whole app over [repos] (a [Backend] fake or a [TestHttp]) and
/// [store], signing in through the real login page.
Widget testApp(Object repos, {ProjectStore? store, Key? key}) {
  if (store != null) ProjectStore.app = store;
  return ProviderScope(
      key: key, overrides: overridesFor(repos), child: const HouseApp());
}

/// Reads [provider] once against [repos] and [store], as a page would.
Future<T> readOnce<T>(Backend repos, ProjectStore store,
    ProviderListenable<Future<T>> provider) async {
  ProjectStore.app = store;
  final container = ProviderContainer(overrides: mockOverrides(repos));
  try {
    return await container.read(provider);
  } finally {
    container.dispose();
  }
}

/// My houses for the signed-in account of [repos].
Future<List<MyHouse>> loadMyHouses(Backend repos, ProjectStore store) =>
    readOnce(repos, store, myHousesProvider.future);
