// End-to-end run of the app against a real yusal-api backend.
//
// Needs the API running with DEV_LOGIN=true, then on a simulator:
//   flutter test integration_test/backend_flow_test.dart -d <device> \
//     --dart-define=YUSAL_API=http://localhost:8080 \
//     --dart-define=YUSAL_DEV_LOGIN=true
// (Android emulator: YUSAL_API=http://10.0.2.2:8080.)
//
// Screenshots of key screens go to E2E_SHOTS, else the app's temp folder
// under `test-screens/`; the path is printed at the end.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/ui/home/post_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

const api = String.fromEnvironment('YUSAL_API');
const devLogin = bool.fromEnvironment('YUSAL_DEV_LOGIN');

/// Where screenshots go. On an iOS simulator this can be a folder on the
/// Mac, e.g. `--dart-define=E2E_SHOTS=$PWD/test-screens`.
const shotsDir = String.fromEnvironment('E2E_SHOTS');

final _shotKey = GlobalKey();
late Directory _shots;

/// Saves what is on screen as `<name>.png`.
Future<void> shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${_shots.path}/$name.png')
        .writeAsBytes(png!.buffer.asUint8List());
  });
}

/// Pumps until [finder] shows up (network calls finish off the test clock).
Future<void> waitFor(
  WidgetTester t,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

/// Lets in-flight requests finish, then settles.
Future<void> idle(WidgetTester t, [int ms = 600]) async {
  await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await t.pumpAndSettle();
}

Future<void> tapIt(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await idle(t);
}

Future<void> tab(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await idle(t);
}

Future<void> signIn(WidgetTester t, HttpBackend repos, String name) async {
  await tab(t, '我的');
  await tapIt(t, find.widgetWithText(FilledButton, '登录或注册'));
  await waitFor(t, find.byKey(const Key('dev-login-name')));
  await t.enterText(find.byKey(const Key('dev-login-name')), name);
  await tapIt(t, find.byKey(const Key('dev-login')));
  await waitFor(t, find.byTooltip('改称呼'));
  expect(repos.currentAccount?.displayName, name);
}

Future<void> signOut(WidgetTester t, HttpBackend repos) async {
  await tab(t, '我的');
  await t.scrollUntilVisible(find.text('退出登录'), 300,
      scrollable: find.byType(Scrollable).hitTestable().first);
  await tapIt(t, find.text('退出登录'));
  expect(repos.currentAccount, isNull);
}

/// Back to the shell's root, whatever is pushed on top.
Future<void> home(WidgetTester t) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r.isFirst);
  await idle(t);
}

