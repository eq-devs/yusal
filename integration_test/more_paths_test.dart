// More of the work platform against a running yusal-api (DEV_LOGIN=true,
// MANUAL_REVIEW off): managing a demand from its page (share link and
// revoking it, pause, resume, renew, close), a worker's favourites, an
// itemised quote, searching for workers, restoring a cloud backup to the
// device, and deleting an account. Run like backend_flow_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/apply/apply_page.dart';
import 'package:yusal/platform/ui/backup/backup_page.dart';
import 'package:yusal/platform/ui/cards.dart';
import 'package:yusal/platform/ui/demand/demand_detail_page.dart';
import 'package:yusal/platform/ui/demand/share_page.dart';
import 'package:yusal/platform/ui/me/me_page.dart';
import 'package:yusal/platform/ui/profile/profile_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

import 'e2e_support.dart';

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

Future<void> openDemand(WidgetTester t, String id) async {
  await home(t);
  await open(t, DemandDetailPage(demandId: id));
  await waitFor(t, find.byType(DemandDetailPage));
  await idle(t, 800);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'manage a demand, favourites, itemised quote, worker search, '
      'backup restore, account deletion', (t) async {
    requireBackend();
    final run = DateTime.now().millisecondsSinceEpoch.toString();
    final owner = 'Olga $run', worker = 'Wang $run';
    final title = '屋面翻新 $run';
    final houseName = '恢复测试 $run';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yusal_api.refresh_token');
    await prefs.setString('house-lang', 'zh');
    AppSettings.instance.lang = AppLang.zh;
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);

    final store = ProjectStore();
    final repos = HttpBackend(api);
    await repos.restore();
    final created = <String>[];
    try {
      await t.pumpWidget(RepaintBoundary(
          key: shotKey,
          child: ProviderScope(child: HouseApp(repos: repos, store: store))));
      await idle(t, 1000);

      // ── Setup: a worker with a profile, an owner with an open demand ──
      await signIn(t, repos, worker);
      final workerId = repos.currentAccount!.id;
      await createProfile(t, worker);
      await signIn(t, repos, owner);
      await publishDemand(t, title);
      var demand = (await io(t, () => repos.myDemands()))
          .singleWhere((d) => d.current.title == title);
      expect(demand.status, DemandStatus.open);

      // ── Share link: public view works, revoking turns it off ──
      await openDemand(t, demand.id);
      await tapIt(t, find.byTooltip('分享'));
      await waitFor(t, find.byType(SharePage));
      expect(
          (await io(t, () => repos.publicView(demand.shareToken)))?.available,
          isTrue);
      await shot(t, 'p01-share-page');
      await scrollTap(t, find.text('撤销分享链接'));
      await idle(t, 1000);
      expect(
          (await io(t, () => repos.publicView(demand.shareToken)))?.available,
          isNot(isTrue));
      await waitFor(t, find.text('此链接已撤销，或需求已关闭／下架'));
      await shot(t, 'p02-share-revoked');
      await scrollTap(t, find.text('撤销分享链接'));
      await idle(t, 1000);
      expect(
          (await io(t, () => repos.publicView(demand.shareToken)))?.available,
          isTrue);

      // ── Pause, resume, renew ──
      await openDemand(t, demand.id);
      await scrollTap(t, find.text('暂停'));
      expect((await io(t, () => repos.demand(demand.id)))!.status,
          DemandStatus.paused);
      await scrollTap(t, find.text('继续招募'));
      demand = (await io(t, () => repos.demand(demand.id)))!;
      expect(demand.status, DemandStatus.open);
      final before = demand.expiresAt;
      await scrollTap(t, find.text('续期'));
      demand = (await io(t, () => repos.demand(demand.id)))!;
      expect(demand.expiresAt, isNotNull);
      if (before != null) {
        expect(demand.expiresAt!.isBefore(before), isFalse);
      }
      await shot(t, 'p03-demand-manage');

      // ── Worker: favourite it from the list, see it under 收藏 ──
      await signIn(t, repos, worker);
      await home(t);
      await tab(t, '发现');
      await tapIt(t, find.byKey(const Key('explore-seg-1')));
      await waitFor(t, find.text(title));
      final card = find
          .ancestor(of: find.text(title), matching: find.byType(DemandCard))
          .first;
      await tapIt(t, find.descendant(of: card, matching: find.byTooltip('收藏')));
      expect(await io(t, () => repos.favourites()), contains(demand.id));
      await home(t);
      await open(t, const FavouritesPage());
      await waitFor(t, find.text(title));
      await shot(t, 'p04-favourites');

      // ── Worker: an itemised quote ──
      await openDemand(t, demand.id);
      await tapIt(t, find.widgetWithText(FilledButton, '报价'));
      await waitFor(t, find.byType(ApplyPage));
      await t.enterText(find.widgetWithText(TextField, '你承接哪些工作'), '拆旧瓦，铺新瓦');
      await scrollTap(t, find.text('按量报价'));
      if (find.widgetWithText(TextField, '分项').evaluate().isEmpty) {
        await scrollTap(t, find.text('添加分项'));
      }
      final item = find.widgetWithText(TextField, '分项').first;
      await scrollTo(t, item);
      await t.enterText(item, '铺瓦');
      final row = find.ancestor(of: item, matching: find.byType(Row)).first;
      final fields = find.descendant(of: row, matching: find.byType(TextField));
      await t.enterText(fields.at(1), '120');
      await t.enterText(fields.at(2), '3500');
      await t.pumpAndSettle();
      await shot(t, 'p05-itemised-quote');
      await scrollTap(t, find.text('发送报价'));
      await idle(t, 1000);
      final quote = (await io(t, () => repos.myApplications()))
          .singleWhere((a) => a.demandId == demand.id);
      expect(quote.current.pricing, PricingMode.perQuantity);
      expect(quote.current.lines, hasLength(1));
      expect(quote.current.lines.single.name, '铺瓦');
      expect(quote.current.total, 120 * 3500);

      // ── Owner: find the worker by name ──
      await signIn(t, repos, owner);
      await home(t);
      await tab(t, '发现');
      await tapIt(t, find.byKey(const Key('explore-seg-2')));
      final search = find.byType(TextField).hitTestable().first;
      await t.enterText(search, worker);
      await idle(t, 1500);
      await waitFor(
          t,
          find.descendant(
              of: find.byType(ProfileCard), matching: find.text(worker)));
      await shot(t, 'p06-worker-search');
      await tapIt(
          t,
          find.descendant(
              of: find.byType(ProfileCard), matching: find.text(worker)));
      await waitFor(t, find.byType(ProfilePage));
      expect(find.text('联系'), findsWidgets);

      // ── Owner closes the demand ──
      await openDemand(t, demand.id);
      await scrollTap(t, find.text('关闭'));
      await answerDialog(t, '不需要了 $run');
      demand = (await io(t, () => repos.demand(demand.id)))!;
      expect(demand.status, DemandStatus.closed);

      // ── Backup, delete the local copy, restore it from the cloud ──
      var seq = 0;
      final projectId = await store.createProject(createHouse(
          name: houseName,
          width: 9000,
          depth: 11000,
          columns: 2,
          rows: 1,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          newId: () => 'restore_${seq++}'));
      created.add(projectId);
      await home(t);
      await open(t, const BackupPage());
      await waitFor(t, find.text(houseName));
      final tile = find
          .ancestor(of: find.text(houseName), matching: find.byType(Column))
          .first;
      await tapIt(
          t,
          find.descendant(
              of: tile, matching: find.widgetWithText(OutlinedButton, '备份')));
      await idle(t, 1000);
      expect((await io(t, () => repos.backups())).map((b) => b.projectId),
          contains(projectId));
      await home(t);
      await store.deleteProject(projectId);
      created.remove(projectId);
      await open(t, const BackupPage());
      await waitFor(t, find.text('恢复到本设备'));
      await shot(t, 'p07-cloud-only');
      await tapIt(t, find.text('恢复到本设备').first);
      await idle(t, 1500);
      final restored = (await store.listProjects())
          .where((p) => p.document.meta.name.startsWith(houseName))
          .toList();
      expect(restored, isNotEmpty, reason: 'restored to the device');
      created.addAll(restored.map((p) => p.id));
      await shot(t, 'p08-restored');

      // ── Worker deletes the account ──
      await signIn(t, repos, worker);
      await home(t);
      await tab(t, '我的');
      await scrollTap(t, find.text('注销账号'));
      await tapIt(t, find.text('注销').last);
      await idle(t, 1500);
      expect(repos.currentAccount, isNull);
      final gone = await io(t, () => repos.account(workerId));
      expect(gone == null || gone.deleted, isTrue);
      // The same identity can sign up again, as a new account.
      await signIn(t, repos, worker);
      expect(repos.currentAccount!.id, isNot(workerId));
      expect(await io(t, () => repos.myProfiles()), isEmpty);
      await shot(t, 'p09-new-account-after-delete');

      // ignore: avoid_print
      print('MORE_RUN=$run DEMAND=${demand.id} OLD_WORKER=$workerId');
      expect(t.takeException(), isNull);
    } catch (_) {
      await shot(t, 'zz-more-failure');
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      for (final id in created) {
        await store.deleteProject(id);
      }
      await LastOpenProject.write(previous);
    }
  });
}
