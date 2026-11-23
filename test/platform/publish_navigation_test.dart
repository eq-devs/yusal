import 'dart:async';
import '../support/test_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/home/pages/post.dart';
import 'package:yusal/features/home/pages/publish_post.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/service/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

class DelayedPublication extends MockBackend {
  DelayedPublication() : super(latency: Duration.zero);
  final release = Completer<void>();
  int submissions = 0;
  @override
  Future<HousePost> publishPost(HousePost post) async {
    submissions++;
    await release.future;
    return super.publishPost(post);
  }
}

void main() {
  testWidgets(
      'back during publication cannot leave a submitted form underneath detail',
      (t) async {
    appLang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final backend = DelayedPublication()..signInAs(SeedIds.owner);
    final store = ProjectStore(fileSystem: MemoryFiles());
    var seq = 0;
    final doc = createHouse(
        name: '发布导航测试',
        width: 10000,
        depth: 13000,
        columns: 1,
        rows: 1,
        timestamp: '2026-11-04T00:00:00Z',
        newId: () => 'nav_${seq++}');
    final id = await store.createProject(doc);
    await t.pumpWidget(TestScope(
        repos: backend,
        store: store,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => pushPage<void>(
                            context,
                            (_) =>
                                PublishPostPage(entry: ProjectEntry(id, doc))),
                        child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '新的公开作品');
    await t.tap(find.text('发布'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(backend.submissions, 1);
    await t.pageBack();
    await t.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PublishPostPage), findsOneWidget);
    backend.release.complete();
    await t.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);
    expect(find.byType(PublishPostPage), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(backend.submissions, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('publishing defaults to asking for feedback with chosen topics',
      (t) async {
    appLang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final backend = MockBackend(latency: Duration.zero)
      ..signInAs(SeedIds.owner);
    final store = ProjectStore(fileSystem: MemoryFiles());
    var seq = 0;
    final doc = createHouse(
        name: '求点评测试',
        width: 10000,
        depth: 12000,
        columns: 1,
        rows: 1,
        timestamp: '2026-11-04T00:00:00Z',
        newId: () => 'fb_${seq++}');
    final id = await store.createProject(doc);
    await t.pumpWidget(TestScope(
        repos: backend,
        store: store,
        child:
            MaterialApp(home: PublishPostPage(entry: ProjectEntry(id, doc)))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('focus-layout')));
    await t.tap(find.byKey(const Key('focus-cost')));
    await t.pump();
    await t.enterText(find.byType(TextField).first, '想听听意见');
    await t.tap(find.text('发布'));
    await t.pumpAndSettle();
    final post = backend.posts.values.singleWhere((p) => p.title == '想听听意见');
    expect(post.openForBuilders, isFalse);
    expect(post.focus, ['layout', 'cost']);
    expect(find.byKey(const Key('feedback-ask')), findsOneWidget);
  });
}
