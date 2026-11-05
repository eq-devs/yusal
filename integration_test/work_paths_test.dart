// The less common paths of the work platform against a running yusal-api
// (DEV_LOGIN=true, MANUAL_REVIEW off): a hire demand end to end, an invite
// declined and one revoked, an agreement change, a disputed end, a phone
// number shared in chat, and blocking. Run like backend_flow_test.dart.
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
import 'package:yusal/platform/ui/apply/apply_page.dart';
import 'package:yusal/platform/ui/chat/chat_page.dart';
import 'package:yusal/platform/ui/coop/agreement_form.dart';
import 'package:yusal/platform/ui/coop/coop_page.dart';
import 'package:yusal/platform/ui/demand/applications_page.dart';
import 'package:yusal/platform/ui/demand/demand_detail_page.dart';
import 'package:yusal/platform/ui/home/post_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

import 'e2e_support.dart';

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

Future<String?> failure(WidgetTester t, Future<Object?> Function() f) =>
    io(t, () async {
      try {
        await f();
        return null;
      } on ApiFailure catch (e) {
        return e.code;
      }
    });

Future<void> openCoop(WidgetTester t, String id) async {
  await home(t);
  await open(t, CooperationPage(cooperationId: id));
  await waitFor(t, find.text('合作详情'));
}

/// Owner: from the demand's applications, invite the only applicant.
Future<void> invite(WidgetTester t, String demandId) async {
  await home(t);
  await open(t, ApplicationsPage(demandId: demandId));
  await waitFor(t, find.text('录用并发起约定'));
  await tapIt(t, find.text('录用并发起约定'));
  await waitFor(t, find.byType(AgreementForm));
  final scope = find.widgetWithText(TextField, '工作范围');
  if ((t.widget<TextField>(scope).controller?.text ?? '').isEmpty) {
    await t.enterText(scope, '砌墙');
  }
  await tapIt(t, find.text('发起并确认我方'));
  await idle(t, 1000);
}

Future<void> sendChat(WidgetTester t, String text) async {
  await t.enterText(
      find.descendant(
          of: find.byType(ChatPage), matching: find.byType(TextField)),
      text);
  await tapIt(t, find.byTooltip('发送'));
  await idle(t, 800);
}

