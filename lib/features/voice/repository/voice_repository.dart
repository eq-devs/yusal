import 'dart:async';
import 'dart:typed_data';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/features/voice/repository/speech.dart';
import 'package:yusal/features/voice/state/session.dart';

/// The assistant and speech, which yusal-api forwards to the AI gateway.

/// [VoiceBackend] over yusal-api.
mixin HttpVoiceRepository on ApiClient implements VoiceBackend, SpeechBackend {
  // Voice: yusal-api forwards both to the AI gateway.

  @override
  Future<VoiceTurn> say(
          {required String sessionId,
          required String text,
          required bool spoken,
          required Map<String, Object?> context}) async =>
      VoiceTurn.fromJson(await request('POST', '/client/voice',
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
      VoiceTurn.fromJson(await request('POST', '/client/voice/results',
          body: {
            'turn_id': turnId,
            'results': results,
            'context': context,
          },
          limit: _voiceTimeout) as Map<String, dynamic>);

  // Speech: yusal-api proxies QazSTT, which holds the key.

  @override
  Future<String> transcribe(Uint8List wav) async =>
      (await request('POST', '/client/voice/transcribe', bytes: wav)
          as Map<String, dynamic>)['text'] as String? ??
      '';

  /// [text] read aloud by the speech service, as WAV. The app shows
  /// replies as text; the live tests use this to make Kazakh recordings.
  Future<Uint8List> synthesize(String text) async {
    final res =
        await sendRaw('POST', '/client/voice/tts', body: {'text': text});
    if (res.statusCode != 200) ApiClient.decode(res);
    return res.bodyBytes;
  }
}
