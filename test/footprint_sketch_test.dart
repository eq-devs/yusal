import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/footprint_sketch.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('outline sketch fits $size and accepts exact dimensions',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: FootprintSketch()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '12');
      await tester.enterText(find.byType(TextField).last, '10');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('outline drawing preserves the initial corner', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FootprintSketch()));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('footprint-sketch-canvas'));
    final size = tester.getSize(canvas), origin = tester.getTopLeft(canvas);
    final scale = math.min(size.width - 48, size.height - 48) / 20000;
    final start = origin + const Offset(30, 30);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + Offset(12000 * scale, 10000 * scale));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '12.00');
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '10.00');
    expect(tester.takeException(), isNull);
  });
}
