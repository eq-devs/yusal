import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Over-the-air Dart patches through Shorebird.
///
/// `shorebird.yaml` turns the engine's own launch-time update off, so this
/// is the one place that checks: once at launch and again whenever the app
/// comes back to the foreground. A downloaded patch takes effect on the next
/// cold start. Store builds follow the stable track; `shorebird preview
/// --track staging` points a test device at staging patches. In builds made with `flutter build` / `flutter run` the
/// updater is unavailable and this does nothing.
class CodePush with WidgetsBindingObserver {
  CodePush([ShorebirdUpdater? updater])
      : _updater = updater ?? ShorebirdUpdater();

  final ShorebirdUpdater _updater;
  bool _busy = false;
  DateTime? _lastCheck;

  /// Don't ask the server again on every quick app switch.
  static const _minInterval = Duration(minutes: 15);

  /// Patch the app is running now; null on the release itself or when the
  /// updater is unavailable.
  Future<int?> currentPatch() async {
    if (!_updater.isAvailable) return null;
    try {
      return (await _updater.readCurrentPatch())?.number;
    } catch (_) {
      return null;
    }
  }

  void start() {
    if (!_updater.isAvailable) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// Downloads a newer patch if there is one. Never throws: a failed check
  /// just waits for the next one.
  Future<void> check() async {
    final now = DateTime.now();
    if (_busy ||
        (_lastCheck != null && now.difference(_lastCheck!) < _minInterval)) {
      return;
    }
    _busy = true;
    _lastCheck = now;
    try {
      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        await _updater.update();
        debugPrint('code push: patch downloaded, applies on next launch');
      }
    } catch (e) {
      debugPrint('code push: check failed ($e)');
    } finally {
      _busy = false;
    }
  }
}