Future<void> chatMenu(WidgetTester t, String item) async {
  await tapIt(
      t,
      find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(PopupMenuButton<String>)));
  await tapIt(t, find.text(item).last);
  await idle(t, 800);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'hire, decline, revoke, change, dispute, phone, block and unblock',
      (t) async {
    requireBackend();
    final run = DateTime.now().millisecondsSinceEpoch.toString();
    final owner = 'Olga $run', worker = 'Wang $run';
    final title = '招两名瓦工 $run';

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

      // ── Hire demand: owner publishes, worker signs up (报名) ──
      await signIn(t, repos, worker);
      final workerId = repos.currentAccount!.id;
      await createProfile(t, worker);
      await signIn(t, repos, owner);
      final ownerId = repos.currentAccount!.id;
      await publishDemand(t, title, hire: true, headcount: 2, wage: 15000);
      final demand = (await io(t, () => repos.myDemands()))
          .singleWhere((d) => d.current.title == title);
      expect(demand.type, DemandType.hire);
      expect(demand.status, DemandStatus.open);
      expect(demand.current.hire?.headcount, 2);
      expect(demand.current.hire?.wage, 15000);
      await shot(t, 'w01-hire-demand');

      await signIn(t, repos, worker);
      await home(t);
      await open(t, DemandDetailPage(demandId: demand.id));
      await waitFor(t, find.widgetWithText(FilledButton, '报名'));
      await tapIt(t, find.widgetWithText(FilledButton, '报名'));
      await waitFor(t, find.byType(ApplyPage));
      await shot(t, 'w02-signup-form');
      await tapIt(t, find.text('发送报名'));
      await idle(t, 1000);
      final application = (await io(t, () => repos.myApplications()))
          .singleWhere((a) => a.demandId == demand.id);
      expect(application.current.acceptsOffer, isTrue);

      // ── Invite 1: the worker declines ──
      await signIn(t, repos, owner);
      await invite(t, demand.id);
      var coops = await io(t, () => repos.cooperationsFor(demand.id));
      expect(coops.single.status, CooperationStatus.pending);
      await signIn(t, repos, worker);
      await openCoop(t, coops.single.id);
      await tapIt(t, find.text('拒绝'));
      await idle(t, 1000);
      var declined = await io(t, () => repos.cooperation(coops.single.id));
      expect(declined!.status, CooperationStatus.notFormed);
      expect((await io(t, () => repos.application(application.id)))!.status,
          ApplicationStatus.submitted);

      // ── Invite 2: the owner revokes it ──
      await signIn(t, repos, owner);
      await invite(t, demand.id);
      coops = await io(t, () => repos.cooperationsFor(demand.id));
      final second =
          coops.singleWhere((c) => c.status == CooperationStatus.pending);
      await openCoop(t, second.id);
      await tapIt(t, find.text('撤回邀请'));
      await idle(t, 1000);
      expect((await io(t, () => repos.cooperation(second.id)))!.status,
          CooperationStatus.notFormed);

      // ── Invite 3: the worker confirms ──
      await invite(t, demand.id);
      coops = await io(t, () => repos.cooperationsFor(demand.id));
      final coopId =
          coops.singleWhere((c) => c.status == CooperationStatus.pending).id;
      await signIn(t, repos, worker);
      await openCoop(t, coopId);
      await tapIt(t, find.text('确认合作'));
      await idle(t, 1000);
      expect((await io(t, () => repos.cooperation(coopId)))!.status,
          CooperationStatus.confirmed);
      await shot(t, 'w03-hire-confirmed');

      // ── Agreement change: owner proposes, worker accepts ──
      await signIn(t, repos, owner);
      await openCoop(t, coopId);
      await scrollTap(t, find.text('提出变更'));
      await waitFor(t, find.byType(AgreementForm));
      final amount = find.widgetWithText(TextField, '金额 ₸（可空）');
      await scrollTo(t, amount);
      await t.enterText(amount, '18000');
      await tapIt(t, find.text('发送变更，待对方确认'));
      await idle(t, 1000);
      await signIn(t, repos, worker);
      await openCoop(t, coopId);
      await scrollTap(t, find.text('接受变更'));
      await idle(t, 1000);
      var coop = (await io(t, () => repos.cooperation(coopId)))!;
      expect(coop.agreement.version, 2);
      expect(coop.agreement.amount, 18000);
      expect(coop.agreement.status, AgreementStatus.active);
      await shot(t, 'w04-change-accepted');

      // ── End: worker asks, owner disputes ──
      await scrollTap(t, find.text('请求结束'));
      await answerDialog(t, '活干完了 $run');
      await signIn(t, repos, owner);
      await openCoop(t, coopId);
      await scrollTap(t, find.text('提出异议'));
      await answerDialog(t, '还差收尾 $run');
      coop = (await io(t, () => repos.cooperation(coopId)))!;
      expect(coop.status, CooperationStatus.confirmed);
      expect(coop.endRequest?.dispute, contains('还差收尾'));
      await scrollTo(t, find.textContaining('还差收尾'));
      await shot(t, 'w05-end-disputed');

      // ── Phone: owner sets it under 我的 → 手机号, then shares it ──
      await home(t);
      await tab(t, '我的');
      await scrollTap(t, find.text('手机号'));
      await answerDialog(t, '+7 701 234 5678');
      expect(repos.currentAccount!.phone, isNotEmpty);
      final conv = await io(t, () => repos.openConversation(workerId));
      await home(t);
      await open(t, ChatPage(conversationId: conv.id));
      await waitFor(t, find.byTooltip('更多'));
      await tapIt(t, find.byTooltip('更多'));
      await waitFor(t, find.text('向对方展示我的电话'));
      await tapIt(t, find.text('向对方展示我的电话'));
      await tapIt(t, find.text('确定').last);
      await idle(t, 1000);
      final msgs = await io(t, () => repos.messages(conv.id));
      expect(msgs.any((m) => m.kind == MessageKind.phoneShared), isTrue);
      await shot(t, 'w06-phone-shared');

      // ── A post by the owner with a critique by the worker ──
      final snap = await io(
          t,
          () => repos.saveSnapshot(DesignSnapshot(
              id: '',
              ownerId: ownerId,
              projectId: 'e2e-$run',
              projectName: '小屋 $run',
              designUpdatedAt: DateTime.now().toUtc().toIso8601String(),
              extractedAt: DateTime.now(),
              stages: const [],
              lines: const [],
              summary: '10 × 12 m')));
      final post = await io(
          t,
          () => repos.publishPost(HousePost(
              id: '',
              ownerId: '',
              projectId: 'e2e-$run',
              snapshotId: snap.id,
              title: '小屋 $run',
              story: '',
              region: 'almaty',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              area: 120,
              floors: 1,
              rooms: 3,
              tags: const [],
              openForBuilders: false,
              focus: const [])));
      await signIn(t, repos, worker);
      final critique = await io(t, () => repos.comment(post.id, '屋顶太平了 $run'));
      await signIn(t, repos, owner);
      await io(
          t, () => repos.comment(post.id, '谢谢建议 $run', parentId: critique.id));

      // ── Worker blocks the owner in chat ──
      await signIn(t, repos, worker);
      await home(t);
      await open(t, ChatPage(conversationId: conv.id));
      await waitFor(t, find.byTooltip('更多'));
      await chatMenu(t, '拉黑');
      expect(await io(t, () => repos.blocked()), contains(ownerId));
      await shot(t, 'w07-blocked');

      // The blocker no longer sees the blocked account's comments.
      final seen = await io(t, () => repos.comments(post.id));
      expect(seen.map((c) => c.text), contains('屋顶太平了 $run'));
      expect(seen.map((c) => c.text), isNot(contains('谢谢建议 $run')));
      await home(t);
      await open(t, PostPage(postId: post.id));
      await waitFor(t, find.text('屋顶太平了 $run'));
      expect(find.text('谢谢建议 $run'), findsNothing);
      await shot(t, 'w08-blocked-comment-hidden');

      // The blocked owner can't message.
      await signIn(t, repos, owner);
      expect(
          await failure(
              t, () => repos.send(conv.id, MessageKind.text, text: '在吗')),
          ApiCodes.blocked);
      await signIn(t, repos, worker);

      // ── Unblock: messages and comments come back ──
      await home(t);
      await open(t, ChatPage(conversationId: conv.id));
      // The blocker sees why there is no input bar.
      await waitFor(t, find.text('你已拉黑对方，无法发送消息。'));
      await chatMenu(t, '取消拉黑');
      await waitFor(t, find.byTooltip('更多'));
      expect(await io(t, () => repos.blocked()), isNot(contains(ownerId)));
      expect((await io(t, () => repos.comments(post.id))).map((c) => c.text),
          contains('谢谢建议 $run'));
      await sendChat(t, '解除了 $run');
      await signIn(t, repos, owner);
      await home(t);
      await open(t, ChatPage(conversationId: conv.id));
      await waitFor(t, find.text('解除了 $run'));
      await sendChat(t, '好的 $run');
      await waitFor(t, find.text('好的 $run'));
      await shot(t, 'w09-unblocked-chat');

      // ignore: avoid_print
      print('WORK_RUN=$run DEMAND=${demand.id} COOP=$coopId POST=${post.id}');
      expect(t.takeException(), isNull);
    } catch (_) {
      await shot(t, 'zz-work-failure');
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
    }
  });
}
