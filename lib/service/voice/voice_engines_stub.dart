import 'package:yusal/service/voice/offline_speech.dart';
import 'package:yusal/service/voice/read_aloud.dart';

/// No on-device voice on the web.
ReadAloud? createReadAloud() => null;

OfflineSpeech? createSpeech({required bool accurate}) => null;
