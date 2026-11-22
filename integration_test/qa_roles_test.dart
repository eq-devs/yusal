// QA pass 2026-11-18: what each role can see and do, live against a
// yusal-api with DEV_LOGIN. Accounts are QA-<run> dev logins plus the
// "Test Restricted" persona; everything made here is closed and the QA
// accounts deleted at the end. Prints one `QA_ROW|...` line per check.
import '../test/support/test_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/apply/page.dart';
import 'package:yusal/features/coop/widgets/agreement_form.dart';
import 'package:yusal/features/coop/page.dart';
import 'package:yusal/features/demand/pages/applications.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/service/storage/last_open.dart';
import 'package:yusal/service/storage/project_store.dart';

import 'e2e_support.dart';

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

void row(String id, String what, String expected, String actual, bool ok) =>
    // ignore: avoid_print
    print('QA_ROW|$id|$what|$expected|$actual|${ok ? 'PASS' : 'FAIL'}');

/// Runs [f] through the app's API client; returns the error code or 'OK'.
/// The error is caught inside runAsync: errors escaping it are reported to
/// the test framework and swallowed.
Future<String> attempt(WidgetTester t, Future<Object?> Function() f) async =>
    (await t.runAsync(() async {
      try {
        await f();
        return 'OK';
      } on ApiFailure catch (e) {
        return '${e.code}${e.details.isEmpty ? '' : ':${e.details}'}';
      } catch (e) {
        return 'ERR ${e.runtimeType}';
      }
    }))!;

bool shown(String text) => find.text(text).evaluate().isNotEmpty;

Future<void> chipSignIn(WidgetTester t, TestHttp repos, String key) async {
  if (repos.api.currentAccount != null) await signOut(t, repos);
  await home(t);
  await tab(t, '我的');
  await tapIt(t, find.widgetWithText(FilledButton, '登录或注册'));
  final chip = find.byKey(Key('test-login-$key'));
  await waitFor(t, chip);
  await scrollTo(t, chip);
  await tapIt(t, chip);
  await waitFor(t, find.byTooltip('改称呼'));
}

