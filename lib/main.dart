import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/settings.dart';
import 'app/tokens.dart';
import 'platform/data/http/http_backend.dart';
import 'platform/data/mock/mock_backend.dart';
import 'platform/data/repositories.dart';
import 'platform/push/push_setup.dart';
import 'platform/ui/home/post_page.dart';
import 'platform/ui/links.dart';
import 'platform/ui/scope.dart';
import 'platform/ui/shell.dart';
import 'render2d/project_preview.dart';
import 'storage/project_store.dart';

/// Real backend address, e.g. `--dart-define=YUSAL_API=https://api.example.com`.
/// Empty: the in-memory demo backend.
const apiBaseUrl = String.fromEnvironment('YUSAL_API');

/// The app's navigator, for opening what a tapped push points to.
final appNavigator = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  PlatformRepositories? repos;
  if (apiBaseUrl.isNotEmpty) {
    final api = HttpBackend(apiBaseUrl);
    // Don't hold the first frame on a slow or sleeping server: the session
    // keeps restoring in the background and shows up when it is back.
    await api.restore().timeout(const Duration(seconds: 6), onTimeout: () {});
    repos = api;
    // Push only with the real backend; the demo never touches Firebase.
    unawaited(PushSetup(api, appNavigator).start());
  }
  runApp(ProviderScope(child: HouseApp(repos: repos)));
}

class HouseApp extends StatefulWidget {
  const HouseApp({super.key, this.repos, this.store});

  /// Platform backend: [HttpBackend] when built with YUSAL_API, else the
  /// in-memory mock.
  final PlatformRepositories? repos;
  final ProjectStore? store;

  @override
  State<HouseApp> createState() => _HouseAppState();
}

class _HouseAppState extends State<HouseApp> {
  late final PlatformRepositories repos = widget.repos ?? MockBackend();
  late final ProjectStore store =
      (widget.store ??
          ProjectStore(
              previewRenderer: renderProjectPreview,
              owners: PrefsProjectOwners()))
        ..currentOwner ??= () => repos.currentAccount?.id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return PlatformScope(
            repos: repos,
            store: store,
            isDemo: repos is MockBackend && repos is! HttpBackend,
            child: MaterialApp(
                navigatorKey: appNavigator,
                title: 'Yusal',
                debugShowCheckedModeBanner: false,
                // System texts (back, close, copy / paste, pickers) and
                // what screen readers announce follow the app language.
                locale: Locale(settings.lang.name),
                supportedLocales: const [
                  Locale('kk'),
                  Locale('ru'),
                  Locale('zh')
                ],
                localizationsDelegates:
                    GlobalMaterialLocalizations.delegates,
                theme: buildTheme(settings.theme == ThemeChoice.night
                    ? Tokens.night
                    : Tokens.light),
                darkTheme: buildTheme(settings.theme == ThemeChoice.day
                    ? Tokens.light
                    : Tokens.night),
                themeMode: switch (settings.theme) {
                  ThemeChoice.auto => ThemeMode.system,
                  ThemeChoice.day => ThemeMode.light,
                  ThemeChoice.night => ThemeMode.dark
                },
                builder: (context, child) => AppScope(child: child!),
                // `/h/<id>` is a shared house: open it directly, signed in
                // or not. Everything else is the app shell.
                onGenerateRoute: _route,
                // One route for the opening address, not one per path
                // segment, so a shared house has nothing underneath it.
                onGenerateInitialRoutes: (name) =>
                    [_route(RouteSettings(name: name))]));
      });

  static Route<dynamic> _route(RouteSettings settings) {
    final id = houseIdFromRoute(settings.name);
    return platformRoute(
        (_) => id == null ? const PlatformShell() : PostPage(postId: id));
  }
}
