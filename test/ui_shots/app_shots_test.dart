// The app's main pages with the voice orb over them, for visual review
// (not run in CI).
// SHOTS_OUT=/path flutter test test/ui_shots/app_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/main.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_clock.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/features/shell/shell.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/session.dart';

import '../storage_test.dart' show MemoryFiles;
import 'editor_shots_test.dart' show loadFont;

class SeededVoice extends MockBackend implements VoiceBackend {
  SeededVoice()
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
      const VoiceTurn(reply: '好的。');
  @override
  Future<VoiceTurn> results(
          {required String turnId,
          required List<Map<String, Object?>> results,
          required Map<String, Object?> context}) async =>
      const VoiceTurn(reply: '好的。');
}

void main() {
  final out = Platform.environment['SHOTS_OUT'];
  setUpAll(() async {
    await loadFont('Onest', [
      for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Onest-$w.ttf'
    ]);
    await loadFont('Lora',
        [for (final w in [500, 600, 700]) 'assets/fonts/Lora-$w.ttf']);
    await loadFont('PlexMono', [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-SemiBold.ttf'
    ]);
    final flutter = Platform.environment['FLUTTER_ROOT']!;
    await loadFont('MaterialIcons', [
      '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
    const cjk = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
    if (File(cjk).existsSync()) await loadFont('Noto Sans SC', [cjk]);
  });

  testWidgets(skip: out == null, 'pages', (t) async {
    Directory(out!).createSync(recursive: true);
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 40, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 40, bottom: 24);
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'voice-intro-seen': true});
    final repos = SeededVoice()..signInAs(SeedIds.owner);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: ProviderScope(
            child: HouseApp(
                repos: repos,
                store: ProjectStore(fileSystem: MemoryFiles())))));
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

    for (final label in ['发现', '我的房子', '消息', '我的']) {
      await t.tap(find.widgetWithText(ShellBarTab, label));
      await t.pumpAndSettle();
      await snap('tab_$label');
    }
    // A conversation, with its input at the bottom.
    await t.tap(find.widgetWithText(ShellBarTab, '消息'));
    await t.pumpAndSettle();
    final rows = find.byType(ListTile);
    if (rows.evaluate().isNotEmpty) {
      await t.tap(rows.first);
      await t.pumpAndSettle();
      await snap('chat');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      await snap('chat_keyboard');
      t.view.viewInsets = FakeViewPadding.zero;
    }
  });
}
