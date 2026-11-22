import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/app/backend.dart';
import 'package:yusal/features/houses/model/my_house.dart';
import 'package:yusal/features/houses/state/my_houses.dart';
import 'package:yusal/services/storage/project_store.dart';
import 'package:yusal/shared/state/session.dart';

/// What the app root gives every page, for tests that pump a page alone:
/// the backend behind every repository provider, the design store and,
/// optionally, a sign-in page.
class TestScope extends StatelessWidget {
  const TestScope(
      {super.key,
      required this.repos,
      this.store,
      this.loginPage,
      required this.child});
  final Backend repos;
  final ProjectStore? store;
  final WidgetBuilder? loginPage;
  final Widget child;

  @override
  Widget build(BuildContext context) => ProviderScope(overrides: [
        ...backendOverrides(repos),
        if (store != null) projectStoreProvider.overrideWithValue(store!),
        if (loginPage != null) loginPageProvider.overrideWithValue(loginPage),
      ], child: child);
}

/// Reads [provider] once against [repos] and [store], as a page would.
Future<T> readOnce<T>(Backend repos, ProjectStore store,
    ProviderListenable<Future<T>> provider) async {
  final container = ProviderContainer(overrides: [
    ...backendOverrides(repos),
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
