// Screens of the create-house flow with the voice orb over them, for
// visual review (not run in CI).
// SHOTS_OUT=/path flutter test test/ui_shots/editor_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/app/tokens.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/features/editor/house_editor.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/session.dart';
import 'package:yusal/voice/voice_overlay.dart';

import '../storage_test.dart' show MemoryFiles;
import '../voice/overlay_test.dart' show VoiceMock;
import '../voice/session_test.dart' show ScriptedBackend;

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

final shotKey = GlobalKey();

void main() {
  final out = Platform.environment['SHOTS_OUT'];
  final lang =
      AppLang.values.byName(Platform.environment['SHOTS_LANG'] ?? 'zh');
  final introSeen = Platform.environment['SHOTS_INTRO'] != '1';
  final sizeEnv = (Platform.environment['SHOTS_SIZE'] ?? '390x844').split('x');
  final size = Size(double.parse(sizeEnv[0]), double.parse(sizeEnv[1]));
  setUpAll(() async {
    await loadFont('Inter', [
      for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Inter-$w.otf'
    ]);
    await loadFont('InterDisplay', [
      for (final w in [600, 700]) 'assets/fonts/InterDisplay-$w.otf'
    ]);
    await loadFont('JetBrainsMono', [
      'assets/fonts/JetBrainsMono-Regular.ttf',
      'assets/fonts/JetBrainsMono-SemiBold.ttf'
    ]);
    final flutter = Platform.environment['FLUTTER_ROOT']!;
    await loadFont('MaterialIcons', [
      '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
    const cjk = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
    if (File(cjk).existsSync()) await loadFont('Noto Sans SC', [cjk]);
  });

  testWidgets(skip: out == null, 'screens', (t) async {
    Directory(out!).createSync(recursive: true);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    // A phone with a home indicator and a status bar.
    t.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    t.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues(
        {if (introSeen) 'voice-intro-seen': true});
    AppSettings.instance.lang = lang;
    addTearDown(() => AppSettings.instance.lang = AppLang.zh);

    var shot = 0;
    Future<void> snap(String name) async {
      await t.pump(const Duration(milliseconds: 400));
      final boundary =
          t.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/${(++shot).toString().padLeft(2, '0')}_$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    final navigator = GlobalKey<NavigatorState>();
    final backend = ScriptedBackend([
      const VoiceTurn(reply: '已经把客厅北墙加了一扇窗。还需要调整别的吗？', options: ['再加一扇', '不用了'])
    ]);
    var n = 0;
    final store = ProjectStore(fileSystem: MemoryFiles());
    final doc = createKazakhTemplate('2026-11-17T00:00:00Z', () => 'id${n++}');
    final id = await store.createProject(doc);
    final direct = size.width > size.height;
    await t.pumpWidget(RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
            navigatorKey: navigator,
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Tokens.light),
            builder: (context, child) => AppScope(
                child: VoiceHost(
                    navigator: navigator,
                    repos: VoiceMock(backend),
                    child: child!)),
            home: direct
                ? HouseEditor(entry: ProjectEntry(id, doc), store: store)
                : HouseHome(store: store))));
    await t.pumpAndSettle();
    await snap('home');

    Future<void> tapIf(Finder f) async {
      if (f.evaluate().isEmpty) {
        // ignore: avoid_print
        print('MISSING ${f.describeMatch(Plurality.one)}');
        return;
      }
      await t.tap(f.first, warnIfMissed: false);
      await t.pumpAndSettle();
    }

    // The editor.
    if (!direct) await tapIf(find.text(doc.meta.name));
    await snap('editor_plan');

    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    Offset at(double x, double y) {
      final painter =
          t.widget<CustomPaint>(canvas.first).painter! as FloorPlanPainter;
      return t.getTopLeft(canvas.first) +
          painter.point(x, y, t.getSize(canvas.first));
    }

    // A room selected: its card.
    await t.tapAt(at(doc.footprint.width * 0.3, doc.footprint.depth * 0.3));
    await t.pumpAndSettle();
    await snap('editor_room_selected');
    await t.tapAt(at(doc.footprint.width * 0.7, doc.footprint.depth * 0.75));
    await t.pumpAndSettle();
    await snap('editor_room2_selected');

    for (final tip in ['墙体', '家具', '更多工具']) {
      await tapIf(find.byTooltip(tip));
      await snap('editor_tool_$tip');
      if (tip == '更多工具') {
        navigator.currentState!.maybePop();
        await t.pumpAndSettle();
      }
    }
    for (final tab in [
      'ext',
      'walk',
      'det',
      'qty',
      'cost',
      'build',
      'iss',
      'plan'
    ]) {
      final f = find.byKey(ValueKey('tab-$tab'));
      if (f.evaluate().isEmpty) continue;
      await t.ensureVisible(f);
      await tapIf(f);
      await snap('editor_tab_$tab');
    }

    // The orb in use: typing, then an answer with options.
    await tapIf(find.byKey(const Key('voice-button')));
    await snap('voice_typing');
    await t.enterText(find.byKey(const Key('voice-input')), '客厅北墙加一扇窗');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    await snap('voice_answer');
  });
}
