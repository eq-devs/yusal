import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/constant/tokens.dart';
import 'package:yusal/features/chat/pages/inbox.dart' show openRef;
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/home/pages/post.dart';
import 'package:yusal/features/shared/state/session.dart';
import 'package:yusal/features/shared/ui/links.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shell/page.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/repository/audio_device.dart';
import 'package:yusal/features/voice/repository/speech.dart';
import 'package:yusal/features/voice/repository/voice_repository.dart';
import 'package:yusal/features/voice/widgets/voice_overlay.dart';
import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/firebase_setup.dart';
import 'package:yusal/service/push/push_setup.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/update/code_push.dart';

/// App startup, each part run once however often it is asked for.
///
/// * [ready]: what the first frame needs, read from the device only (the
///   settings, the saved session with the signed-in account, Firebase). No
///   network, so a cold start is the same online and offline.
/// * [background]: everything that talks to a server (session sync, push,
///   code push), started once [ready] is done and never awaited by a screen.
abstract final class Boot {
  static final Future<void> ready = Future.wait([
    _step('settings', AppSettings.instance.load),
    _step('session', ApiClient.app.loadSession),
    // Analytics and crash reports on iOS / Android; no-op on the web.
    _step('firebase', FirebaseSetup.init),
  ]);

  static final Future<void> background = _background();

  static Future<void> _background() async {
    await ready;
    // After the first frame is on screen, so a permission prompt (push)
    // never covers a blank window.
    await WidgetsBinding.instance.endOfFrame;
    unawaited(_step('session sync', ApiClient.app.syncSession));
    unawaited(_step(
        'push', PushSetup(ApiClient.app, appNavigator, opener: openRef).start));
    // Over-the-air patches (Shorebird); a no-op outside `shorebird release`.
    unawaited(_step('code push', () async => CodePush().start()));
  }

  /// One failed step never keeps the app from starting.
  static Future<void> _step(String name, Future<Object?> Function() run) async {
    try {
      await run();
    } catch (e, st) {
      if (kDebugMode) debugPrint('boot $name: $e\n$st');
    }
  }
}

/// The root: nothing until [Boot.ready] (the first frame is held, so the
/// native launch screen stays up), then the app.
class BootGate extends StatelessWidget {
  const BootGate({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
      future: Boot.ready,
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? const ProviderScope(child: HouseApp())
          : const SizedBox.shrink());
}

/// The app's navigator, for opening what a tapped push points to.
final appNavigator = GlobalKey<NavigatorState>();

/// The microphone for voice control, on phones and tablets.
final AudioDevice? voiceAudio =
    voiceBuiltIn && voicePlatform ? PluginAudio() : null;

const _locales = [Locale('kk'), Locale('ru'), Locale('zh')];

/// The root widget: theme, language and routes.
class HouseApp extends ConsumerStatefulWidget {
  const HouseApp({super.key});

  @override
  ConsumerState<HouseApp> createState() => _HouseAppState();
}

class _HouseAppState extends ConsumerState<HouseApp> {
  // Themes are rebuilt only when the theme choice changes, not on every
  // settings change (a language switch keeps the same ThemeData objects).
  ThemeChoice? _themeFor;
  late ThemeData _light;
  late ThemeData _dark;
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
        return MaterialApp(
            navigatorKey: appNavigator,
            navigatorObservers: FirebaseSetup.observers,
            title: 'Yusal',
            debugShowCheckedModeBanner: false,
            // System texts (back, close, copy / paste, pickers) and what
            // screen readers announce follow the app language.
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
                    repos: VoiceRepositories(
                        session: ref.read(sessionProvider),
                        demands: ref.read(demandRepositoryProvider),
                        cooperations: ref.read(cooperationRepositoryProvider)),
                    voice: ref.read(voiceRepositoryProvider),
                    audio: voiceAudio,
                    child: child!)),
            // `/h/<id>` is a shared house: open it directly, signed in or
            // not. Everything else is the app shell.
            onGenerateRoute: _route,
            // One route for the opening address, not one per path segment,
            // so a shared house has nothing underneath it.
            onGenerateInitialRoutes: (name) =>
                [_route(RouteSettings(name: name))]);
      });

  static Route<dynamic> _route(RouteSettings settings) {
    final id = houseIdFromRoute(settings.name);
    return platformRoute(
        (_) => id == null ? const PlatformShell() : PostPage(postId: id));
  }
}
