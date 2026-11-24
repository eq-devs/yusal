import 'package:flutter/widgets.dart';

import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/model/form.dart';

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

  /// Whether the assistant's orb shows on this page. Off where it would
  /// only be in the way, as beside a conversation's own input.
  bool get showsAssistant => true;

  /// One line for the language model about what the page shows.
  String get summary => '';

  /// What the page holds in detail, as a few lines of text for the
  /// language model. Sent with every step, so keep it short.
  String get scene => '';

  /// The inputs showing that voice can fill.
  List<VoiceField> get fields => const [];

  /// Sends what the page has filled in, as its main button does. Null
  /// when the page has nothing to send.
  Future<void> Function()? get voiceSubmit => null;

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

  /// What an action may read right now: the current page and what it
  /// shows.
  static ActionContext context(VoiceRepositories repos,
      {required bool loggedIn}) {
    final screen = current;
    return ActionContext(
        repos: repos,
        loggedIn: loggedIn,
        entities: screen?.entities ?? const [],
        page: screen?.context);
  }
}
