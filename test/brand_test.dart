import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/brand/brand.dart';

void main() {
  Widget host(Widget child, {bool dark = false}) => MaterialApp(
      theme: ThemeData(extensions: [dark ? YTokens.night : YTokens.light]),
      home: Center(child: child));

  testWidgets('the puzzle-house mark keeps its 22 : 24 box', (t) async {
    for (final h in [16.0, 56.0]) {
      await t.pumpWidget(host(YusalMark(height: h)));
      final size = t.getSize(find.byType(YusalMark));
      expect(size.height, h);
      expect(size.width, closeTo(h * 220 / 240, 0.01));
    }
  });

  testWidgets('the lockup draws in both themes and at small sizes',
      (t) async {
    for (final dark in [false, true]) {
      for (final h in [24.0, 40.0]) {
        await t.pumpWidget(host(YusalLogo(height: h), dark: dark));
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byType(YusalLogo)).height, h);
      }
    }
  });

  testWidgets('the tab icon takes its size from the icon theme', (t) async {
    await t.pumpWidget(host(const IconTheme(
        data: IconThemeData(size: 28, color: Colors.black),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          YusalMarkIcon(),
          YusalMarkIcon(selected: true),
        ]))));
    expect(t.getSize(find.byType(YusalMarkIcon).first), const Size(28, 28));
    expect(find.bySemanticsLabel('Yusal'), findsNothing);
  });
}
