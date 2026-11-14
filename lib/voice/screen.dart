import 'package:flutter/widgets.dart';

import 'action.dart';

/// A page's contract with the voice layer: what it is, what it shows and
/// what can be done on it. Pages keep their state privately, so each one
/// says this itself.
///
/// ```dart
/// class _DemandDetailState extends State<DemandDetailPage>
///     with VoiceScreen {
///   @override
///   String get screenId => 'demand.detail';
/// }
/// ```
mixin VoiceScreen<T extends StatefulWidget> on State<T> {
  /// Stable dotted name: "demand.detail".
  String get screenId;

  /// What is on screen right now that an action can act on.
  List<Entity> get entities => const [];

  /// Ids of the actions that belong to this page.
  List<String> get actions => const [];

  /// One line for the language model about what the page shows.
  String get summary => '';

  @override
  void initState() {
    super.initState();
    VoiceScreens._mounted.add(this);
  }

  @override
  void dispose() {
    VoiceScreens._mounted.remove(this);
    super.dispose();
  }
}

/// The pages that are alive and have a contract.
abstract final class VoiceScreens {
  static final _mounted = <VoiceScreen>[];

  static Iterable<VoiceScreen> get mounted => _mounted;

  /// The page the user is looking at: the newest one whose route is on
  /// top. Null while a page or dialog without a contract covers it, so
  /// voice never acts on something hidden.
  static VoiceScreen? get current {
    for (final s in _mounted.reversed) {
      if (ModalRoute.of(s.context)?.isCurrent ?? true) return s;
    }
    return null;
  }
}
