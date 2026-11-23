import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/service/api/api_client.dart';

export 'package:yusal/service/api/api_client.dart'
    show ChangeSource, ClockSource, Session;

/// Who is signed in, and when anything changed.
final sessionProvider = Provider<Session>((ref) => ApiClient.app);

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
