import 'offline_speech.dart';
import 'read_aloud.dart';

/// No on-device voice on the web.
ReadAloud? createReadAloud() => null;

OfflineSpeech? createSpeech({required bool accurate}) => null;
