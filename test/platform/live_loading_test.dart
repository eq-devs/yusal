import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

void main() {
  testWidgets('stable reload key avoids requests on parent rebuild', (t) async {
    final backend = MockBackend(latency: Duration.zero);
    final store = ProjectStore(fileSystem: MemoryFiles());
    var calls = 0;
    Widget page(String key) => MaterialApp(
        home: PlatformScope(
            repos: backend,
            store: store,
            child: Live<String>(
                reloadKey: key,
                load: (_) async {
                  calls++;
                  return key;
                },
                builder: (_, data) => Text(data))));
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

  testWidgets('old request cannot overwrite new query', (t) async {
    final backend = MockBackend(latency: Duration.zero);
    final store = ProjectStore(fileSystem: MemoryFiles());
    final first = Completer<String>(), second = Completer<String>();
    Widget page(int key) => MaterialApp(
        home: PlatformScope(
            repos: backend,
            store: store,
            child: Live<String>(
                reloadKey: key,
                load: (_) => key == 1 ? first.future : second.future,
                builder: (_, data) => Text(data))));
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
    await t.pumpWidget(MaterialApp(
        home: PlatformScope(
            repos: backend,
            store: ProjectStore(fileSystem: MemoryFiles()),
            child: Live<String>(
                reloadKey: 'private',
                load: (_) {
                  calls++;
                  return calls == 1
                      ? Future.value('private owner')
                      : next.future;
                },
                builder: (_, data) => Text(data)))));
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
