import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';

import 'explore_test.dart' show launch;

void main() {
  testWidgets('signing out asks first', (t) async {
    final (repos, _) = await launch(t, as: SeedIds.owner);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    final signOut = find.byKey(const Key('me-sign-out'));
    await t.scrollUntilVisible(signOut, 300,
        scrollable: find.byType(Scrollable).last);
    await t.tap(signOut);
    await t.pumpAndSettle();
    expect(find.text('退出登录？'), findsOneWidget);

    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(repos.currentAccount, isNotNull);

    await t.tap(signOut);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '退出'));
    await t.pumpAndSettle();
    expect(repos.currentAccount, isNull);
  });
}
