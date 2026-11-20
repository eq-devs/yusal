import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/house_app.dart';
import 'app/settings.dart';
import 'data/http/http_backend.dart';
import 'features/chat/inbox_page.dart' show openRef;
import 'services/firebase_setup.dart';
import 'services/push/push_setup.dart';
import 'services/update/code_push.dart';

export 'app/house_app.dart';

/// Real backend address, e.g. `--dart-define=YUSAL_API=https://api.example.com`.
/// Empty: the in-memory demo backend.
const apiBaseUrl = String.fromEnvironment('YUSAL_API');

/// Longest the first frame waits for a saved session. A slow or sleeping
/// server must not hold the splash screen: the session keeps restoring in
/// the background and the shell follows when it arrives.
const _restoreBudget = Duration(seconds: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = apiBaseUrl.isEmpty ? null : HttpBackend(apiBaseUrl);
  // Independent startup steps run side by side: the first frame waits for
  // the slowest of them, not for their sum.
  await Future.wait([
    AppSettings.instance.load(),
    // Analytics and crash reports on iOS / Android; no-op on the web.
    FirebaseSetup.init(),
    if (api != null) _restore(api),
  ]);
  runApp(ProviderScope(child: HouseApp(repos: api)));
  // Push only with the real backend; the demo registers no token.
  if (api != null) unawaited(PushSetup(api, appNavigator, opener: openRef).start());
  // Over-the-air patches (Shorebird); a no-op outside `shorebird release`.
  CodePush().start();
}

/// Never lets a failed restore keep the app from starting.
Future<void> _restore(HttpBackend api) async {
  try {
    await api.restore().timeout(_restoreBudget);
  } catch (e) {
    if (kDebugMode) debugPrint('session restore: $e');
  }
}
