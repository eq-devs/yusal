import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where replies are turned into sound.
enum TtsEngine {
  /// On the phone (qazvoice); needs its one-time download.
  device,

  /// By the speech server, through yusal-api; needs a network.
  server,
}

/// Where a recording is turned into text.
enum SttEngine {
  /// By the speech server, through yusal-api.
  server,

  /// On the phone, standard model.
  device,

  /// On the phone, the more accurate and slower model.
  deviceAccurate,
}

/// The user's choices for voice, kept across launches.
class VoiceSettings extends ChangeNotifier {
  VoiceSettings._();
  static final instance = VoiceSettings._();

  static const speeds = [0.75, 1.0, 1.25, 1.5];

  TtsEngine tts = TtsEngine.device;
  SttEngine stt = SttEngine.server;

  /// Which of the phone's voices reads.
  int voice = 0;
  double speed = 1.0;

  /// Read every reply without a tap on the speaker.
  bool autoRead = false;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString('voice-tts');
      final s = p.getString('voice-stt');
      tts = TtsEngine.values.where((e) => e.name == t).firstOrNull ?? tts;
      stt = SttEngine.values.where((e) => e.name == s).firstOrNull ?? stt;
      voice = p.getInt('voice-speaker') ?? voice;
      speed = p.getDouble('voice-speed') ?? speed;
      autoRead = p.getBool('voice-auto-read') ?? autoRead;
    } catch (_) {
      /* Storage unavailable: keep the defaults. */
    }
    notifyListeners();
  }

  void _save(Future<bool> Function(SharedPreferences p) write) {
    notifyListeners();
    SharedPreferences.getInstance().then(write).catchError((_) => false);
  }

  void setTts(TtsEngine v) {
    tts = v;
    _save((p) => p.setString('voice-tts', v.name));
  }

  void setStt(SttEngine v) {
    stt = v;
    _save((p) => p.setString('voice-stt', v.name));
  }

  void setVoice(int v) {
    voice = v;
    _save((p) => p.setInt('voice-speaker', v));
  }

  void setSpeed(double v) {
    speed = v;
    _save((p) => p.setDouble('voice-speed', v));
  }

  void setAutoRead(bool v) {
    autoRead = v;
    _save((p) => p.setBool('voice-auto-read', v));
  }
}
