// The work platform end to end against a running yusal-api, two dev-login
// accounts: a worker and a house owner. Run like backend_flow_test.dart:
//   flutter test integration_test/market_flow_test.dart -d <device> \
//     --dart-define=YUSAL_API=http://localhost:8080 \
//     --dart-define=YUSAL_DEV_LOGIN=true \
//     --dart-define=E2E_SHOTS=$PWD/test-screens
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/main.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/apply/apply_page.dart';
import 'package:yusal/platform/ui/chat/chat_page.dart';
import 'package:yusal/platform/ui/coop/agreement_form.dart';
import 'package:yusal/platform/ui/coop/coop_page.dart';
import 'package:yusal/platform/ui/coop/review_page.dart';
import 'package:yusal/platform/ui/demand/applications_page.dart';
import 'package:yusal/platform/ui/demand/demand_detail_page.dart';
import 'package:yusal/platform/ui/demand/publish_page.dart';
import 'package:yusal/platform/ui/profile/profile_edit_page.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';

import 'e2e_support.dart';

/// Stands in for the gallery: returns one generated photo.
class FakeGallery extends FileSelectorPlatform {
  FakeGallery(this.photo);
  final Uint8List photo;
  @override
  Future<List<XFile>> openFiles(
          {List<XTypeGroup>? acceptedTypeGroups,
          String? initialDirectory,
          String? confirmButtonText}) async =>
      [XFile.fromData(photo, name: 'site.png', mimeType: 'image/png')];
}

/// A small PNG drawn on the spot.
Future<Uint8List> sitePhoto() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 320, 240),
      Paint()..color = const Color(0xffb5651d));
  c.drawRect(const Rect.fromLTWH(40, 60, 240, 120),
      Paint()..color = const Color(0xffeeeeee));
  final img = await rec.endRecording().toImage(320, 240);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

/// Opens a cooperation the way the app's links do.
Future<void> openCoop(WidgetTester t, String id) async {
  await home(t);
  await open(t, CooperationPage(cooperationId: id));
  await waitFor(t, find.text('合作详情'));
}

/// Fills the work-log / inspection sheet and submits it.
Future<void> submitSiteEntry(WidgetTester t, String note) async {
  await waitFor(t, find.byKey(const Key('site-entry-submit')));
  final field = find.descendant(
      of: find.byType(BottomSheet), matching: find.byType(TextField));
  if (field.evaluate().isNotEmpty) await t.enterText(field.first, note);
  await tapIt(t, find.byKey(const Key('site-entry-submit')));
  await idle(t, 1000);
}

