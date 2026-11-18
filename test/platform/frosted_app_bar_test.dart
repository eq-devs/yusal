import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/ui/theme.dart';
import 'package:yusal/platform/ui/widgets.dart';

void main() {
  testWidgets('the frosted app bar covers the whole bar', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: buildPlatformTheme(YTokens.light),
        home: const Scaffold(
            extendBodyBehindAppBar: true,
            appBar: FrostedAppBar(title: Text('title')),
            body: SizedBox.expand())));
    final frost = find.descendant(
        of: find.byType(FrostedAppBar), matching: find.byType(ColoredBox));
    expect(t.getSize(frost.first).height,
        greaterThanOrEqualTo(kToolbarHeight));
  });
}
