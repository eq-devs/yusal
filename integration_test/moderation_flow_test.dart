// Moderation end to end against a yusal-api started with MANUAL_REVIEW=true
// and DEV_LOGIN=true, where the dev account named by E2E_ADMIN (default
// "Admin E2E") was made an admin with `go run ./cmd/setadmin <id>`:
//   flutter test integration_test/moderation_flow_test.dart -d <device> \
//     --dart-define=YUSAL_API=http://localhost:8080 \
//     --dart-define=YUSAL_DEV_LOGIN=true \
//     --dart-define=E2E_SHOTS=$PWD/test-screens
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/chat/chat_page.dart';
import 'package:yusal/platform/ui/me/admin_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

import 'e2e_support.dart';

const adminName =
    String.fromEnvironment('E2E_ADMIN', defaultValue: 'Admin E2E');

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

/// The API error code of [f], or null when it succeeds.
Future<String?> failure(WidgetTester t, Future<Object?> Function() f) =>
    io(t, () async {
      try {
        await f();
        return null;
      } on ApiFailure catch (e) {
        return e.code;
      }
    });

Future<void> openAdmin(WidgetTester t, HttpBackend repos) async {
  await signIn(t, repos, adminName);
  expect(repos.currentAccount!.isAdmin, isTrue,
      reason: 'make "$adminName" an admin with go run ./cmd/setadmin <id>');
  await home(t);
  await tab(t, '我的');
  await scrollTap(t, find.text('审核后台'));
  await waitFor(t, find.byType(AdminPage));
}

/// The admin card whose texts include [text].
Finder card(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Column)).first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('review queue approve / reject, report upheld restricts',
      (t) async {
    requireBackend();
    final run = DateTime.now().millisecondsSinceEpoch.toString();
    final owner = 'Olga $run', worker = 'Wang $run', rita = 'Rita $run';
    final good = '砌墙找师傅 $run', bad = '找人砌墙押金 $run';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yusal_api.refresh_token');
    await prefs.setString('house-lang', 'zh');
    AppSettings.instance.lang = AppLang.zh;
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);

    final repos = HttpBackend(api);
    await repos.restore();
    try {
      await t.pumpWidget(RepaintBoundary(
          key: shotKey,
          child: ProviderScope(
              child: HouseApp(repos: repos, store: ProjectStore()))));
      await idle(t, 1000);

      // ── Owner publishes two demands; both wait for review ──
      await signIn(t, repos, owner);
      final ownerId = repos.currentAccount!.id;
      await publishDemand(t, good);
      await publishDemand(t, bad);
      var mine = await io(t, () => repos.myDemands());
      final goodId = mine.singleWhere((d) => d.current.title == good).id;
      final badId = mine.singleWhere((d) => d.current.title == bad).id;
      expect(mine.map((d) => d.status).toSet(), {DemandStatus.pendingReview});
      await shot(t, 'a01-pending-review');

      // ── Admin approves one and rejects the other ──
      await openAdmin(t, repos);
      await waitFor(t, find.text(good));
      await shot(t, 'a02-review-queue');
      await tapIt(
          t, find.descendant(of: card(good), matching: find.text('通过')));
      await idle(t, 1000);
      await waitFor(t, find.text(bad));
      await tapIt(t, find.descendant(of: card(bad), matching: find.text('拒绝')));
      await answerDialog(t, '不要收押金 $run');
      await idle(t, 1000);
      expect(find.text(good), findsNothing);
      expect(find.text(bad), findsNothing);
      final audit = await io(t, () => repos.audit());
      expect(audit.where((a) => a.targetId == goodId || a.targetId == badId),
          hasLength(2));

      // ── The owner sees the outcome and gets both notices ──
      await signIn(t, repos, owner);
      mine = await io(t, () => repos.myDemands());
      expect(mine.singleWhere((d) => d.id == goodId).status, DemandStatus.open);
      final rejected = mine.singleWhere((d) => d.id == badId);
      expect(rejected.status, DemandStatus.rejected);
      expect(rejected.rejectReason, contains('不要收押金'));
      final notes = await io(t, () => repos.notifications());
      expect(notes.where((n) => n.refId == goodId), isNotEmpty);
      expect(notes.where((n) => n.refId == badId), isNotEmpty);
      await home(t);
      await tab(t, '消息');
      await tapIt(t, find.text('通知'));
      await waitFor(t, find.textContaining(bad));
      await shot(t, 'a03-owner-notices');

      // ── A worker messages Rita; Rita reports the account from chat ──
      await signIn(t, repos, worker);
      final workerId = repos.currentAccount!.id;
      await createProfile(t, worker);
      await signIn(t, repos, rita);
      final ritaId = repos.currentAccount!.id;
      await signIn(t, repos, worker);
      final conv = await io(t, () => repos.openConversation(ritaId));
      await io(t,
          () => repos.send(conv.id, MessageKind.text, text: '加我微信，先交押金 $run'));
      await signIn(t, repos, rita);
      await home(t);
      await open(t, ChatPage(conversationId: conv.id));
      await waitFor(t, find.text('加我微信，先交押金 $run'));
      await tapIt(t, find.byType(PopupMenuButton<String>));
      await tapIt(t, find.text('举报'));
      await answerDialog(t, '要求先交押金 $run');
      await shot(t, 'a04-report-from-chat');

      // ── Admin upholds the report: the account is restricted ──
      await openAdmin(t, repos);
      await tapIt(t, find.text('举报').last);
      await waitFor(t, find.text('要求先交押金 $run'));
      await shot(t, 'a05-report-queue');
      await tapIt(
          t,
          find.descendant(
              of: card('要求先交押金 $run'), matching: find.text('核实违规并处理')));
      await answerDialog(t, '收押金，限制账号 $run');
      await idle(t, 1000);
      final reports = await io(t, () => repos.reports());
      final report = reports.singleWhere((r) => r.targetId == workerId);
      expect(report.status, isNot(ReportStatus.open));

      // ── Restricted: cannot publish, apply or message ──
      await signIn(t, repos, worker);
      expect(repos.currentAccount!.restricted, isTrue);
      expect(
          await failure(
              t, () => repos.send(conv.id, MessageKind.text, text: 'hi')),
          ApiCodes.restricted);
      final openDemand = await io(t, () => repos.demand(goodId));
      final profile = (await io(t, () => repos.myProfiles())).single;
      expect(
          await failure(
              t,
              () => repos.submit(
                  demandId: goodId,
                  profileId: profile.id,
                  requestId: 'restricted-$run',
                  version: ApplicationVersion(
                      no: 0,
                      demandVersionNo: openDemand!.current.no,
                      createdAt: DateTime.now(),
                      scopeText: '砌墙',
                      lumpSum: 1000000))),
          ApiCodes.restricted);
      expect(
          await failure(
              t,
              () => repos
                  .saveDraft(DemandType.contract, openDemand!.current)
                  .then((d) => repos.publish(d.id))),
          ApiCodes.restricted);
      // The UI says so too.
      await home(t);
      await open(t, ChatPage(conversationId: conv.id));
      await waitFor(t, find.byType(TextField));
      await t.enterText(
          find.descendant(
              of: find.byType(ChatPage), matching: find.byType(TextField)),
          '还在吗');
      await tapIt(t, find.byTooltip('发送'));
      await shot(t, 'a06-restricted-cannot-send');

      // ignore: avoid_print
      print('MODERATION_RUN=$run OWNER=$ownerId WORKER=$workerId');
      expect(t.takeException(), isNull);
    } catch (_) {
      await shot(t, 'zz-moderation-failure');
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
    }
  });
}
