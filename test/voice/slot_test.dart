import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/motion/motion.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/session.dart';
import 'package:yusal/voice/voice_overlay.dart';

import '../storage_test.dart' show MemoryFiles;
import 'overlay_test.dart' show VoiceMock;
import 'session_test.dart' show ScriptedBackend;

void main() {
  final orb = find.byKey(const Key('voice-button'));

  Future<GlobalKey<NavigatorState>> pump(WidgetTester t, Widget home,
      {List<Object> script = const [], bool introSeen = true}) async {
    SharedPreferences.setMockInitialValues(
        {if (introSeen) 'voice-intro-seen': true});
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(
            child: VoiceHost(
                navigator: navigator,
                repos: VoiceMock(ScriptedBackend([...script])),
                enabled: true,
                child: child!)),
        home: home));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    return navigator;
  }

  testWidgets('the orb sits on the place a page keeps for it', (t) async {
    final navigator = await pump(
        t,
        const Scaffold(
            body: Align(
                alignment: Alignment(0.5, -0.8), child: VoiceSlot(size: 44))),
        script: [const VoiceTurn(reply: '好的。')],
        introSeen: false);
    final slot = t.getRect(find.byType(VoiceSlot));
    expect(slot.size, const Size(44, 44));
    expect(t.getRect(orb), slot);
    // No introduction over a page that keeps a slot.
    expect(find.byKey(const Key('voice-intro')), findsNothing);

    // What it says opens below a slot in the top half of the screen.
    await t.tap(orb);
    await t.pump();
    await t.enterText(find.byKey(const Key('voice-input')), '你好');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    final bubble = t.getRect(find.byKey(const Key('voice-bar')));
    expect(bubble.top, greaterThanOrEqualTo(slot.top));
    expect(bubble.right, lessThan(slot.left));
    await t.tap(find.byKey(const Key('voice-close')));
    await t.pumpAndSettle();

    // Under another page the slot does not count: back to the corner.
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next'))));
    await t.pumpAndSettle();
    final corner = t.getRect(orb);
    expect(corner.size, const Size(52, 52));
    expect(corner.bottom, 600 - 96);
    navigator.currentState!.pop();
    await t.pumpAndSettle();
    expect(t.getRect(orb), slot);
    expect(t.takeException(), isNull);
  });

  testWidgets('the orb steps aside while a sheet is open', (t) async {
    final navigator = await pump(t, const Scaffold(body: Text('page')));
    expect(orb, findsOneWidget);
    final sheet = showMotionSheet<void>(
        context: navigator.currentContext!,
        builder: (_) => const SizedBox(height: 300, child: Text('sheet')));
    await t.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(orb, findsNothing);
    navigator.currentState!.pop();
    await sheet;
    await t.pumpAndSettle();
    expect(orb, findsOneWidget);
  });

  for (final size in [
    const Size(390, 844),
    const Size(360, 640),
    const Size(844, 390),
    const Size(1180, 820)
  ])
    testWidgets('in the editor at $size the orb covers no tool', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var n = 0;
      final doc =
          createKazakhTemplate('2026-11-17T00:00:00Z', () => 'id${n++}');
      await pump(
          t,
          HouseEditor(
              entry: ProjectEntry('project', doc),
              store: ProjectStore(fileSystem: MemoryFiles())));
      final at = t.getRect(orb);
      expect(at, t.getRect(find.byType(VoiceSlot)));
      // Every button and the drawing are clear of it.
      for (final finder in [
        find.byType(IconButton),
        find.byType(BackButton),
        find.byType(PopupMenuButton<String>),
        find.byType(TextButton),
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is FloorPlanPainter),
      ])
        for (final e in finder.evaluate()) {
          if (find
              .ancestor(of: find.byWidget(e.widget), matching: find.byType(VoiceBar))
              .evaluate()
              .isNotEmpty) continue;
          final box = e.renderObject! as RenderBox;
          if (!box.hasSize || box.size.isEmpty) continue;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.overlaps(at.deflate(4)), isFalse,
              reason: '${e.widget.runtimeType} at $rect under the orb $at');
        }
      expect(t.takeException(), isNull);
    });
}
