import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/http/http_backend.dart';
import '../data/repositories.dart';
import '../services/firebase_setup.dart';
import '../features/auth/login_page.dart';
import '../features/home/post_page.dart';
import '../shared/ui/links.dart';
import '../shared/ui/scope.dart';
import '../features/shell/shell.dart';
import '../render2d/project_preview.dart';
import '../storage/project_store.dart';
import '../voice/audio_device.dart';
import '../voice/speech.dart';
import '../voice/voice_overlay.dart';
import 'settings.dart';
import 'tokens.dart';

/// The app's navigator, for opening what a tapped push points to.
final appNavigator = GlobalKey<NavigatorState>();

/// The microphone for voice control, on phones and tablets.
final AudioDevice? voiceAudio =
    voiceBuiltIn && voicePlatform ? PluginAudio() : null;

const _locales = [Locale('kk'), Locale('ru'), Locale('zh')];

/// The root widget: repositories, the local design store, theme, language
/// and routes. Startup work lives in `main.dart`; this only builds.
class HouseApp extends StatefulWidget {
  const HouseApp({super.key, required this.repos, this.store});

  /// Platform backend: [HttpBackend] in the app, a fake in tests.
  final PlatformRepositories repos;
  final ProjectStore? store;

  @override
  State<HouseApp> createState() => _HouseAppState();
}

class _HouseAppState extends State<HouseApp> {
  late final PlatformRepositories repos = widget.repos;
  late final ProjectStore store = (widget.store ??
      ProjectStore(
          previewRenderer: renderProjectPreview, owners: PrefsProjectOwners()))
    ..currentOwner ??= () => repos.currentAccount?.id;

  // Themes are rebuilt only when the theme choice changes, not on every
  // settings change (a language switch keeps the same ThemeData objects).
  ThemeChoice? _themeFor;
  late ThemeData _light, _dark;
  void _themes(ThemeChoice choice) {
    if (choice == _themeFor) return;
    _themeFor = choice;
    _light =
        buildTheme(choice == ThemeChoice.night ? Tokens.night : Tokens.light);
    _dark = buildTheme(choice == ThemeChoice.day ? Tokens.light : Tokens.night);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        _themes(settings.theme);
        return PlatformScope(
            repos: repos,
            store: store,
            loginPage: (_) => const LoginPage(),
            child: MaterialApp(
                navigatorKey: appNavigator,
                navigatorObservers: FirebaseSetup.observers,
                title: 'Yusal',
                debugShowCheckedModeBanner: false,
                // System texts (back, close, copy / paste, pickers) and
                // what screen readers announce follow the app language.
                locale: Locale(settings.lang.name),
                supportedLocales: _locales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: _light,
                darkTheme: _dark,
                themeMode: switch (settings.theme) {
                  ThemeChoice.auto => ThemeMode.system,
                  ThemeChoice.day => ThemeMode.light,
                  ThemeChoice.night => ThemeMode.dark
                },
                builder: (context, child) => AppScope(
                    child: VoiceHost(
                        navigator: appNavigator,
                        repos: repos,
                        audio: voiceAudio,
                        child: child!)),
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
