import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';

/// Firebase (Analytics, Crashlytics, and the base for push) on iOS and
/// Android. The web build and tests run without it.
class FirebaseSetup {
  FirebaseSetup._();

  static bool _ready = false;

  /// Whether Firebase started on this device.
  static bool get ready => _ready;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Starts Firebase once; later calls return the first result.
  static Future<bool> init() async {
    if (_ready) return true;
    if (!_supported) return false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
      _ready = true;
    } catch (e) {
      debugPrint('firebase: init failed, running without it ($e)');
      return false;
    }
    _wireCrashlytics();
    return true;
  }

  static void _wireCrashlytics() {
    final crashlytics = FirebaseCrashlytics.instance;
    // Debug runs on a developer's phone shouldn't fill the crash list.
    unawaited(crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode));
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterError?.call(details);
      crashlytics.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Screen views for Analytics; empty until Firebase is ready.
  static List<NavigatorObserver> get observers => _ready
      ? [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
      : const [];
}
