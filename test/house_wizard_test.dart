import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/features/house_wizard.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/session.dart';
import 'package:yusal/voice/voice_overlay.dart';

import 'storage_test.dart' show MemoryFiles;
import 'voice/overlay_test.dart' show VoiceMock;
import 'voice/session_test.dart' show ScriptedBackend;

void main() {
  test('the wish reads as one sentence with a comma for decimals', () {
    const wish = HouseWish(
        width: 10.5, depth: 8, floors: 2, bedrooms: 4, bathrooms: 2);
    expect(wish.sentence(),
        '帮我设计一栋 10.5×8 米的 2 层房子：4 间卧室、2 个卫生间、客厅和厨房，还要门厅。每个房间都要有门，卧室、客厅和厨房要有窗。');
    AppSettings.instance.lang = AppLang.ru;
    addTearDown(() => AppSettings.instance.lang = AppLang.zh);
    expect(wish.sentence(), startsWith('Спроектируй дом 10,5×8 метров'));
  });

  testWidgets('the start sheet asks a few questions and hands them over',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    final backend = ScriptedBackend([const VoiceTurn(reply: '画好了。')]);
    await t.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => VoiceHost(
            navigator: navigator,
            repos: VoiceMock(backend),
            enabled: true,
            child: AppScope(child: child!)),
        home: HouseHome(store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });

    await t.tap(find.text('也可以从示例开始'));
    await t.pumpAndSettle();
    await t.tap(find.text('回答几个问题，帮我出一套'));
    await t.pumpAndSettle();
    expect(find.text('想要什么样的房子？'), findsOneWidget);

    // A size out of range is refused in place.
    await t.enterText(find.byType(TextField).first, '2');
    await t.ensureVisible(find.byKey(const Key('wizard-go')));
    await t.tap(find.byKey(const Key('wizard-go')));
    await t.pump();
    expect(find.text('长宽需在 3–100 米之间'), findsOneWidget);
    expect(backend.said, isEmpty);

    await t.enterText(find.byType(TextField).first, '9,5');
    await t.tap(find.byKey(const Key('wizard-floors-2')));
    await t.tap(find.byKey(const Key('wizard-bedrooms-4')));
    await t.tap(find.text('储藏间'));
    await t.tap(find.byKey(const Key('wizard-go')));
    await t.pumpAndSettle();

    expect(backend.said.single.text,
        '帮我设计一栋 9.5×10 米的 2 层房子：4 间卧室、1 个卫生间、客厅和厨房，还要门厅、锅炉房、储藏间。每个房间都要有门，卧室、客厅和厨房要有窗。');
    expect(backend.said.single.spoken, isFalse);
    // The answer shows beside the orb, as for a typed sentence.
    expect(find.text('画好了。'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('without the assistant the start sheet does not offer it',
      (t) async {
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => AppScope(child: child!),
        home: HouseHome(store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();
    await t.tap(find.text('也可以从示例开始'));
    await t.pumpAndSettle();
    expect(find.text('按长宽新建'), findsOneWidget);
    expect(find.text('回答几个问题，帮我出一套'), findsNothing);
  });
}
