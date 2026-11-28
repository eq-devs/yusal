// The speaker on a reply and the voice download dialog, for visual review
// (not run in CI).
// SHOTS_OUT=/path flutter test test/ui_shots/read_aloud_shots_test.dart
import '../support/test_scope.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/features/voice/repository/voice_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_clock.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/features/shell/page.dart';
import 'package:yusal/service/voice/offline_speech.dart';

import '../storage_test.dart' show MemoryFiles;
import '../voice/read_aloud_test.dart' show FakeReader, FakeSpeech;
import 'editor_shots_test.dart' show loadFont;

const _reply = 'Екі қабатты, үш жатын бөлмелі үйдің жобасы дайын. '
    'Ауданы 156 шаршы метр.';

class KazakhVoice extends MockBackend implements VoiceBackend {
  KazakhVoice()
      : super(
            clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
            latency: Duration.zero,
            autoReviewDelay: Duration.zero);
  @override
  Future<VoiceTurn> say(
          {required String sessionId,
          required String text,
          required bool spoken,
          required Map<String, Object?> context}) async =>
      const VoiceTurn(reply: _reply);
  @override
  Future<VoiceTurn> results(
          {required String turnId,
          required List<Map<String, Object?>> results,
          required Map<String, Object?> context}) async =>
      const VoiceTurn(reply: _reply);
}

void main() {
  final out = Platform.environment['SHOTS_OUT'];
  setUpAll(() async {
    await loadFont('Inter', [
      for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Inter-$w.otf'
    ]);
    await loadFont('InterDisplay', ['assets/fonts/InterDisplay-600.otf']);
    final flutter = Platform.environment['FLUTTER_ROOT']!;
    await loadFont('MaterialIcons', [
      '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
  });

  testWidgets(skip: out == null, 'read aloud', (t) async {
    Directory(out!).createSync(recursive: true);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 40, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 40, bottom: 24);
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'voice-intro-seen': true});
    appLang = AppLang.kk;
    final reader = FakeReader();
    ReadAloud.instance = reader;
    OfflineSpeech.standard = FakeSpeech('', installed: true);
    OfflineSpeech.accurate = FakeSpeech('');
    final repos = KazakhVoice()..signInAs(SeedIds.owner);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: testApp(repos, store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();
    var shot = 0;
    Future<void> snap(String name) async {
      await t.pump(const Duration(milliseconds: 400));
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/${(++shot).toString().padLeft(2, '0')}_$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    await t.enterText(find.byKey(const Key('voice-input')), 'үй жобала');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    await snap('reply_with_speaker');
    await t.tap(find.byKey(const Key('voice-speak')));
    await t.pumpAndSettle();
    await snap('download_offer');
    await t.tap(find.byKey(const Key('voice-download-start')));
    await t.pump();
    await snap('downloading');
    await t.tap(find.byKey(const Key('voice-download-hide')));
    await t.pumpAndSettle();
    await snap('downloading_in_background');
    reader.phase.value = const VoiceModelStatus(VoiceModelPhase.installed);
    await t.pump();
    await snap('reading');
    await t.tap(find.byKey(const Key('voice-close')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ShellBarTab, 'Менің'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('me-voice')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('me-voice')));
    await t.pumpAndSettle();
    await snap('voice_settings');
    await t.tap(find.byKey(const Key('voice-stt-engine')));
    await t.pumpAndSettle();
    await snap('stt_choices');
    debugDefaultTargetPlatformOverride = null;
  });
}