Future<void> openPost(WidgetTester t, String title) async {
  await home(t);
  await tab(t, '发现');
  await waitFor(t, find.text(title));
  await tapIt(t, find.text(title).first);
  await waitFor(t, find.byType(PostPage));
  await idle(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign in, publish, feed, like, critique, reply, backup, rename', (
    t,
  ) async {
    expect(api, isNotEmpty, reason: 'run with --dart-define=YUSAL_API=...');
    expect(
      devLogin,
      isTrue,
      reason: 'run with --dart-define=YUSAL_DEV_LOGIN=true',
    );
    _shots = Directory(shotsDir.isEmpty
        ? '${Directory.systemTemp.path}/test-screens'
        : shotsDir)
      ..createSync(recursive: true);

    final run = DateTime.now().millisecondsSinceEpoch.toString();
    final ana = 'Ana $run', bek = 'Bek $run';
    final houseName = 'E2E 小屋 $run';
    final title = '给父母的一层砖房 $run';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yusal_api.refresh_token');
    await prefs.setString('house-lang', 'zh');
    AppSettings.instance.lang = AppLang.zh;
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);

    final store = ProjectStore();
    var seq = 0;
    final projectId = await store.createProject(
      createHouse(
        name: houseName,
        width: 10000,
        depth: 12000,
        columns: 2,
        rows: 1,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        newId: () => 'e2e_${seq++}',
      ),
    );

    final repos = HttpBackend(api);
    await repos.restore();
    expect(repos.currentAccount, isNull);

    try {
      await t.pumpWidget(
        RepaintBoundary(
          key: _shotKey,
          child: ProviderScope(
            child: HouseApp(repos: repos, store: store),
          ),
        ),
      );
      await idle(t, 1000);

      // ── Ana signs in and publishes her house ──
      await signIn(t, repos, ana);
      await shot(t, '01-signed-in-ana');
      final anaId = repos.currentAccount!.id;

      await tab(t, '我的房子');
      await waitFor(t, find.text(houseName));
      final row = find
          .ancestor(of: find.text(houseName), matching: find.byType(Row))
          .first;
      await tapIt(
        t,
        find.descendant(of: row, matching: find.byTooltip('项目操作')),
      );
      await tapIt(t, find.text('发布作品'));
      await t.enterText(find.byType(TextField).first, title);
      await t.pumpAndSettle();
      await shot(t, '02-publish-form');
      await tapIt(t, find.widgetWithText(FilledButton, '发布').last);
      await waitFor(t, find.byType(PostPage));
      await idle(t);
      await shot(t, '03-published-post');

      final mine = await t.runAsync(() => repos.myPosts());
      final post = mine!.firstWhere((p) => p.title == title);
      expect(post.ownerId, anaId);
      expect(post.projectId, projectId);
      final snap = await t.runAsync(() => repos.snapshot(post.snapshotId));
      expect(snap, isNotNull);
      expect(snap!.projectName, houseName);

      // ── It is on the feed ──
      await home(t);
      await tab(t, '发现');
      await waitFor(t, find.text(title));
      await shot(t, '04-feed');

      // ── Bek likes it and leaves a rated critique ──
      await signOut(t, repos);
      await signIn(t, repos, bek);
      await openPost(t, title);
      await tapIt(t, find.byTooltip('收藏').first);
      expect(await t.runAsync(() => repos.liked(post.id)), isTrue);
      expect(await t.runAsync(() => repos.likedPosts()), contains(post.id));

      final composer = find.byKey(const Key('critique-text'));
      await t.ensureVisible(composer);
      await t.pumpAndSettle();
      // Fourth star: rating 4.
      await t.tap(find.byIcon(Icons.star_border).at(3));
      await t.pumpAndSettle();
      await t.enterText(composer, '厨房可以再大一点 $run');
      await tapIt(t, find.byKey(const Key('critique-send')));
      await waitFor(t, find.text('厨房可以再大一点 $run'));
      await shot(t, '05-critique-by-bek');

      var comments = await t.runAsync(() => repos.comments(post.id));
      final critique = comments!.singleWhere((c) => c.text == '厨房可以再大一点 $run');
      expect(critique.rating, 4);
      final rated = await t.runAsync(() => repos.post(post.id));
      expect(rated!.likeCount, 1);
      expect(rated.ratingCount, 1);
      expect(rated.ratingSum, 4);

      // ── Ana replies and marks it helpful ──
      await home(t);
      await signOut(t, repos);
      await signIn(t, repos, ana);
      await openPost(t, title);
      await tapIt(t, find.byKey(Key('critique-reply-${critique.id}')));
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '好的，我改一下 $run',
      );
      await tapIt(t, find.widgetWithText(FilledButton, '确定'));
      await waitFor(t, find.text('好的，我改一下 $run'));
      await tapIt(t, find.byKey(Key('critique-helpful-${critique.id}')));
      // The page reloads and shows the mark as set.
      await waitFor(t, find.byIcon(Icons.thumb_up_alt));
      await shot(t, '06-reply-and-helpful');

      comments = await t.runAsync(() => repos.comments(post.id));
      expect(comments!.singleWhere((c) => c.id == critique.id).helpful, isTrue);
      final reply = comments.singleWhere((c) => c.text == '好的，我改一下 $run');
      expect(reply.parentId, critique.id);
      expect(reply.authorId, anaId);

      // ── Cloud backup from the backup page ──
      await home(t);
      await tab(t, '我的');
      await t.scrollUntilVisible(find.text('设计备份与恢复'), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await tapIt(t, find.text('设计备份与恢复'));
      await waitFor(t, find.text(houseName));
      final tile = find
          .ancestor(of: find.text(houseName), matching: find.byType(Column))
          .first;
      await tapIt(
        t,
        find.descendant(
          of: tile,
          matching: find.widgetWithText(OutlinedButton, '备份'),
        ),
      );
      await idle(t, 1000);
      await shot(t, '07-backup-list');
      final backups = await t.runAsync(() => repos.backups());
      final cloud = backups!.singleWhere((b) => b.projectId == projectId);
      expect(cloud.name, houseName);

      // ── A stale upload is refused, not overwritten ──
      final stale = await t.runAsync(() async {
        try {
          await repos.upload(
            projectId: projectId,
            name: houseName,
            houseText: cloud.houseText,
            designUpdatedAt: DateTime.now().toUtc().toIso8601String(),
            expectedPreviousUpdatedAt: '2000-01-01T00:00:00.000Z',
          );
          return null;
        } on ApiFailure catch (e) {
          return e.code;
        }
      });
      expect(stale, ApiCodes.conflict);
      final after = await t.runAsync(() => repos.backup(projectId));
      expect(after!.designUpdatedAt, cloud.designUpdatedAt);

      // ── The saved refresh token signs a fresh start back in ──
      final relaunch = HttpBackend(api);
      await t.runAsync(() => relaunch.restore());
      expect(relaunch.currentAccount?.id, anaId);

      // ── Rename ──
      await home(t);
      await tab(t, '我的');
      await t.scrollUntilVisible(find.byTooltip('改称呼'), -300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      await tapIt(t, find.byTooltip('改称呼'));
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await t.enterText(field, 'Ana 改名 $run');
      await tapIt(t, find.widgetWithText(FilledButton, '确定'));
      await waitFor(t, find.text('Ana 改名 $run'));
      await shot(t, '08-renamed');
      expect(repos.currentAccount?.displayName, 'Ana 改名 $run');
      // A later start reads the new name from the server.
      final again = HttpBackend(api);
      await t.runAsync(() => again.restore());
      expect(again.currentAccount?.displayName, 'Ana 改名 $run');

      // ignore: avoid_print
      print(
        'E2E_RUN=$run POST_ID=${post.id} ANA_ID=$anaId '
        'PROJECT_ID=$projectId SCREENS=${_shots.path}',
      );
      expect(t.takeException(), isNull);
    } catch (_) {
      await shot(t, 'zz-failure');
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await store.deleteProject(projectId);
      await LastOpenProject.write(previous);
    }
  });
}
