import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

Widget _host(Widget child) => MaterialApp(home: Center(child: child));

void main() {
  testWidgets('a two-colour icon stacks its ink and its orange piece',
      (t) async {
    await t.pumpWidget(_host(const YusalIcon(YIcon.home, size: 32)));
    expect(find.byIcon(YIcon.home.ink!), findsOneWidget);
    expect(find.byIcon(YIcon.home.accent!), findsOneWidget);
    expect(t.getSize(find.byType(YusalIcon)), const Size.square(32));
  });

  testWidgets('mono draws the whole icon as one glyph', (t) async {
    await t.pumpWidget(_host(const YusalIcon(YIcon.home, mono: true)));
    expect(find.byIcon(YIcons.home), findsOneWidget);
    expect(find.byIcon(YIcon.home.accent!), findsNothing);
  });

  test('every icon has its own glyph, and layers only with an orange piece',
      () {
    final seen = <int>{};
    for (final i in YIcon.values) {
      expect(seen.add(i.glyph.codePoint), isTrue, reason: i.name);
      expect(i.glyph.fontFamily, 'YusalIcons');
      if (i.accent == null) expect(i.ink, isNull, reason: i.name);
    }
  });
}
