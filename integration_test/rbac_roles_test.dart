// RBAC through the real app: each back-office role signs in with the dev
// sign-in, and the test checks what the app shows it (the admin entry, the
// account actions, the console rows) against what the backend lets the same
// session do. A superadmin outside the app changes roles mid-session.
//
// Needs a yusal-api with DEV_LOGIN=true and DEV_ADMIN=true on a throwaway
// database (the "Test Admin" dev persona must be a superadmin):
//
//   flutter test integration_test/rbac_roles_test.dart -d <simulator> \
//     --dart-define=YUSAL_API=http://localhost:8090
//
// Never point it at a shared server: it grants and revokes roles and bans an
// account. It also uninstalls the app from the device when it finishes, so
// use a simulator without real data. Prints one `RBAC_UI|id|result|detail`
// line per check (ALLOWED / DENIED / FAILED).
import '../test/support/test_scope.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/features/admin/page.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/storage/last_open.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'e2e_support.dart';

final _failures = <String>[];

void rbac(String id, bool ok, String allowedOrDenied, String detail) {
  final result = ok ? allowedOrDenied : 'FAILED';
  if (!ok) _failures.add('$id: $detail');
  // ignore: avoid_print
  print('RBAC_UI|$id|$result|$detail');
}

bool shown(String text) => find.text(text).evaluate().isNotEmpty;

/// A signed-in account driven over plain HTTP, outside the app.
class Raw {
  Raw._(this.id, this.token);
  final String id;
  final String token;

