import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/settings.dart';
import '../data/http/http_backend.dart';
import '../domain/models.dart';
import '../firebase_setup.dart';
import '../ui/chat/inbox_page.dart';

/// What the app needs from a push service; Firebase in the app, a fake in
/// tests.
abstract class PushMessaging {
  /// False when the service can't start here (no Firebase config yet).
  Future<bool> init();
  Future<bool> requestPermission();
  Future<String?> token();
  Stream<String> get tokenRefreshes;

  /// Data of pushes the person taps while the app runs in the background.
  Stream<Map<String, dynamic>> get opened;

  /// Data of the push that launched the app, if any.
  Future<Map<String, dynamic>?> launchedFrom();
}

class FirebasePushMessaging implements PushMessaging {
  @override
  Future<bool> init() async {
    final ok = await FirebaseSetup.init();
    if (!ok) debugPrint('push: Firebase not available, push is off');
    return ok;
  }

  @override
  Future<bool> requestPermission() async {
    final s = await FirebaseMessaging.instance.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  // The API sends with FCM HTTP v1 to registration tokens. The newer
  // register()/onRegistered gives an installation ID for direct send
  // instead, which the API does not use yet.
  @override
  // ignore: deprecated_member_use
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Future<Map<String, dynamic>?> launchedFrom() async =>
      (await FirebaseMessaging.instance.getInitialMessage())?.data;
}

/// The object a push points to, from its `ref_type` / `ref_id` data.
(RefType, String)? pushTarget(Map<String, dynamic> data) {
  final id = data['ref_id'];
  final type = RefType.values.asNameMap()[data['ref_type']];
  if (id is! String || id.isEmpty || type == null) return null;
  return (type, id);
}

/// Registers this device for pushes with the API and opens what a tapped
/// push points to. Only for the real backend, and not on the web.
class PushSetup {
  PushSetup(this.api, this.navigator,
      {PushMessaging? messaging, this.opener = openRef})
      : messaging = messaging ?? FirebasePushMessaging();
  final HttpBackend api;
  final GlobalKey<NavigatorState> navigator;
  final PushMessaging messaging;

  /// Opens a target page; [openRef] in the app.
  final Future<void> Function(BuildContext, RefType, String) opener;
  final _subs = <StreamSubscription<Object?>>[];

  static String get platform => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => defaultTargetPlatform.name,
      };

  Future<void> start() async {
    if (kIsWeb || !await messaging.init()) return;
    _subs.add(messaging.opened.listen(open));
    final launch = await messaging.launchedFrom();
    if (launch != null) {
      // Let the first frame build the navigator.
      WidgetsBinding.instance.addPostFrameCallback((_) => open(launch));
    }
    if (!await messaging.requestPermission()) return;
    _subs.add(messaging.tokenRefreshes.listen(_register));
    final t = await messaging.token();
    if (t != null) await _register(t);
  }

  Future<void> _register(String token) => api.setPushToken(token,
      platform: platform, language: AppSettings.instance.lang.name);

  void open(Map<String, dynamic> data) {
    final target = pushTarget(data);
    final context = navigator.currentContext;
    if (target == null || context == null) return;
    opener(context, target.$1, target.$2);
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}
