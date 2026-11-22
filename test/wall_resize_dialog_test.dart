import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/widgets/wall_length_dialog.dart';

void main() {
  testWidgets('a new wall length takes a sum and the end that stays',
      (t) async {
    WallResizeChoice? choice;
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async => choice =
                    await showDialog<WallResizeChoice>(
                        context: context,
                        builder: (_) => const WallResizeDialog(
                            initial: 3000, vertical: false, keepEnd: false)),
                child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text, '3.00');

    await t.enterText(find.byType(TextField), '0,1');
    await t.tap(find.text('确定'));
    await t.pump();
    expect(find.text('请输入 0.30 到 100 米'), findsOneWidget);

    await t.enterText(find.byType(TextField), '3,6+2,4');
    await t.tap(find.text('右端不动'));
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(choice, (length: 6000, keepEnd: true));
  });
}