  static Future<Raw> signIn(String name) async {
    final res = await http.post(Uri.parse('$api/auth/oauth/dev'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': name}));
    final d = (jsonDecode(res.body) as Map)['data'] as Map;
    return Raw._(
        (d['user'] as Map)['id'] as String, d['access_token'] as String);
  }

  Future<(int, String)> call(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$api$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    final code = ((jsonDecode(res.body) as Map)['code'] as String?) ?? '';
    return (res.statusCode, code);
  }

  Future<void> grant(String accountId, String role) async {
    final (status, code) =
        await call('PUT', '/admin/users/$accountId/role', {'role': role});
    expect(status, 200, reason: 'grant $role: $code');
  }
}

Future<String> attempt(WidgetTester t, Future<Object?> Function() f) async =>
    (await t.runAsync(() async {
      try {
        await f();
        return 'OK';
      } on ApiFailure catch (e) {
        return e.code;
      } catch (e) {
        return 'ERR ${e.runtimeType}';
      }
    }))!;

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

const _restrict = '限制账号';
const _setRole = '设置后台角色';
const _ban = '封禁';
const _delete = '注销账号';
const _broadcast = '群发通知';
const _exportUsers = '导出用户表';
const _noAccess = '没有后台权限';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RBAC: each role in the app matches the backend', (t) async {
    requireBackend();
    final run = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('house-lang', 'zh');
    appLang = AppLang.zh;
    await LastOpenProject.write(null);

    final root = await io(t, () => Raw.signIn('Test Admin'));
    final (rootStatus, _) = await io(t, () => root.call('GET', '/admin/me'));
    expect(rootStatus, 200,
        reason: 'the Test Admin persona must be a superadmin (DEV_ADMIN=true)');
    final target = await io(t, () => Raw.signIn('RBAC Target $run'));

    final repos = TestHttp(api);
    await repos.api.restore();
    await t.pumpWidget(RepaintBoundary(
        key: shotKey, child: testApp(repos, store: ProjectStore())));
    await idle(t, 1000);

    // What each role should see and be allowed, from user/role.go.
    final cases = <(String, String?, Set<String>)>[
      ('user', null, {}),
      ('viewer', 'viewer', {'read'}),
      ('operator', 'operator', {'read', 'operate'}),
      ('moderator', 'moderator', {'read', 'moderate'}),
      ('superadmin', 'superadmin', {'read', 'moderate', 'operate', 'team'}),
    ];

    for (final (label, role, perms) in cases) {
      final name = 'RBAC ${label[0].toUpperCase()}${label.substring(1)} $run';
      final raw = await io(t, () => Raw.signIn(name));
      if (role != null) await io(t, () => root.grant(raw.id, role));
      await signIn(t, repos, name);

      // ── the Me tab's back-office entry ──
      await home(t);
      await tab(t, '我的');
      await idle(t);
      final entry = find.byKey(const Key('me-admin'));
      if (role != null) await scrollTo(t, entry);
      final hasEntry = entry.evaluate().isNotEmpty;
      rbac('UI:$label:me-admin-entry', hasEntry == perms.contains('read'),
          hasEntry ? 'ALLOWED' : 'DENIED', hasEntry ? 'shown' : 'hidden');
      await shot(t, 'rbac-$label-me');

      // ── backend parity for the same session, through the app's client ──
      final read = await attempt(t, repos.admin.todo);
      rbac(
          'API:$label:GET /admin/todo',
          (read == 'OK') == perms.contains('read'),
          read == 'OK' ? 'ALLOWED' : 'DENIED',
          read);
      final ban = await attempt(
          t,
          () =>
              repos.admin.setBanned('0123456789abcdef01234567', true, 'rbac'));
      final banAllowed = ban != ApiCodes.forbidden;
      rbac(
          'API:$label:POST /admin/accounts/:id/ban',
          banAllowed == perms.contains('moderate'),
          banAllowed ? 'ALLOWED' : 'DENIED',
          ban);
      final export = await attempt(t, () => repos.admin.export('users'));
      rbac(
          'API:$label:GET /admin/export/users',
          (export == 'OK') == perms.contains('team'),
          export == 'OK' ? 'ALLOWED' : 'DENIED',
          export);
      final grant =
          await attempt(t, () => repos.admin.setRole(target.id, 'viewer'));
      rbac(
          'API:$label:PUT /admin/users/:id/role',
          (grant == 'OK') == perms.contains('team'),
          grant == 'OK' ? 'ALLOWED' : 'DENIED',
          grant);
      if (grant == 'OK') await io(t, () => root.grant(target.id, ''));

      // A user without a role who opens the console by a deep link gets
      // the lock screen, not the console.
      await open(t, const AdminPage());
      await idle(t, 800);
      final locked = shown(_noAccess);
      rbac('UI:$label:admin-deep-link', locked == !perms.contains('read'),
          locked ? 'DENIED' : 'ALLOWED', locked ? 'lock screen' : 'console');
      if (!perms.contains('read')) {
        await signOut(t, repos);
        continue;
      }

      // ── the console's More tab ──
      await tapIt(t, find.text('更多').last);
      await idle(t, 800);
      await scrollTo(t, find.byKey(const Key('admin-banned-words')));
      final hasBroadcast = shown(_broadcast);
      rbac(
          'UI:$label:more-broadcast',
          hasBroadcast == perms.contains('operate'),
          hasBroadcast ? 'ALLOWED' : 'DENIED',
          hasBroadcast ? 'shown' : 'hidden');
      final hasExport = shown(_exportUsers);
      rbac('UI:$label:more-export', hasExport == perms.contains('team'),
          hasExport ? 'ALLOWED' : 'DENIED', hasExport ? 'shown' : 'hidden');
      await shot(t, 'rbac-$label-more');

      // ── account actions on an ordinary account ──
      await open(t, AccountDetailPage(accountId: target.id));
      await waitFor(t, find.text('RBAC Target $run'));
      await idle(t, 800);
      for (final (button, perm) in [
        (_restrict, 'moderate'),
        (_ban, 'moderate'),
        (_setRole, 'team'),
        (_delete, 'team'),
      ]) {
        final has =
            find.widgetWithText(OutlinedButton, button).evaluate().isNotEmpty;
        rbac('UI:$label:account-$button', has == perms.contains(perm),
            has ? 'ALLOWED' : 'DENIED', has ? 'shown' : 'hidden');
      }
      await shot(t, 'rbac-$label-account');
      await signOut(t, repos);
    }

    // ── role changes while signed in ──
    final live = await io(t, () => Raw.signIn('RBAC Live $run'));
    await io(t, () => root.grant(live.id, 'viewer'));
    await signIn(t, repos, 'RBAC Live $run');
    await open(t, AccountDetailPage(accountId: target.id));
    await waitFor(t, find.text('RBAC Target $run'));

    // Promotion: the backend lets the session moderate at once; the app
    // shows the new buttons only after it re-reads the account.
    await io(t, () => root.grant(live.id, 'moderator'));
    final promoted = await attempt(t,
        () => repos.admin.setBanned('0123456789abcdef01234567', true, 'rbac'));
    rbac('SESS:promote-backend-immediate', promoted != ApiCodes.forbidden,
        'ALLOWED', promoted);
    await idle(t, 800);
    final staleUi =
        !find.widgetWithText(OutlinedButton, _restrict).evaluate().isNotEmpty;
    // ignore: avoid_print
    print('RBAC_UI|SESS:promote-ui-before-sync|${staleUi ? 'STALE' : 'FRESH'}|'
        'restrict button ${staleUi ? 'hidden until the account is re-read' : 'shown'}');
    await t.runAsync(repos.api.syncSession);
    await idle(t, 1200);
    await open(t, AccountDetailPage(accountId: target.id));
    await waitFor(t, find.text('RBAC Target $run'));
    final freshUi =
        find.widgetWithText(OutlinedButton, _restrict).evaluate().isNotEmpty;
    rbac('SESS:promote-ui-after-sync', freshUi, 'ALLOWED',
        freshUi ? 'restrict button shown' : 'still hidden');

    // Demotion: the backend refuses at once; the console closes once the
    // app re-reads the account.
    await open(t, const AdminPage());
    await io(t, () => root.grant(live.id, ''));
    final demoted = await attempt(t, repos.admin.todo);
    rbac('SESS:demote-backend-immediate', demoted == ApiCodes.forbidden,
        'DENIED', demoted);
    final consoleStillOpen = !shown(_noAccess);
    // ignore: avoid_print
    print(
        'RBAC_UI|SESS:demote-ui-before-sync|${consoleStillOpen ? 'STALE' : 'FRESH'}|'
        'console ${consoleStillOpen ? 'still open until the account is re-read' : 'closed'}');
    await t.runAsync(repos.api.syncSession);
    await idle(t, 1200);
    final closed = shown(_noAccess);
    rbac('SESS:demote-ui-after-sync', closed, 'DENIED',
        closed ? 'lock screen' : 'console still open');
    await shot(t, 'rbac-live-demoted');

    // Suspension: the backend refuses the session; a sync signs it out.
    final (banStatus, banCode) = await io(
        t,
        () => root.call('POST', '/admin/accounts/${live.id}/ban',
            {'banned': true, 'note': 'rbac'}));
    expect(banStatus, 200, reason: banCode);
    final afterBan = await attempt(t, repos.notifications.unreadNotifications);
    rbac('SESS:banned-backend-immediate', afterBan != 'OK', 'DENIED', afterBan);
    await t.runAsync(repos.api.syncSession);
    await idle(t, 1200);
    final signedOut = repos.api.currentAccount == null;
    rbac('SESS:banned-signed-out-on-sync', signedOut, 'DENIED',
        signedOut ? 'signed out' : 'still signed in');
    await io(
        t,
        () => root.call('POST', '/admin/accounts/${live.id}/ban',
            {'banned': false, 'note': 'rbac'}));

    expect(_failures, isEmpty, reason: _failures.join('\n'));
  });
}
