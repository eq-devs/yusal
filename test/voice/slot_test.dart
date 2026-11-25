import 'package:flutter/material.dart';
import '../support/mock/backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/features/editor/widgets/editor_kit.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/shared/motion/motion.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/features/voice/state/session.dart';
import 'package:yusal/features/voice/widgets/voice_overlay.dart';

import '../storage_test.dart' show MemoryFiles;
import '../tabs.dart';
import 'overlay_test.dart' show VoiceMock, VoicePage;
import 'session_test.dart' show ScriptedBackend;

void main() {
  final orb = find.byKey(const Key('voice-button'));

  Future<GlobalKey<NavigatorState>> pump(WidgetTester t, Widget home,
      {List<Object> script = const [],
      bool introSeen = true,
      bool signedIn = true}) async {
    SharedPreferences.setMockInitialValues(
        {if (introSeen) 'voice-intro-seen': true});
    final navigator = GlobalKey<NavigatorState>();
    final mock = VoiceMock(ScriptedBackend([...script]), signedIn: signedIn);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => VoiceHost(
                navigator: navigator,
                repos: voiceRepos(mock),
                voice: mock,
                child: child!),
            home: home)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const ProviderScope(child: SizedBox.shrink()));
      await t.pumpAndSettle();
    });
    return navigator;
  }

  testWidgets('the orb sits on the place a page keeps for it', (t) async {
    final navigator = await pump(
        t,
        const VoicePage(
            child: Align(alignment: Alignment(0.5, -0.8), child: VoiceSlot())),
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
    expect(bubble.top, greaterThan(slot.bottom));
    expect(t.getRect(orb), slot);
    await t.tap(find.byKey(const Key('voice-close')));
    await t.pumpAndSettle();

    // Under another page of its own the slot does not count: the corner.
    navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const VoicePage()));
    await t.pumpAndSettle();
    final corner = t.getRect(orb);
    expect(corner.size, const Size(52, 52));
    expect(corner.bottomRight, const Offset(800 - 16, 600 - 20));
    navigator.currentState!.pop();
    await t.pumpAndSettle();
    expect(t.getRect(orb), slot);
    expect(t.takeException(), isNull);
  });

  testWidgets('what it says opens above a slot at the bottom', (t) async {
    await pump(
        t,
        const VoicePage(
            child: Align(
                alignment: Alignment(0, 0.9), child: VoiceSlot(size: 48))),
        script: [const VoiceTurn(reply: '好的。')]);
    final slot = t.getRect(find.byType(VoiceSlot));
    expect(t.getRect(orb), slot);
    await t.tap(orb);
    await t.pump();
    await t.enterText(find.byKey(const Key('voice-input')), '你好');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const Key('voice-bar'))).bottom,
        lessThan(slot.top));
    expect(t.getRect(orb), slot);
  });

  testWidgets('the orb shows only where the assistant has something to do',
      (t) async {
    final navigator = await pump(t, const VoicePage());
    expect(orb, findsOneWidget);

    // A page with no contract (settings, a picture): no orb.
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('settings'))));
    await t.pumpAndSettle();
    expect(orb, findsNothing);
    navigator.currentState!.pop();
    await t.pumpAndSettle();
    expect(orb, findsOneWidget);

    // A dialog over the page: no orb either.
    showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('sure?')));
    await t.pumpAndSettle();
    expect(orb, findsNothing);
    navigator.currentState!.pop();
    await t.pumpAndSettle();
    expect(orb, findsOneWidget);
  });

  testWidgets("the orb is away while the page's keyboard is up", (t) async {
    await pump(t, const VoicePage());
    addTearDown(t.view.reset);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.pumpAndSettle();
    expect(orb, findsNothing);
    t.view.viewInsets = FakeViewPadding.zero;
    await t.pumpAndSettle();
    expect(orb, findsOneWidget);

    // Typing to the assistant itself keeps it, above the keyboard.
    await t.tap(orb);
    await t.pump();
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('voice-input')), findsOneWidget);
    // 300 physical pixels of keyboard are 100 logical ones here.
    expect(t.getRect(orb).bottom, 600 - 100 - 12);
  });

  testWidgets('the orb steps aside while a sheet is open', (t) async {
    final navigator = await pump(t, const VoicePage());
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

  testWidgets('signed out, a slot takes no room', (t) async {
    await pump(t, const VoicePage(child: Center(child: VoiceSlot())),
        signedIn: false);
    expect(orb, findsNothing);
    expect(t.getSize(find.byType(VoiceSlot)), Size.zero);
  });

  testWidgets('in the 3D view on a phone the orb covers no switch', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var n = 0;
    final doc = createKazakhTemplate('2026-11-17T00:00:00Z', () => 'id${n++}');
    await pump(
        t,
        HouseEditor(
            entry: ProjectEntry('project', doc),
            store: ProjectStore(fileSystem: MemoryFiles())));
    for (final tab in ['ext', 'walk']) {
      await openTab(t, tab);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      final at = t.getRect(orb);
      expect(at, t.getRect(find.byType(VoiceSlot)), reason: tab);
      for (final finder in [
        find.byType(IconButton),
        find.byType(PillToggle),
        find.byType(ActionChip),
        find.byType(Btn),
      ]) {
        for (final e in finder.evaluate()) {
          final box = e.renderObject! as RenderBox;
          var rect = box.localToGlobal(Offset.zero) & box.size;
          // Only the part its scrolling row shows.
          final row = Scrollable.maybeOf(e)?.context.findRenderObject();
          if (row is RenderBox) {
            rect = rect.intersect(row.localToGlobal(Offset.zero) & row.size);
          }
          expect(rect.overlaps(at.deflate(4)), isFalse,
              reason: '$tab: ${e.widget.runtimeType} at $rect under $at');
        }
      }
    }
  });

  for (final size in [
    const Size(390, 844),
    const Size(360, 640),
    const Size(844, 390),
    const Size(820, 1180),
    const Size(1180, 820)
  ]) {
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
      ]) {
        for (final e in finder.evaluate()) {
          if (find
              .ancestor(
                  of: find.byWidget(e.widget), matching: find.byType(VoiceBar))
              .evaluate()
              .isNotEmpty) {
            continue;
          }
          final box = e.renderObject! as RenderBox;
          if (!box.hasSize || box.size.isEmpty) continue;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.overlaps(at.deflate(4)), isFalse,
              reason: '${e.widget.runtimeType} at $rect under the orb $at');
        }
      }
      expect(t.takeException(), isNull);
    });
  }
}
