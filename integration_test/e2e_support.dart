// Helpers for the integration tests that drive the app against a running
// yusal-api (see backend_flow_test.dart for how to run them).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/ui/demand/demand_detail_page.dart';
import 'package:yusal/platform/ui/demand/publish_page.dart';
import 'package:yusal/platform/ui/profile/profile_edit_page.dart';

const api = String.fromEnvironment('YUSAL_API');
const devLogin = bool.fromEnvironment('YUSAL_DEV_LOGIN');

/// Where screenshots go. On an iOS simulator this can be a folder on the
/// Mac, e.g. `--dart-define=E2E_SHOTS=$PWD/test-screens`.
const shotsDir = String.fromEnvironment('E2E_SHOTS');

/// Wrap the app in a RepaintBoundary with this key so [shot] can capture it.
final shotKey = GlobalKey();

Directory shotsFolder() => Directory(
    shotsDir.isEmpty ? '${Directory.systemTemp.path}/test-screens' : shotsDir)
  ..createSync(recursive: true);

void requireBackend() {
  expect(api, isNotEmpty, reason: 'run with --dart-define=YUSAL_API=...');
  expect(devLogin, isTrue,
      reason: 'run with --dart-define=YUSAL_DEV_LOGIN=true');
}

/// Saves what is on screen as `<name>.png`.
Future<void> shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${shotsFolder().path}/$name.png')
        .writeAsBytes(png!.buffer.asUint8List());
  });
}

/// Pumps until [finder] shows up (network calls finish off the test clock).
Future<void> waitFor(WidgetTester t, Finder finder,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
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
  // A toast from the previous step can float over the bottom of the page.
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    for (final m in find.byType(ScaffoldMessenger).evaluate()) {
      (m as StatefulElement).state is ScaffoldMessengerState
          ? (m.state as ScaffoldMessengerState).clearSnackBars()
          : null;
    }
    await t.pumpAndSettle();
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await idle(t);
}

/// Scrolls the topmost scrollable until [f] is built, then taps it.
Future<void> scrollTap(WidgetTester t, Finder f, {double delta = 300}) async {
  await scrollTo(t, f, delta: delta);
  await tapIt(t, f);
}

Future<void> scrollTo(WidgetTester t, Finder f, {double delta = 300}) async {
  if (f.evaluate().isNotEmpty) return;
  await t.scrollUntilVisible(f, delta,
      scrollable: find.byType(Scrollable).hitTestable().first);
}

Future<void> tab(WidgetTester t, String label) async {
  await t.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await idle(t);
}

/// Back to the shell's root, whatever is pushed on top.
Future<void> home(WidgetTester t) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r.isFirst);
  await idle(t);
}

/// Pushes [page] on the root navigator, as the app's own links do.
Future<void> open(WidgetTester t, Widget page) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => page));
  await idle(t);
}

Future<void> signIn(WidgetTester t, HttpBackend repos, String name) async {
  if (repos.currentAccount != null) await signOut(t, repos);
  await home(t);
  await tab(t, '我的');
  await tapIt(t, find.widgetWithText(FilledButton, '登录或注册'));
  await waitFor(t, find.byKey(const Key('dev-login-name')));
  await t.enterText(find.byKey(const Key('dev-login-name')), name);
  await tapIt(t, find.byKey(const Key('dev-login')));
  await waitFor(t, find.byTooltip('改称呼'));
  expect(repos.currentAccount?.displayName, name);
}

Future<void> signOut(WidgetTester t, HttpBackend repos) async {
  await home(t);
  await tab(t, '我的');
  await scrollTap(t, find.text('退出登录'));
  expect(repos.currentAccount, isNull);
}

/// Types into the text field of the open dialog and presses 确定.
Future<void> answerDialog(WidgetTester t, String text) async {
  await t.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      text);
  await tapIt(t, find.widgetWithText(FilledButton, '确定'));
}

/// Picks [label] in a pickMany sheet and presses 完成.
Future<void> pickManyOne(WidgetTester t, String label) async {
  await tapIt(t, find.text(label).last);
  await tapIt(t, find.text('完成'));
}

/// Creates a mason profile in Almaty through the profile form.
Future<void> createProfile(WidgetTester t, String name) async {
  await home(t);
  await open(t, const ProfileEditPage());
  await waitFor(t, find.text('创建接活名片'));
  await t.enterText(find.widgetWithText(TextField, '姓名'), name);
  await tapIt(t, find.text('工种').first);
  await pickManyOne(t, '瓦工／砌墙');
  await tapIt(t, find.text('服务地区').first);
  await pickManyOne(t, '阿拉木图');
  await tapIt(t, find.widgetWithText(FilledButton, '保存'));
  await idle(t, 1000);
}

/// Publishes a demand through the wizard: a contract by default, or a hire
/// of [headcount] masons at [wage] ₸ a day. Ends on its detail page.
Future<void> publishDemand(WidgetTester t, String title,
    {bool hire = false, int headcount = 1, int wage = 15000}) async {
  await home(t);
  await open(t, const PublishPage());
  await waitFor(t, find.text('下一步'));
  if (hire) await tapIt(t, find.text('招人干活'));
  await tapIt(t, find.text('下一步'));
  await tapIt(t, find.text('工种').first);
  await pickManyOne(t, '瓦工／砌墙');
  await tapIt(t, find.text('地区').first);
  await tapIt(t, find.text('阿拉木图').last);
  if (hire) {
    final people = find.widgetWithText(TextField, '需要人数');
    await scrollTo(t, people);
    await t.enterText(people, '$headcount');
    final pay = find.widgetWithText(TextField, '工资（₸）');
    await scrollTo(t, pay);
    await t.enterText(pay, '$wage');
  }
  final titleField = find.widgetWithText(TextField, '标题');
  await scrollTo(t, titleField);
  await t.enterText(titleField, title);
  await t.pumpAndSettle();
  for (var i = 0; i < 6 && find.text('提交发布').evaluate().isEmpty; i++) {
    await tapIt(t, find.text('下一步'));
  }
  await tapIt(t, find.text('提交发布'));
  await waitFor(t, find.byType(DemandDetailPage));
}