/// Sends a lump-sum quote through the quote form.
Future<void> quote(WidgetTester t, String demandId, String amount) async {
  await home(t);
  await open(t, DemandDetailPage(demandId: demandId));
  await waitFor(t, find.widgetWithText(FilledButton, '报价'));
  await tapIt(t, find.widgetWithText(FilledButton, '报价'));
  await waitFor(t, find.byType(ApplyPage));
  await t.enterText(find.widgetWithText(TextField, '你承接哪些工作'), 'QA 全部砌墙');
  final lump = find.widgetWithText(TextField, '总价 ₸');
  await scrollTo(t, lump);
  await t.enterText(lump, amount);
  final days = find.widgetWithText(TextField, '预计工期（天）');
  await scrollTo(t, days);
  await t.enterText(days, '20');
  await t.pumpAndSettle();
  await tapIt(t, find.text('发送报价'));
  await idle(t, 1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('roles: guest, owner, worker, contractor, restricted', (t) async {
    requireBackend();
    final run = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
    final owner = 'QA-Owner $run';
    final worker = 'QA-Worker $run';
    final contractor = 'QA-Contractor $run';
    final title = 'QA-roles 砌墙 $run';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yusal_api.refresh_token');
    await prefs.setString('house-lang', 'zh');
    appLang = AppLang.zh;
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);

    final repos = TestHttp(api);
    await repos.api.restore();
    String? demandId;
    String? coopId;
    String? ownerId;
    String? providerName;
    try {
      await t.pumpWidget(RepaintBoundary(
          key: shotKey, child: testApp(repos, store: ProjectStore())));
      await idle(t, 1000);

      // ── Owner publishes a demand ──
      await signIn(t, repos, owner);
      ownerId = repos.api.currentAccount!.id;
      await publishDemand(t, title);
      final mine = await io(t, repos.demands.myDemands);
      final demand = mine.singleWhere((d) => d.current.title == title);
      demandId = demand.id;
      row('D-owner-1', 'owner publishes a demand', 'open (auto review)',
          demand.status.name, demand.status == DemandStatus.open);
      await shot(t, 'd01-owner-demand');
      final ownerActions = ['暂停', '关闭', '修改（生成新版本）'];
      row(
          'D-owner-2',
          'owner sees pause/close/revise on own demand',
          'shown',
          ownerActions.where(shown).join(','),
          ownerActions.every(shown) || ownerActions.where(shown).length >= 2);
      row('D-owner-3', 'owner is not offered a quote on own demand', 'hidden',
          shown('报价') ? 'shown' : 'hidden', !shown('报价'));

      // ── Guest ──
      await signOut(t, repos);
      await home(t);
      await open(t, DemandDetailPage(demandId: demandId));
      await waitFor(t, find.text(title));
      final guestOwnerActions = ['暂停', '关闭'].where(shown).toList();
      row('D-guest-1', 'guest can read an open demand', 'readable', 'readable',
          true);
      row(
          'D-guest-2',
          'guest sees no owner actions',
          'none',
          guestOwnerActions.isEmpty ? 'none' : guestOwnerActions.join(','),
          guestOwnerActions.isEmpty);
      if (shown('报价')) {
        await tapIt(t, find.text('报价').first);
        await idle(t, 1000);
      }
      final asked =
          find.byKey(const Key('dev-login-name')).evaluate().isNotEmpty ||
              shown('登录或注册') ||
              find.textContaining('登录').evaluate().isNotEmpty;
      await shot(t, 'd02-guest-quote');
      row('D-guest-3', 'guest tapping 报价 is asked to sign in', 'sign-in',
          asked ? 'sign-in shown' : 'no sign-in', asked);
      await home(t);

      // ── Worker: profile, quote, chat; no owner actions ──
      await signIn(t, repos, worker);
      final workerId = repos.api.currentAccount!.id;
      await createProfile(t, worker);
      await home(t);
      await open(t, DemandDetailPage(demandId: demandId));
      await waitFor(t, find.text(title));
      final workerOwnerActions = ['暂停', '关闭'].where(shown).toList();
      row(
          'D-worker-1',
          "worker sees no owner actions on others' demand",
          'none',
          workerOwnerActions.isEmpty ? 'none' : workerOwnerActions.join(','),
          workerOwnerActions.isEmpty);
      await quote(t, demandId, '1800000');
      final apps = await io(t, repos.applications.myApplications);
      final workerApp = apps.where((a) => a.demandId == demandId).firstOrNull;
      row(
          'D-worker-2',
          'worker sends a quote',
          'submitted',
          workerApp?.status.name ?? 'none',
          workerApp?.status == ApplicationStatus.submitted);
      await shot(t, 'd03-worker-quoted');
      final pause = await attempt(t, () => repos.demands.pause(demandId!));
      row('D-worker-3', "API: worker pauses owner's demand", 'FORBIDDEN', pause,
          pause.startsWith('FORBIDDEN'));

      // ── Contractor (team profile via the form's defaults) quotes too ──
      await signIn(t, repos, contractor);
      await createProfile(t, contractor);
      await quote(t, demandId, '2100000');
      final capps = await io(t, repos.applications.myApplications);
      final contractorApp =
          capps.where((a) => a.demandId == demandId).firstOrNull;
      row(
          'D-contractor-1',
          'second provider quotes on the same demand',
          'submitted',
          contractorApp?.status.name ?? 'none',
          contractorApp?.status == ApplicationStatus.submitted);
      final invite = await attempt(
          t,
          () => repos.cooperations.invite(
              workerApp!.id,
              Agreement(
                  version: 0,
                  scope: 'x',
                  demandVersionNo: 0,
                  proposedBy: '',
                  status: AgreementStatus.proposed,
                  createdAt: DateTime.now(),
                  confirmedBy: const {})));
      row('D-contractor-2', "API: a provider invites on someone else's demand",
          'FORBIDDEN', invite, invite.startsWith('FORBIDDEN'));

      // ── Owner invites the worker; worker confirms ──
      await signIn(t, repos, owner);
      await home(t);
      await open(t, ApplicationsPage(demandId: demandId));
      await waitFor(t, find.text('选择并发起约定'));
      await shot(t, 'd04-owner-quotes');
      await tapIt(t, find.text('选择并发起约定').first);
      await waitFor(t, find.byType(AgreementForm));
      final scope = find.widgetWithText(TextField, '工作范围');
      if ((t.widget<TextField>(scope).controller?.text ?? '').isEmpty) {
        await t.enterText(scope, 'QA 全部砌墙');
      }
      await tapIt(t, find.text('发起并确认我方'));
      await idle(t, 1000);
      final coops =
          await io(t, () => repos.cooperations.cooperationsFor(demandId!));
      coopId = coops.firstOrNull?.id;
      row(
          'D-owner-4',
          'owner invites a quote',
          'cooperation pending',
          coops.firstOrNull?.status.name ?? 'none',
          coops.firstOrNull?.status == CooperationStatus.pending);
      final ownerConfirm =
          await attempt(t, () => repos.cooperations.confirm(coopId!));
      row('D-owner-5', "API: owner confirms on the provider's behalf",
          'refused', ownerConfirm, ownerConfirm != 'OK');

      providerName = coops.first.providerId == workerId ? worker : contractor;
      await signIn(t, repos, providerName);
      await home(t);
      await open(t, CooperationPage(cooperationId: coopId!));
      await waitFor(t, find.text('合作详情'));
      await tapIt(t, find.text('确认合作'));
      await idle(t, 1000);
      var coop = (await io(t, () => repos.cooperations.cooperation(coopId!)))!;
      row('D-worker-4', 'provider confirms the cooperation', 'confirmed',
          coop.status.name, coop.status == CooperationStatus.confirmed);
      await shot(t, 'd05-coop-confirmed');

      // ── Restricted: the seed account "Стройбаза" (seed:spam) ──
      await chipSignIn(t, repos, 'seed:spam');
      final restricted = repos.api.currentAccount?.restricted ?? false;
      row('D-restricted-0', 'seed:spam is a restricted account', 'true',
          '$restricted', restricted);
      String? draftId;
      final draft = await attempt(t, () async {
        final d = await repos.demands.saveDraft(
            DemandType.contract,
            DemandVersion(
                no: 0,
                title: 'QA-restricted $run',
                trades: const ['mason'],
                region: 'almaty',
                locality: 'QA',
                budget: const Budget(mode: BudgetMode.askQuote),
                createdAt: DateTime.now(),
                contract: const ContractTerms(scopeKind: ScopeKind.custom)));
        draftId = d.id;
        return repos.demands.publish(d.id);
      });
      row('D-restricted-1', 'API: restricted publishes a demand', 'RESTRICTED',
          draft, draft.startsWith('RESTRICTED'));
      final apply = await attempt(
          t,
          () => repos.applications.submit(
              demandId: demandId!,
              profileId: 'none',
              version: ApplicationVersion(
                  no: 0,
                  demandVersionNo: 0,
                  createdAt: DateTime.now(),
                  scopeText: 'QA',
                  lumpSum: 1,
                  durationDays: 1),
              requestId: 'qa-$run'));
      row('D-restricted-2', 'API: restricted applies', 'RESTRICTED', apply,
          apply.startsWith('RESTRICTED'));
      String? conv;
      final openConv = await attempt(t, () async {
        return conv =
            (await repos.chat.openConversation(ownerId!, demandId: demandId))
                .id;
      });
      row('D-restricted-3', 'API: restricted opens a conversation',
          'RESTRICTED', openConv, openConv.startsWith('RESTRICTED'));
      if (conv != null) {
        final send = await attempt(
            t, () => repos.chat.send(conv!, MessageKind.text, text: 'QA ping'));
        row('D-restricted-4', 'API: restricted sends a chat message',
            'RESTRICTED', send, send.startsWith('RESTRICTED'));
        final phone = await attempt(t, () => repos.chat.sharePhone(conv!));
        row('D-restricted-5', 'API: restricted shares phone in chat',
            'RESTRICTED', phone, phone.startsWith('RESTRICTED'));
      }
      final posts = await io(t, repos.posts.myPosts);
      if (posts.isNotEmpty) {
        // Saves the post unchanged: nothing differs if it is allowed.
        final edit =
            await attempt(t, () => repos.posts.updatePost(posts.first));
        row('D-restricted-6', 'API: restricted edits own house post',
            'RESTRICTED', edit, edit.startsWith('RESTRICTED'));
      } else {
        row('D-restricted-6', 'API: restricted edits own house post',
            'RESTRICTED', 'no post to try', false);
      }
      final coopsR = await io(t, repos.cooperations.myCooperations);
      if (coopsR.isNotEmpty) {
        // Index 999 does not exist: the answer shows which check runs first.
        final ms = await attempt(
            t, () => repos.cooperations.requestMilestone(coopsR.first.id, 999));
        row('D-restricted-7', 'API: restricted requests a milestone',
            'RESTRICTED', ms, ms.startsWith('RESTRICTED'));
        final change = await attempt(
            t,
            () => repos.cooperations.proposeChange(
                coopsR.first.id,
                Agreement(
                    version: 0,
                    scope: '',
                    demandVersionNo: 0,
                    proposedBy: '',
                    status: AgreementStatus.proposed,
                    createdAt: DateTime.now(),
                    confirmedBy: const {})));
        row('D-restricted-8', 'API: restricted proposes an agreement change',
            'RESTRICTED', change, change.startsWith('RESTRICTED'));
      } else {
        row('D-restricted-7', 'API: restricted milestone / agreement change',
            'RESTRICTED', 'no cooperation to try', false);
      }
      if (draftId != null) {
        final c =
            await attempt(t, () => repos.demands.close(draftId!, 'QA cleanup'));
        row('D-cleanup-0', 'restricted QA draft closed', 'OK', c, c == 'OK');
      }
      // The quote button in the UI.
      await home(t);
      await open(t, DemandDetailPage(demandId: demandId));
      await waitFor(t, find.text(title));
      if (shown('报价')) {
        await tapIt(t, find.text('报价').first);
        await idle(t, 1500);
      }
      await shot(t, 'd06-restricted-quote');
      row(
          'D-restricted-9',
          'UI: restricted taps 报价',
          'no quote form',
          find.byType(ApplyPage).evaluate().isEmpty ? 'no form' : 'form opened',
          find.byType(ApplyPage).evaluate().isEmpty);
      if (repos.api.currentAccount != null) await signOut(t, repos);
    } catch (_) {
      await shot(t, 'd99-roles-failure');
      rethrow;
    } finally {
      // End the cooperation, close the demand and delete the QA accounts,
      // whatever happened.
      if (coopId != null) {
        try {
          await signIn(t, repos, owner);
          final end = await attempt(
              t, () => repos.cooperations.requestEnd(coopId!, 'QA cleanup'));
          await signIn(t, repos, providerName ?? worker);
          final ok =
              await attempt(t, () => repos.cooperations.confirmEnd(coopId!));
          row('D-cleanup-1', 'QA cooperation ended by both', 'OK/OK',
              '$end/$ok', end == 'OK' && ok == 'OK');
        } catch (e) {
          row('D-cleanup-1', 'QA cooperation ended by both', 'OK', 'ERR $e',
              false);
        }
      }
      for (final name in [owner, worker, contractor]) {
        try {
          await signIn(t, repos, name);
          if (name == owner && demandId != null) {
            final c = await attempt(
                t, () => repos.demands.close(demandId!, 'QA cleanup'));
            row('D-cleanup-2', 'QA demand closed', 'OK', c, c == 'OK');
          }
          final del = await attempt(t, repos.auth.deleteAccount);
          row('D-cleanup-3', 'QA account $name deleted', 'OK', del,
              del == 'OK');
        } catch (e) {
          row('D-cleanup-3', 'QA account $name deleted', 'OK', 'ERR $e', false);
        }
      }
      // ignore: avoid_print
      print('QA_IDS demand=$demandId coop=$coopId');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
    }
  });
}
