// The one-tap test accounts on the dev sign-in, against a yusal-api run
// with DEV_LOGIN=true and DEV_ADMIN=true, filled by yusal-api
// tool/seed/seed.py. Run like backend_flow_test.dart.
import '../test/support/test_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/storage/project_store.dart';

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
    final repos = TestHttp(api);
    await repos.api.restore();
    await t.pumpWidget(RepaintBoundary(
        key: shotKey, child: testApp(repos, store: ProjectStore())));
    await idle(t, 1000);

    Future<void> chip(String key, String name) async {
      if (repos.api.currentAccount != null) await signOut(t, repos);
      await home(t);
      await tab(t, '我的');
      await tapIt(
          t, find.widgetWithText(FilledButton, '登录或注册').hitTestable().first);
      final chip = find.byKey(Key('test-login-$key'));
      await waitFor(t, chip);
      await scrollTo(t, chip);
      await tapIt(t, chip);
      await waitFor(t, find.byTooltip('改称呼'));
      expect(repos.api.currentAccount?.displayName, name);
    }

    await chip('Test Owner', 'Test Owner');
    await shot(t, 't01-login-chips-owner');
    expect(await io(t, repos.profiles.myProfiles), isEmpty);

    await chip('seed:aigerim', 'Айгерім Сейтқали');
    expect(await io(t, repos.profiles.myProfiles), isEmpty);

    for (final (key, name) in [
      ('seed:bolat', 'Болат Жұмабеков'),
      ('seed:nurlan', 'Нұрлан Сәрсенбаев'),
      ('seed:gulnar', 'Гүлнар Омарова'),
    ]) {
      await chip(key, name);
      expect(await io(t, repos.profiles.myProfiles), isNotEmpty,
          reason: '$name has a service profile');
    }

    await chip('Test Admin', 'Test Admin');
    expect(repos.api.currentAccount!.role, isNotNull);
    await shot(t, 't02-admin-entry');

    await chip('seed:moderator', 'Әлия · модератор');
    expect(repos.api.currentAccount!.role, 'moderator');

    await chip('seed:spam', 'Стройбаза Опт');
    expect(repos.api.currentAccount!.restricted, isTrue);
    await signOut(t, repos);
    expect(t.takeException(), isNull);
  });
}
