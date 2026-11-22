// The press bloom at three moments, for visual review (not run in CI).
// SHOTS_OUT=/path flutter test test/ui_shots/press_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/shared/ui/components.dart';
import 'package:yusal/shared/theme/theme.dart';

import 'editor_shots_test.dart' show loadFont;

void main() {
  final out = Platform.environment['SHOTS_OUT'];
  setUpAll(() async {
    await loadFont('Inter', [
      for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Inter-$w.otf'
    ]);
    final flutter = Platform.environment['FLUTTER_ROOT']!;
    await loadFont('MaterialIcons', [
      '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
  });

  for (final tokens in [YTokens.light, YTokens.night]) {
    testWidgets(skip: out == null, 'press ${tokens.dark ? 'night' : 'light'}',
        (t) async {
      Directory(out!).createSync(recursive: true);
      t.view.physicalSize = const Size(412, 360);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildPlatformTheme(tokens),
              home: Scaffold(
                  body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        SettingsGroup(children: [
                          SettingsRow(
                              key: const Key('row'),
                              icon: Icons.language,
                              title: 'Тіл',
                              value: 'Қазақша',
                              onTap: () {}),
                          SettingsRow(
                              icon: Icons.brightness_6_outlined,
                              title: 'Көрініс',
                              onTap: () {}),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  key: const Key('outlined'),
                                  onPressed: () {},
                                  child: const Text('Болдырмау'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: FilledButton(
                                  key: const Key('filled'),
                                  onPressed: () {},
                                  child: const Text('Сақтау'))),
                          IconButton(
                              key: const Key('icon'),
                              onPressed: () {},
                              icon: const Icon(Icons.favorite_border)),
                        ]),
                      ]))))));
      await t.pumpAndSettle();
      final name = tokens.dark ? 'night' : 'light';
      Future<void> snap(String label) async {
        final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/${name}_$label.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
      }

      final row = t.getRect(find.byKey(const Key('row')));
      final gestures = [
        await t.startGesture(row.centerLeft + const Offset(90, 0)),
        await t.startGesture(
            t.getRect(find.byKey(const Key('outlined'))).centerRight -
                const Offset(30, 0)),
        await t.startGesture(t.getCenter(find.byKey(const Key('filled')))),
        await t.startGesture(t.getCenter(find.byKey(const Key('icon')))),
      ];
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await snap('1_50ms');
      await t.pump(const Duration(milliseconds: 60));
      await snap('2_110ms');
      await t.pump(const Duration(milliseconds: 200));
      await snap('3_held');
      for (final g in gestures) {
        await g.up();
      }
      await t.pumpAndSettle();
    });
  }
}
