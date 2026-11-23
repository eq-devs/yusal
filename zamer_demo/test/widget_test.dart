import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zamer/main.dart';

void main() {
  testWidgets('demo room solves and shows the suspect wall', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    await t.pumpWidget(const ZamerApp());
    await t.tap(find.text('看示例房间'));
    await t.pumpAndSettle();
    expect(find.textContaining('很可能量错了'), findsOneWidget);
    expect(
        find.textContaining('原始走线终点'), findsNothing); // painted, not a widget
    await t.tap(find.text('返回修改'));
    await t.pumpAndSettle();
    expect(find.text('自动闭合'), findsWidgets);
  });

  testWidgets('sketch, simulate laser, solve', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    await t.pumpWidget(const ZamerApp());
    final canvas = find.byKey(const Key('plan'));
    final tl = t.getTopLeft(canvas);
    for (final o in const [
      Offset(60, 60),
      Offset(260, 62),
      Offset(262, 220),
      Offset(58, 218),
      Offset(61, 61)
    ]) {
      await t.tapAt(tl + o);
      await t.pump();
    }
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('模拟测距仪'));
      await t.pump();
    }
    await t.tap(find.text('自动闭合'));
    await t.pumpAndSettle();
    expect(find.text('面积'), findsOneWidget);
  });
}
