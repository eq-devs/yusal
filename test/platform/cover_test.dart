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

  testWidgets('a cover with a plan to draw never shows the placeholder icon',
      (t) async {
    final b = MockBackend(latency: Duration.zero);
    await t.pumpWidget(app(
        b,
        const Cover(
            icon: Icons.home_outlined, seed: 'a', child: SizedBox.shrink())));
    expect(find.byIcon(Icons.home_outlined), findsNothing);

    await t.pumpWidget(
        app(b, const Cover(icon: Icons.home_outlined, seed: 'a')));
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('a loaded plan cover draws in the first frame of a new copy',
      (t) async {
    final b = MockBackend(latency: Duration.zero);
    final post = (await b.feed(const FeedFilter()))
        .firstWhere((p) => p.snapshotId.isNotEmpty);
    Widget cover(Key key) => SizedBox(
        key: key,
        height: 200,
        child: PlanCover(snapshotId: post.snapshotId, postId: post.id));
    Finder plan() => find.descendant(
        of: find.byType(PlanCover), matching: find.byType(CustomPaint));

    await t.pumpWidget(app(b, cover(const ValueKey(1))));
    await t.pumpAndSettle();
    expect(plan(), findsOneWidget);

    // A new copy (the house page, or the flight's): drawn at once.
    await t.pumpWidget(app(b, cover(const ValueKey(2))));
    expect(plan(), findsOneWidget);
  });
}
