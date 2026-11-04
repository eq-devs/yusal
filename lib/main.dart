import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/settings.dart';
import 'app/tokens.dart';
import 'platform/data/mock/mock_backend.dart';
import 'platform/data/repositories.dart';
import 'platform/ui/home/post_page.dart';
import 'platform/ui/links.dart';
import 'platform/ui/scope.dart';
import 'platform/ui/shell.dart';
import 'render2d/project_preview.dart';
import 'storage/project_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const ProviderScope(child: HouseApp()));
}

class HouseApp extends StatefulWidget {
  const HouseApp({super.key, this.repos, this.store});

  /// Platform backend; the in-memory mock until a real server exists.
  final PlatformRepositories? repos;
  final ProjectStore? store;

  @override
  State<HouseApp> createState() => _HouseAppState();
}

class _HouseAppState extends State<HouseApp> {
  late final PlatformRepositories repos = widget.repos ?? MockBackend();
  late final ProjectStore store =
      widget.store ?? ProjectStore(previewRenderer: renderProjectPreview);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return PlatformScope(
            repos: repos,
            store: store,
            child: MaterialApp(
                title: 'Yusal',
                debugShowCheckedModeBanner: false,
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
