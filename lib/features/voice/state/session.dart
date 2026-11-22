import 'package:flutter/foundation.dart';

import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/services/api/api_failure.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/model/form.dart';
import 'package:yusal/features/voice/state/screen.dart';

/// One action the language model asked the app to run.
class ActionCall {
  const ActionCall(this.id, this.action, this.args);
  final String id;
  final String action;
  final Map<String, Object?> args;
}

/// What the server sent back for one step of a turn: either actions to
/// run and report on ([turnId] set), or the final [reply].
class VoiceTurn {
  const VoiceTurn(
      {this.reply = '',
      this.turnId,
      this.calls = const [],
      this.options = const [],
      this.brief = const {}});

  /// From `{reply, events}`; events this app does not know are ignored.
  factory VoiceTurn.fromJson(Map<String, dynamic> json) {
    String? turnId;
    var calls = const <ActionCall>[];
    var options = const <String>[];
    var brief = const <String, Object?>{};
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
        case 'brief':
          brief = (e['brief'] as Map?)?.cast<String, Object?>() ?? const {};
      }
    }
    return VoiceTurn(
        reply: json['reply'] as String? ?? '',
        turnId: turnId,
        calls: calls,
        options: options,
        brief: brief);
  }

  final String reply;
  final String? turnId;
  final List<ActionCall> calls;

  /// Answers to offer as buttons when the reply is a question.
  final List<String> options;

  /// What is known so far of the house being asked about: `width_m`,
  /// `depth_m`, `area_m2`, `floors`, `bedrooms`, `entrance`, `notes`.
  final Map<String, Object?> brief;
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
    if (screen != null && screen.scene.isNotEmpty) 'scene': screen.scene,
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
  final VoiceRepositories repos;
  final bool Function() loggedIn;
  final String sessionId;

  /// The app's one session while its bar is up, for pages that hand it
  /// a sentence themselves.
  static VoiceSession? current;

  /// Batches of actions one sentence may run.
  static const maxSteps = 6;

  VoicePhase phase = VoicePhase.idle;
  String heard = '';
  String reply = '';
  String? error;
  List<VoiceStep> steps = const [];
  List<String> options = const [];
  Map<String, Object?> brief = const {};
  bool _stop = false;

  /// A sentence said while another was running; it runs next.
  (String, bool)? _next;

  bool get busy => phase == VoicePhase.thinking || phase == VoicePhase.acting;

  /// Stops running further actions of the current sentence.
  void stop() => _stop = true;

  /// Runs [text] to its end. Said while another sentence is running, it
  /// interrupts that one: no further actions of it run, its reply is
  /// dropped, and [text] starts as soon as the step in flight returns.
  Future<void> say(String text, {required bool spoken}) async {
    if (busy) {
      _stop = true;
      _next = (text, spoken);
      heard = text;
      return notifyListeners();
    }
    await _say(text, spoken: spoken);
    while (_next != null) {
      final (text, spoken) = _next!;
      _next = null;
      await _say(text, spoken: spoken);
    }
  }

  Future<void> _say(String text, {required bool spoken}) async {
    heard = text;
    reply = '';
    error = null;
    steps = const [];
    options = const [];
    brief = const {};
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
        if (_next != null) return;
        if (step == maxSteps) {
          error = VoiceCodes.tooManySteps;
          return _set(VoicePhase.failed);
        }
        _set(VoicePhase.acting);
        final results = await _run(turn.calls);
        if (_next != null) return;
        _set(VoicePhase.thinking);
        turn = await backend.results(
            turnId: turn.turnId!, results: results, context: _context());
      }
      if (_next != null) return;
      reply = turn.reply;
      options = turn.options;
      brief = turn.brief;
      _set(VoicePhase.done);
    } catch (e) {
      if (_next != null) return;
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
      // Under the names the model knows them by; what was removed has
      // none any more.
      final entities = VoiceScreens.current?.entities ?? const <Entity>[];
      final changed = [
        for (final id in result.changed)
          for (final e in entities)
            if (e.id == id) e.alias
      ];
      out.add({
        'id': call.id,
        'ok': result.ok,
        if (!result.ok) 'code': result.code,
        if (result.say.isNotEmpty) 'say': result.say,
        if (changed.isNotEmpty) 'changed': changed,
      });
    }
    return out;
  }

  void _set(VoicePhase next) {
    phase = next;
    notifyListeners();
  }
}
