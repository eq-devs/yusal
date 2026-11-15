import 'package:flutter/foundation.dart';

import '../app/settings.dart';
import '../platform/data/repositories.dart';
import 'action.dart';
import 'actions_design.dart';
import 'executor.dart';
import 'form.dart';
import 'screen.dart';

/// One action the language model asked the app to run.
class ActionCall {
  const ActionCall(this.id, this.action, this.args);
  final String id, action;
  final Map<String, Object?> args;
}

/// What the server sent back for one step of a turn: either actions to
/// run and report on ([turnId] set), or the final [reply].
class VoiceTurn {
  const VoiceTurn(
      {this.reply = '',
      this.turnId,
      this.calls = const [],
      this.options = const []});

  /// From `{reply, events}`; events this app does not know are ignored.
  factory VoiceTurn.fromJson(Map<String, dynamic> json) {
    String? turnId;
    var calls = const <ActionCall>[];
    var options = const <String>[];
    for (final e in (json['events'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      switch (e['type']) {
        case 'run_actions':
          turnId = e['turn_id'] as String?;
          calls = [
            for (final c in (e['calls'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
              ActionCall(
                  '${c['id']}',
                  '${c['action']}',
                  (c['args'] as Map?)?.cast<String, Object?>() ??
                      const <String, Object?>{})
          ];
        case 'options':
          options = [
            ...(e['options'] as List? ?? const []).whereType<String>()
          ];
      }
    }
    return VoiceTurn(
        reply: json['reply'] as String? ?? '',
        turnId: turnId,
        calls: calls,
        options: options);
  }

  final String reply;
  final String? turnId;
  final List<ActionCall> calls;

  /// Answers to offer as buttons when the reply is a question.
  final List<String> options;
}

/// The server side of a turn: yusal-api, which forwards to the AI
/// gateway.
abstract interface class VoiceBackend {
  Future<VoiceTurn> say(
      {required String sessionId,
      required String text,
      required bool spoken,
      required Map<String, Object?> context});

  Future<VoiceTurn> results(
      {required String turnId,
      required List<Map<String, Object?>> results,
      required Map<String, Object?> context});
}

enum VoicePhase { idle, thinking, acting, done, failed }

/// One line of the status bar's list of what was done.
class VoiceStep {
  const VoiceStep(this.action, this.result);
  final AppAction? action;
  final ActionResult result;
}

/// Failure codes of a turn as a whole.
abstract final class VoiceCodes {
  static const network = 'network';
  static const tooManySteps = 'too_many_steps';

  /// Reported for calls after a failed one in the same batch.
  static const skipped = 'skipped';
}

/// What the language model is told about the screen: the page, what it
/// shows under short aliases, its inputs, and the [actions] that can run
/// here right now. Ids stay in the app.
Map<String, Object?> voiceContext({List<String> actions = const []}) {
  final screen = VoiceScreens.current;
  return {
    'screen': screen?.screenId,
    'lang': AppSettings.instance.lang.name,
    'actions': actions,
    if (screen != null && screen.summary.isNotEmpty) 'summary': screen.summary,
    'entities': [
      for (final e in screen?.entities ?? const <Entity>[])
        {
          'kind': e.kind,
          'id': e.alias,
          if (e.title.isNotEmpty) 'title': e.title
        }
    ],
    'fields': [
      for (final f in screen?.fields ?? const <VoiceField>[])
        {
          'name': f.name,
          'type': f.type.name,
          if (f.values.isNotEmpty) 'values': f.values
        }
    ],
  };
}

/// Runs one sentence to its end: sends it, runs the actions the server
/// asks for, reports their results, and repeats until the reply. The
/// status bar listens to it.
class VoiceSession extends ChangeNotifier {
  VoiceSession(
      {required this.backend,
      required this.executor,
      required this.repos,
      required this.loggedIn,
      required this.sessionId});

  final VoiceBackend backend;
  final ActionExecutor executor;
  final PlatformRepositories repos;
  final bool Function() loggedIn;
  final String sessionId;

  /// The app's one session while its bar is up, for pages that hand it
  /// a sentence themselves.
  static VoiceSession? current;

  /// Batches of actions one sentence may run.
  static const maxSteps = 6;

  VoicePhase phase = VoicePhase.idle;
  String heard = '', reply = '';
  String? error;
  List<VoiceStep> steps = const [];
  List<String> options = const [];
  bool _stop = false;

  bool get busy => phase == VoicePhase.thinking || phase == VoicePhase.acting;

  /// Stops running further actions of the current sentence.
  void stop() => _stop = true;

  Future<void> say(String text, {required bool spoken}) async {
    if (busy) return;
    heard = text;
    reply = '';
    error = null;
    steps = const [];
    options = const [];
    _stop = false;
    _set(VoicePhase.thinking);

    // Everything one sentence changes in a design undoes as one step.
    final Object? screen = VoiceScreens.current;
    final design = screen is DesignHost ? screen : null;
    design?.beginUndoGroup();
    try {
      var turn = await backend.say(
          sessionId: sessionId,
          text: text,
          spoken: spoken,
          context: _context());
      for (var step = 0; turn.turnId != null; step++) {
        if (step == maxSteps) {
          error = VoiceCodes.tooManySteps;
          return _set(VoicePhase.failed);
        }
        _set(VoicePhase.acting);
        final results = await _run(turn.calls);
        _set(VoicePhase.thinking);
        turn = await backend.results(
            turnId: turn.turnId!, results: results, context: _context());
      }
      reply = turn.reply;
      options = turn.options;
      _set(VoicePhase.done);
    } catch (e) {
      error = e is ApiFailure ? e.code : VoiceCodes.network;
      _set(VoicePhase.failed);
    } finally {
      design?.endUndoGroup();
    }
  }

  Map<String, Object?> _context() => voiceContext(actions: [
        for (final a in executor.registry
            .offered(VoiceScreens.context(repos, loggedIn: loggedIn())))
          a.id
      ]);

  /// Runs a batch in order. After a failure, or once the user stops it,
  /// the rest are reported as skipped.
  Future<List<Map<String, Object?>>> _run(List<ActionCall> calls) async {
    final out = <Map<String, Object?>>[];
    var halted = false;
    for (final call in calls) {
      final result = halted || _stop
          ? const ActionResult.fail(VoiceCodes.skipped)
          : await executor.run(call.action, call.args,
              VoiceScreens.context(repos, loggedIn: loggedIn()),
              source: Source.voice);
      halted = halted || !result.ok;
      steps = [...steps, VoiceStep(executor.registry[call.action], result)];
      notifyListeners();
      out.add({
        'id': call.id,
        'ok': result.ok,
        if (!result.ok) 'code': result.code,
        if (result.say.isNotEmpty) 'say': result.say,
      });
    }
    return out;
  }

  void _set(VoicePhase next) {
    phase = next;
    notifyListeners();
  }
}
