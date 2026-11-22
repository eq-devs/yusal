import 'package:flutter/material.dart';
import '../support/test_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/mock/mock_backend.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/features/home/widgets/plan_viewer.dart';
import 'package:yusal/shared/theme/theme.dart';
import 'package:yusal/shared/ui/widgets.dart';
import 'package:yusal/services/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

void main() {
  Widget app(MockBackend b, Widget child) => MaterialApp(
      theme: buildPlatformTheme(YTokens.light),
      home: TestScope(
          repos: b,
          store: ProjectStore(fileSystem: MemoryFiles()),
          child: Scaffold(body: child)));

  testWidgets('a loaded plan cover draws in the first frame of a new copy',
      (t) async {
    final b = MockBackend(latency: Duration.zero);
    final post = (await b.feed(const FeedFilter()))
        .firstWhere((p) => p.snapshotId.isNotEmpty);
    Widget coverX() => Cover(
        icon: Icons.home_outlined,
        seed: post.id,
        height: 200,
        child: PlanCover(snapshotId: post.snapshotId, postId: post.id));
    // Loose width, as in a feed card's start-aligned column.
    Widget cover(Key key) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [coverX()]);
    Finder plan() => find.descendant(
        of: find.byType(PlanCover), matching: find.byType(CustomPaint));

    await t.pumpWidget(app(b, cover(const ValueKey(1))));
    await t.pumpAndSettle();
    expect(plan(), findsOneWidget);
    // It fills the cover, over the placeholder.
    expect(t.getSize(plan()), const Size(800, 200));

    // A new copy (the house page, or the flight's): drawn at once.
    await t.pumpWidget(app(b, cover(const ValueKey(2))));
    expect(plan(), findsOneWidget);
    expect(t.getSize(plan()), const Size(800, 200));
  });
}