/// Gives five stars on every dimension and submits.
Future<void> reviewAll(WidgetTester t, String text) async {
  await waitFor(t, find.byType(ReviewPage));
  while (find.byTooltip('5').evaluate().isNotEmpty &&
      find.byIcon(Icons.star_outline_rounded).evaluate().isNotEmpty) {
    final fives = find.byTooltip('5');
    // Tap the first row that still has empty stars.
    var tapped = false;
    for (var i = 0; i < fives.evaluate().length; i++) {
      final row = find.ancestor(of: fives.at(i), matching: find.byType(Row));
      if (find
          .descendant(
              of: row.first, matching: find.byIcon(Icons.star_outline_rounded))
          .evaluate()
          .isNotEmpty) {
        await tapIt(t, fives.at(i));
        tapped = true;
        break;
      }
    }
    if (!tapped) break;
  }
  await t.enterText(
      find.descendant(
          of: find.byType(ReviewPage), matching: find.byType(TextField)),
      text);
  await tapIt(t, find.text('提交评价'));
  await idle(t, 1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'profile, demand, quote, invite, confirm, milestone, work log, end, '
      'reviews, chat, notifications, report', (t) async {
    requireBackend();
    final run = DateTime.now().millisecondsSinceEpoch.toString();
    final worker = 'Wang $run', owner = 'Olga $run';
    final demandTitle = '砌墙 130 平米 $run';

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

      // ── 1. Worker creates a service profile ──
      await signIn(t, repos, worker);
      final workerId = repos.currentAccount!.id;
      await home(t);
      await open(t, const ProfileEditPage());
      await waitFor(t, find.text('创建接活名片'));
      await t.enterText(find.widgetWithText(TextField, '姓名'), worker);
      await tapIt(t, find.text('工种').first);
      await pickManyOne(t, '瓦工／砌墙');
      await tapIt(t, find.text('服务地区').first);
      await pickManyOne(t, '阿拉木图');
      await shot(t, 'm01-profile-form');
      await tapIt(t, find.widgetWithText(FilledButton, '保存'));
      await idle(t, 1000);
      final profiles = await io(t, () => repos.myProfiles());
      expect(profiles, hasLength(1));
      expect(profiles.single.trades, ['mason']);

      // ── 2. Owner publishes a contract demand; it opens ──
      await signOut(t, repos);
      await signIn(t, repos, owner);
      final ownerId = repos.currentAccount!.id;
      await home(t);
      await open(t, const PublishPage());
      await waitFor(t, find.text('下一步'));
      await tapIt(t, find.text('下一步')); // type: contract, owner
      await tapIt(t, find.text('工种').first);
      await pickManyOne(t, '瓦工／砌墙');
      await tapIt(t, find.text('地区').first);
      await tapIt(t, find.text('阿拉木图').last);
      final titleField = find.widgetWithText(TextField, '标题');
      await scrollTo(t, titleField);
      await t.enterText(titleField, demandTitle);
      await t.pumpAndSettle();
      for (var i = 0; i < 6 && find.text('提交发布').evaluate().isEmpty; i++) {
        await tapIt(t, find.text('下一步'));
      }
      await shot(t, 'm02-demand-preview');
      await tapIt(t, find.text('提交发布'));
      await waitFor(t, find.byType(DemandDetailPage));
      final demands = await io(t, () => repos.myDemands());
      final demand = demands.singleWhere((d) => d.current.title == demandTitle);
      expect(demand.status, DemandStatus.open);
      await shot(t, 'm03-demand-open');

      // ── 3. Worker finds it and sends a quote, then messages the owner ──
      await signOut(t, repos);
      await signIn(t, repos, worker);
      await home(t);
      await tab(t, '发现');
      await tapIt(t, find.byKey(const Key('explore-seg-1')));
      await waitFor(t, find.text(demandTitle));
      await shot(t, 'm04-worker-finds-demand');
      await tapIt(t, find.text(demandTitle).first);
      await waitFor(t, find.byType(DemandDetailPage));
      await tapIt(t, find.widgetWithText(FilledButton, '报价'));
      await waitFor(t, find.byType(ApplyPage));
      await t.enterText(find.widgetWithText(TextField, '你承接哪些工作'), '全部砌墙，含二层');
      final lump = find.widgetWithText(TextField, '总价 ₸');
      await scrollTo(t, lump);
      await t.enterText(lump, '1800000');
      final days = find.widgetWithText(TextField, '预计工期（天）');
      await scrollTo(t, days);
      await t.enterText(days, '20');
      await t.pumpAndSettle();
      await shot(t, 'm05-quote-form');
      await tapIt(t, find.text('发送报价'));
      await idle(t, 1000);
      final mine = await io(t, () => repos.myApplications());
      final application = mine.singleWhere((a) => a.demandId == demand.id);
      expect(application.applicantId, workerId);

      await home(t);
      await open(t, DemandDetailPage(demandId: demand.id));
      await waitFor(t, find.byTooltip('联系发布者'));
      await tapIt(t, find.byTooltip('联系发布者'));
      await waitFor(t, find.byType(ChatPage));
      await t.enterText(
          find.descendant(
              of: find.byType(ChatPage), matching: find.byType(TextField)),
          '你好，我明天可以去现场看看 $run');
      await tapIt(t, find.byTooltip('发送'));
      await waitFor(t, find.text('你好，我明天可以去现场看看 $run'));
      await shot(t, 'm06-chat-worker');

      // ── 4. Owner: unread badge, notifications, quote, invite ──
      await signOut(t, repos);
      await signIn(t, repos, owner);
      expect(await io(t, () => repos.unreadMessages()), greaterThan(0));
      await home(t);
      await tab(t, '消息');
      await waitFor(t, find.textContaining('你好，我明天可以去现场看看'));
      await shot(t, 'm07-inbox-owner');
      await tapIt(t, find.text('通知'));
      await idle(t, 1000);
      final notes = await io(t, () => repos.notifications());
      expect(notes, isNotEmpty);
      expect(notes.any((n) => n.refId == demand.id || n.title == demandTitle),
          isTrue,
          reason: 'owner hears about the new quote');
      await shot(t, 'm08-notifications-owner');

      await home(t);
      await open(t, ApplicationsPage(demandId: demand.id));
      await waitFor(t, find.text('选择并发起约定'));
      await shot(t, 'm09-quotes-owner');
      await tapIt(t, find.text('选择并发起约定'));
      await waitFor(t, find.byType(AgreementForm));
      final scope = find.widgetWithText(TextField, '工作范围');
      if ((t.widget<TextField>(scope).controller?.text ?? '').isEmpty) {
        await t.enterText(scope, '全部砌墙，含二层');
      }
      await tapIt(t, find.text('发起并确认我方'));
      await idle(t, 1000);
      var coops = await io(t, () => repos.cooperationsFor(demand.id));
      expect(coops, hasLength(1));
      var coop = coops.single;
      expect(coop.status, CooperationStatus.pending);
      expect(coop.providerId, workerId);

      // ── 5. Worker confirms, asks for the first inspection, logs a day ──
      await signOut(t, repos);
      await signIn(t, repos, worker);
      await openCoop(t, coop.id);
      await tapIt(t, find.text('确认合作'));
      await idle(t, 1000);
      coop = (await io(t, () => repos.cooperation(coop.id)))!;
      expect(coop.status, CooperationStatus.confirmed);
      expect(coop.milestones, isNotEmpty,
          reason: 'a contract comes with inspection points');
      await shot(t, 'm10-coop-confirmed');

      await scrollTap(t, find.text('申请验收').first);
      await submitSiteEntry(t, '基础完成 $run');
      await scrollTap(t, find.byKey(const Key('log-work')));
      // The day's log comes with a site photo from the "gallery".
      final photo = await io(t, sitePhoto);
      FileSelectorPlatform.instance = FakeGallery(photo);
      await waitFor(t, find.byKey(const Key('site-entry-submit')));
      await tapIt(t, find.textContaining('加照片'));
      await idle(t, 1500);
      expect(find.textContaining('加照片 1/'), findsOneWidget);
      await submitSiteEntry(t, '今天砌了一层 $run');
      coop = (await io(t, () => repos.cooperation(coop.id)))!;
      expect(coop.milestones.first.status, MilestoneStatus.requested);
      expect(coop.workLogs, hasLength(1));
      expect(coop.workLogs.single.photos, hasLength(1));
      await shot(t, 'm11-milestone-and-log');

      // ── 6. Owner accepts the inspection, confirms the day, asks to end ──
      await signOut(t, repos);
      await signIn(t, repos, owner);
      await openCoop(t, coop.id);
      await scrollTap(t, find.text('确认验收').first);
      await idle(t, 1000);
      await scrollTap(t, find.widgetWithText(TextButton, '确认').first);
      await idle(t, 1000);
      coop = (await io(t, () => repos.cooperation(coop.id)))!;
      expect(coop.milestones.first.status, MilestoneStatus.accepted);
      expect(coop.workLogs.single.confirmed, isTrue);
      // The owner gets the worker's photo back from the server (/media).
      expect(coop.workLogs.single.photos.single, isNotEmpty);
      await scrollTo(t, find.textContaining('📷1'));
      expect(find.textContaining('📷1'), findsOneWidget);
      await shot(t, 'm11b-owner-sees-photo');
      await scrollTap(t, find.text('请求结束'));
      await answerDialog(t, '工程完成 $run');
      await idle(t, 1000);
      coop = (await io(t, () => repos.cooperation(coop.id)))!;
      expect(coop.endRequest, isNotNull);

      // ── 7. Worker confirms the end and reviews the owner ──
      await signOut(t, repos);
      await signIn(t, repos, worker);
      await openCoop(t, coop.id);
      await scrollTap(t, find.text('确认结束'));
      await idle(t, 1000);
      coop = (await io(t, () => repos.cooperation(coop.id)))!;
      expect(coop.status, CooperationStatus.ended);
      await scrollTap(t, find.text('评价对方（可跳过）'));
      await reviewAll(t, '房主很爽快 $run');
      expect(await io(t, () => repos.reviewsFor(coop.id)), hasLength(1));

      // ── 8. Owner reviews the worker; both reviews are now public ──
      await signOut(t, repos);
      await signIn(t, repos, owner);
      await openCoop(t, coop.id);
      await scrollTap(t, find.text('评价对方（可跳过）'));
      await reviewAll(t, '活干得好 $run');
      final reviews = await io(t, () => repos.reviewsFor(coop.id));
      expect(reviews, hasLength(2));
      expect(await io(t, () => repos.reviewsAbout(workerId)), isNotEmpty);
      await openCoop(t, coop.id);
      await scrollTo(t, find.text('活干得好 $run'));
      await shot(t, 'm12-coop-ended-reviews');

      // ── 9. A third account reports the demand from its menu ──
      await signOut(t, repos);
      await signIn(t, repos, 'Rita $run');
      await home(t);
      await open(t, DemandDetailPage(demandId: demand.id));
      await waitFor(t, find.byType(PopupMenuButton<String>));
      await tapIt(t, find.byType(PopupMenuButton<String>));
      await tapIt(t, find.text('举报'));
      await answerDialog(t, '测试举报 $run');
      await idle(t, 1000);
      await shot(t, 'm13-report-sent');

      // ignore: avoid_print
      print('MARKET_RUN=$run DEMAND=${demand.id} COOP=${coop.id} '
          'OWNER=$ownerId WORKER=$workerId');
      expect(t.takeException(), isNull);
    } catch (_) {
      await shot(t, 'zz-market-failure');
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
    }
  });
}
