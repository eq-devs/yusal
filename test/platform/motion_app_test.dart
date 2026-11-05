import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/motion/motion.dart';
import 'package:yusal/platform/ui/home/post_page.dart';
import '../widget_test.dart' show launch;

void main() {
  testWidgets('a feed card flies its cover into the house page and back',
      (t) async {
    await launch(t);
    final title = find.text('给父母盖的一层砖房');
    expect(title, findsWidgets);
    await t.tap(title.first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(t.takeException(), isNull);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(PostPage), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PostPage), matching: find.byType(HeroTarget)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(HeroTarget), matching: find.byType(Hero)),
        findsOneWidget);

    await t.pageBack();
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(t.takeException(), isNull);
    await t.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
  });

  testWidgets('a house opened without a touch has no flight', (t) async {
    await launch(t, route: '/h/${'nope'}');
    expect(find.byType(Hero), findsNothing);
  });
}
