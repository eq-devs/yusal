import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/shared/model/models.dart';

/// A backend with its own clock (the in-memory test fake). Screens read the
/// time through it so tests can move time forward.
abstract interface class ClockSource {
  DateTime get now;
}

/// Fires whenever any data behind the repositories changes.
abstract interface class ChangeSource {
  Listenable get changes;
}

/// What every screen may ask of the backend session: who is signed in, and
/// when anything changed. The app's backend and the test fake both are one.
abstract interface class Session implements ChangeSource {
  Account? get currentAccount;
}

/// The session. `lib/app` overrides it (and each feature's repository
/// provider) with the one backend; tests override it with the fake.
final sessionProvider = Provider<Session>(
    (ref) => throw UnimplementedError('sessionProvider is not overridden'));

/// The sign-in page [requireLogin] opens; the auth feature's page in the
/// app. Null (tests that never sign in) means sign-in is not offered.
final loginPageProvider = Provider<WidgetBuilder?>((ref) => null);

/// Reads a provider from a widget's context, for one-off reads in callbacks
/// (a button's write, a dialog). Watching belongs in a `Consumer…` widget.
extension ProviderContext on BuildContext {
  T read<T>(ProviderListenable<T> provider) =>
      ProviderScope.containerOf(this, listen: false).read(provider);

  Session get session => read(sessionProvider);

  /// The current time; a test backend with its own clock sets it.
  DateTime get now => switch (session) {
        ClockSource clock => clock.now,
        _ => DateTime.now(),
      };
}
