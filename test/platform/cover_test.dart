import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/design/plan_viewer.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/platform/ui/theme.dart';
import 'package:yusal/platform/ui/widgets.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

void main() {
  Widget app(MockBackend b, Widget child) => MaterialApp(
      theme: buildPlatformTheme(YTokens.light),
      home: PlatformScope(
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
