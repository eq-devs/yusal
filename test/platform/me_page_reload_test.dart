import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/me/me_page.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import '../storage_test.dart' show MemoryFiles;
import '../http_backend_test.dart' show FakeApi;

/// The fake API without thumbnails (its preview bytes are not an image).
class NoPreviewApi extends FakeApi {
  @override
  Future<http.Response> handle(http.Request r) async =>
      r.url.path.endsWith('/preview')
          ? http.Response('', 404)
          : super.handle(r);
}

class CountingBackend extends MockBackend {
  CountingBackend() : super(latency: Duration.zero);
  int myPostsCalls = 0;
  @override
  Future<List<HousePost>> myPosts() {
    myPostsCalls++;
    return super.myPosts();
  }
}

void main() {
  testWidgets('the me page loads my posts once, not in a loop', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final b = CountingBackend()..signInAs(SeedIds.owner);
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const MePage())));
    await t.pumpAndSettle();
    final settled = b.myPostsCalls;
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(b.myPostsCalls, settled, reason: 'no reloads without changes');
    expect(settled, lessThanOrEqualTo(2));
  });

  testWidgets('signed in against the API, my posts load once', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    SharedPreferences.setMockInitialValues({});
    final api = NoPreviewApi();
    final b = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
    await t.runAsync(() => b.signInWithProvider('google', 'id-token'));
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const MePage())));
    int calls() =>
        api.requests.where((r) => r.url.path == '/client/me/posts').length;
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 100));
    }
    final settled = calls();
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(calls(), settled, reason: 'no reloads without changes');
    expect(settled, lessThanOrEqualTo(2));
  });

  testWidgets('scrolled down on a phone, my posts do not reload in a loop',
      (t) async {
    AppSettings.instance.lang = AppLang.zh;
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = NoPreviewApi();
    final b = HttpBackend('https://api.test',
        client: MockClient((r) async {
          // A real network takes a while; the fake answers at once.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return api.handle(r);
        }),
        seed: false);
    await t.runAsync(() => b.signInWithProvider('google', 'id-token'));
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: const MePage())));
    Future<void> wait(int rounds) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    int calls() =>
        api.requests.where((r) => r.url.path == '/client/me/posts').length;
    await wait(20);
    // Scroll step by step to the bottom, as a person (or the test) does.
    for (var i = 0; i < 12; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await wait(4);
    }
    await wait(20);
    final settled = calls();
    await wait(40);
    expect(calls(), settled, reason: 'no reloads while nothing changes');
  });
}
