import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:yusal/app/http_backend.dart';
import 'package:yusal/features/chat/pages/inbox.dart' show openRef;
import 'package:yusal/services/firebase_setup.dart';
import 'package:yusal/services/push/push_setup.dart';
import 'package:yusal/services/update/code_push.dart';
import 'package:yusal/app/app.dart';
import 'package:yusal/shared/settings/settings.dart';

/// The backend (yusal-api on eqserver).
const apiBaseUrl = 'https://eqserver.tail920a63.ts.net';

/// App startup, each part run once however often it is asked for.
///
/// * [ready]: what the first frame needs, read from the device only (the
///   settings, the saved session with the signed-in account, Firebase). No
///   network, so a cold start is the same online and offline and the
///   signed-in user sees their own profile at once.
/// * [background]: everything that talks to a server (session sync, push,
///   code push), started once [ready] is done and never awaited by a screen.
abstract final class Boot {
  /// The one backend for the app's lifetime.
  static final HttpBackend api = HttpBackend(apiBaseUrl);

  static final Future<void> ready = _ready();

  static final Future<void> background = _background();

  static Future<void> _ready() => Future.wait([
        _step('settings', AppSettings.instance.load),
        _step('session', api.loadSession),
        // Analytics and crash reports on iOS / Android; no-op on the web.
        _step('firebase', FirebaseSetup.init),
      ]);

  static Future<void> _background() async {
    await ready;
    // After the first frame is on screen, so a permission prompt (push)
    // never covers a blank window.
    await WidgetsBinding.instance.endOfFrame;
    unawaited(_step('session sync', api.syncSession));
    unawaited(
        _step('push', PushSetup(api, appNavigator, opener: openRef).start));
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
          ? HouseApp(repos: Boot.api)
          : const SizedBox.shrink());
}
