import 'dart:async';
import '../support/test_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/shared/ui/components.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/services/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

void main() {
  testWidgets('a stable provider avoids requests on parent rebuild', (t) async {
    final backend = MockBackend(latency: Duration.zero);
    final store = ProjectStore(fileSystem: MemoryFiles());
    var calls = 0;
    final load = FutureProvider.autoDispose.family<String, String>((_, key) {
      calls++;
      return key;
    });
    Widget page(String key) => MaterialApp(
        home: TestScope(
            repos: backend,
            store: store,
            child: Live<String>(
                provider: load(key), builder: (_, data) => Text(data))));
    await t.pumpWidget(page('first'));
    await t.pumpAndSettle();
    await t.pumpWidget(page('first'));
    await t.pumpAndSettle();
    expect(calls, 1);
    await t.pumpWidget(page('second'));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('a loading list shows a skeleton, never a spinner', (t) async {
    final backend = MockBackend(latency: Duration.zero);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final answer = Completer<String>();
    final load = FutureProvider.autoDispose<String>((_) => answer.future);
    Widget page({bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: TestScope(
                repos: backend,
                store: store,
                child: Scaffold(
                    body: Live<String>(
                        provider: load, builder: (_, data) => Text(data))))));
    await t.pumpWidget(page());
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // It breathes while waiting, and holds still under reduce motion.
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpWidget(page(reduceMotion: true));
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    answer.complete('done');
    await t.pumpAndSettle();
    expect(find.text('done'), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets('old request cannot overwrite new query', (t) async {
    final backend = MockBackend(latency: Duration.zero);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final first = Completer<String>();
    final second = Completer<String>();
    final load = FutureProvider.autoDispose.family<String, int>(
        (_, key) => key == 1 ? first.future : second.future);
    Widget page(int key) => MaterialApp(
        home: TestScope(
            repos: backend,
            store: store,
            child: Live<String>(
                provider: load(key), builder: (_, data) => Text(data))));
    await t.pumpWidget(page(1));
    await t.pumpWidget(page(2));
    second.complete('new');
    await t.pumpAndSettle();
    first.complete('old');
    await t.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('account change clears previous private data while loading',
      (t) async {
    final backend = MockBackend(latency: Duration.zero)
      ..signInAs(SeedIds.owner);
    final next = Completer<String>();
    var calls = 0;
    final load = FutureProvider.autoDispose<String>((_) {
      calls++;
      return calls == 1 ? Future.value('private owner') : next.future;
    });
    await t.pumpWidget(MaterialApp(
        home: TestScope(
            repos: backend,
            store: ProjectStore(fileSystem: MemoryFiles()),
            child: Live<String>(
                provider: load, builder: (_, data) => Text(data)))));
    await t.pumpAndSettle();
    expect(find.text('private owner'), findsOneWidget);
    backend.signInAs(SeedIds.mason);
    await t.pump();
    expect(find.text('private owner'), findsNothing);
    next.complete('mason');
    await t.pumpAndSettle();
    expect(find.text('mason'), findsOneWidget);
  });
}
