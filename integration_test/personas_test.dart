// The one-tap test accounts on the dev sign-in, against a yusal-api run
// with DEV_LOGIN=true. Run like backend_flow_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/storage/project_store.dart';

import 'e2e_support.dart';

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('each test-account chip signs in with its role', (t) async {
    requireBackend();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yusal_api.refresh_token');
    await prefs.setString('house-lang', 'zh');
    AppSettings.instance.lang = AppLang.zh;
    final repos = HttpBackend(api);
    await repos.restore();
    await t.pumpWidget(RepaintBoundary(
        key: shotKey,
        child: ProviderScope(
            child: HouseApp(repos: repos, store: ProjectStore()))));
    await idle(t, 1000);

    Future<void> chip(String name) async {
      if (repos.currentAccount != null) await signOut(t, repos);
      await home(t);
      await tab(t, '我的');
      await tapIt(t, find.widgetWithText(FilledButton, '登录或注册'));
      final key = find.byKey(Key('test-login-$name'));
      await waitFor(t, key);
      await scrollTo(t, key);
      await tapIt(t, key);
      await waitFor(t, find.byTooltip('改称呼'));
      expect(repos.currentAccount?.displayName, name);
    }

    await chip('Test Owner');
    await shot(t, 't01-login-chips-owner');
    expect(await io(t, () => repos.myProfiles()), isEmpty);
    final ownerId = repos.currentAccount!.id;

    await chip('Test Owner 2');
    expect(repos.currentAccount!.id, isNot(ownerId));
    expect(await io(t, () => repos.myProfiles()), isEmpty);

    for (final pro in ['Test Worker', 'Test Contractor', 'Test Engineer']) {
      await chip(pro);
      expect(await io(t, () => repos.myProfiles()), isNotEmpty,
          reason: '$pro starts with a service profile');
    }

    await chip('Test Admin');
    expect(repos.currentAccount!.isAdmin, isTrue);
    await scrollTo(t, find.text('审核后台'));
    expect(find.text('审核后台'), findsOneWidget);
    await shot(t, 't02-admin-entry');

    await chip('Test Restricted');
    expect(repos.currentAccount!.restricted, isTrue);
    await signOut(t, repos);
    expect(t.takeException(), isNull);
  });
}
