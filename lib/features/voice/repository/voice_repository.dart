import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/features/voice/repository/speech.dart';

/// The assistant and speech, which yusal-api forwards to the AI gateway.

/// The assistant; the app's also turns speech into text.
final voiceRepositoryProvider =
    Provider<VoiceBackend>((ref) => HttpVoiceRepository(ApiClient.app));

/// [VoiceBackend] over yusal-api.
final class HttpVoiceRepository
    implements VoiceBackend, SpeechBackend, SpeechSynth {
  HttpVoiceRepository(this.api);
  final ApiClient api;

  // Voice: yusal-api forwards both to the AI gateway.

  @override
  Future<VoiceTurn> say(
          {required String sessionId,
          required String text,
          required bool spoken,
          required Map<String, Object?> context}) async =>
      VoiceTurn.fromJson(await api.request('POST', '/client/voice',
          body: {
            'session_id': sessionId,
            'text': text,
            'input': spoken ? 'voice' : 'text',
            'context': context,
          },
          limit: _voiceTimeout) as Map<String, dynamic>);

  /// Designing a whole house takes the AI a minute or two.
  static const _voiceTimeout = Duration(seconds: 150);

  @override
  Future<VoiceTurn> results(
          {required String turnId,
          required List<Map<String, Object?>> results,
          required Map<String, Object?> context}) async =>
      VoiceTurn.fromJson(await api.request('POST', '/client/voice/results',
          body: {
            'turn_id': turnId,
            'results': results,
            'context': context,
          },
          limit: _voiceTimeout) as Map<String, dynamic>);

  // Speech: yusal-api proxies QazSTT, which holds the key.

  @override
  Future<String> transcribe(Uint8List wav) async =>
      (await api.request('POST', '/client/voice/transcribe', bytes: wav)
          as Map<String, dynamic>)['text'] as String? ??
      '';

  /// [text] read aloud by the speech service, as WAV.
  @override
  Future<Uint8List> synthesize(String text, {double speed = 1.0}) async {
    final res = await api.sendRaw('POST', '/client/voice/tts',
        body: {'text': text, if (speed != 1.0) 'speed': speed});
    if (res.statusCode != 200) ApiClient.decode(res);
    return res.bodyBytes;
  }
}

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
