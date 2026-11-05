import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/domain/rules.dart';
import 'package:yusal/platform/snapshot/design_snapshot.dart';

MockBackend backend({bool seed = true}) => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero,
    seed: seed);

DemandVersion contractDraft({String title = '车库砌墙', String text = ''}) =>
    DemandVersion(
        no: 0,
        title: title,
        trades: const ['mason'],
        region: 'talgar',
        locality: '塔尔加尔',
        exactAddress: '私密地址 7 号',
        budget: const Budget(mode: BudgetMode.askQuote),
        createdAt: DateTime.utc(2026),
        description: text,
        contract: const ContractTerms(scopeKind: ScopeKind.custom, quantities: [
          QtyItem(
              name: '砌墙', quantity: 20, unit: 'm3', source: QtySource.manual)
        ]));

ApplicationVersion lumpQuote(int amount,
        {MaterialMode materials = MaterialMode.labourOnly}) =>
    ApplicationVersion(
        no: 0,
        demandVersionNo: 0,
        createdAt: DateTime.utc(2026),
        scopeText: '全部砌墙',
        materials: materials,
        pricing: PricingMode.lumpSum,
        lumpSum: amount,
        durationDays: 10);

Agreement terms({int? amount = 900000, int? headcount}) => Agreement(
    version: 0,
    scope: '全部砌墙',
    demandVersionNo: 0,
    proposedBy: '',
    confirmedBy: const {},
    status: AgreementStatus.proposed,
    createdAt: DateTime.utc(2026),
    amount: amount,
    headcount: headcount);

Future<Demand> publishAsOwner(MockBackend b, {String text = ''}) async {
  b.signInAs(SeedIds.owner);
  final draft =
      await b.saveDraft(DemandType.contract, contractDraft(text: text));
  return b.publish(draft.id);
}

void main() {
  group('accounts', () {
    test('signs in with the mock code and refuses a wrong one', () async {
      final b = backend();
      await b.requestCode('+7 701 555 1234');
      await expectLater(
          b.verify('+77015551234', '0000'), throwsA(isA<ApiFailure>()));
      final a = await b.verify('+77015551234', MockBackend.verificationCode,
          displayName: 'Test');
      expect(b.currentAccount?.id, a.id);
      expect(a.displayName, 'Test');
    });

    test('browsing works signed out, acting needs an account', () async {
      final b = backend();
      expect(await b.searchDemands(const DemandFilter()), isNotEmpty);
      await expectLater(
          b.myDemands(),
          throwsA(predicate(
              (e) => (e as ApiFailure).code == ApiCodes.notSignedIn)));
    });

    test('deleting an account takes its demands down', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      await b.deleteAccount();
      expect(b.currentAccount, isNull);
      expect(b.demands['dem_wall']!.status, DemandStatus.closed);
      final list = await b.searchDemands(const DemandFilter());
      expect(list.any((d) => d.ownerId == SeedIds.owner), isFalse);
    });
  });

  group('demands', () {
    test('draft → review → open; private fields stay off share pages',
        () async {
      final b = backend();
      final d = await publishAsOwner(b);
      expect(d.status, DemandStatus.open);
      expect(d.expiresAt, isNotNull);
      b.signInAs(SeedIds.mason);
      expect((await b.demand(d.id))!.current.exactAddress, isEmpty);
      b.signInAs(SeedIds.owner);
      expect((await b.demand(d.id))!.current.exactAddress, isNotEmpty);
      final view = await b.publicView(d.shareToken);
      expect(view!.available, isTrue);
      expect(view.title, '车库砌墙');
      // The public projection has no address field at all; check revoking.
      await b.setShareRevoked(d.id, true);
      final revoked = await b.publicView(d.shareToken);
      expect(revoked!.available, isFalse);
      expect(revoked.title, isEmpty);
    });

    test('a deposit request is rejected by review with a reason', () async {
      final b = backend();
      final d = await publishAsOwner(b, text: '开工前请交押金');
      expect(d.status, DemandStatus.rejected);
      expect(d.rejectReason, contains('押金'));
      expect(b.auditLog.last.action, 'reject');
    });

    test('a demand needs a valid budget but may ask for quotes', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final bad = DemandVersion(
          no: 0,
          title: 'x',
          trades: const ['mason'],
          region: 'talgar',
          budget: const Budget(mode: BudgetMode.range, min: 500, max: 100),
          createdAt: DateTime.utc(2026),
          contract: const ContractTerms(scopeKind: ScopeKind.whole));
      await expectLater(
          b.saveDraft(DemandType.contract, bad), throwsA(isA<ApiFailure>()));
    });

    test('expiry stops new applications but keeps cooperations', () async {
      final b = backend();
      final d = await publishAsOwner(b);
      b.signInAs(SeedIds.mason);
      final app = await b.submit(
          demandId: d.id,
          profileId: 'prof_mason',
          version: lumpQuote(800000),
          requestId: 'r1');
      b.signInAs(SeedIds.owner);
      final coop = await b.invite(app.id, terms());
      b.signInAs(SeedIds.mason);
      await b.confirm(coop.id);
      b.advanceTime(const Duration(days: 31));
      expect(b.demands[d.id]!.status, DemandStatus.expired);
      expect(b.cooperations[coop.id]!.status, CooperationStatus.confirmed);
      b.signInAs(SeedIds.team);
      await expectLater(
          b.submit(
              demandId: d.id,
              profileId: 'prof_team',
              version: lumpQuote(700000),
              requestId: 'r2'),
          throwsA(predicate(
              (e) => (e as ApiFailure).code == ApiCodes.notAccepting)));
      b.signInAs(SeedIds.owner);
      final renewed = await b.renew(d.id);
      expect(renewed.status, DemandStatus.open);
    });

    test('sends the outcome follow-up on day 3 only once', () async {
      final b = backend();
      final d = await publishAsOwner(b);
      b.advanceTime(const Duration(days: 3, hours: 1));
      b.advanceTime(const Duration(hours: 1));
      final followUps = b.notices.values.where(
          (n) => n.kind == NoticeKind.outcomeFollowUp && n.refId == d.id);
      expect(followUps, hasLength(1));
    });

    test('a revision marks live quotes for re-confirmation', () async {
      final b = backend();
      final d = await publishAsOwner(b);
      b.signInAs(SeedIds.team);
      final app = await b.submit(
          demandId: d.id,
          profileId: 'prof_team',
          version: lumpQuote(900000),
          requestId: 'r1');
      b.signInAs(SeedIds.owner);
      await b.revise(d.id, contractDraft(title: '车库砌墙（加高）'));
      final after = b.applications[app.id]!;
      expect(after.needsReconfirm, isTrue);
      expect(after.current.demandVersionNo, 1);
      expect(b.demands[d.id]!.versions, hasLength(2));
      // A new quote version clears the flag and records the new base.
      b.signInAs(SeedIds.team);
      final requoted = await b.submit(
          demandId: d.id,
          profileId: 'prof_team',
          version: lumpQuote(950000),
          requestId: 'r2');
      expect(requoted.needsReconfirm, isFalse);
      expect(requoted.current.demandVersionNo, 2);
      expect(requoted.versions, hasLength(2));
    });
  });

  group('applications and cooperation', () {
    test('a double tap creates one application', () async {
      final b = backend();
      b.signInAs(SeedIds.electrician);
      final p = await b.saveProfile(ServiceProfile(
          id: '',
          ownerId: '',
          kind: ProfileKind.individual,
          name: 'Ерлан 2',
          trades: const ['mason'],
          regions: const ['kaskelen'],
          availability: Availability.now,
          availabilityConfirmedAt: DateTime.utc(2026)));
      final v = ApplicationVersion(
          no: 0, demandVersionNo: 0, createdAt: DateTime.utc(2026));
      final a1 = await b.submit(
          demandId: 'dem_hire', profileId: p.id, version: v, requestId: 'same');
      final a2 = await b.submit(
          demandId: 'dem_hire', profileId: p.id, version: v, requestId: 'same');
      expect(a1.id, a2.id);
      expect(b.applications.values.where((a) => a.profileId == p.id),
          hasLength(1));
    });

    test('nobody can apply to their own demand', () async {
      final b = backend();
      b.signInAs(SeedIds.team);
      await expectLater(
          b.submit(
              demandId: 'dem_rebar',
              profileId: 'prof_team',
              version: ApplicationVersion(
                  no: 0, demandVersionNo: 0, createdAt: DateTime.utc(2026)),
              requestId: 'x'),
          throwsA(
              predicate((e) => (e as ApiFailure).code == ApiCodes.ownDemand)));
    });

    test('cooperation needs both sides; one side cannot confirm twice',
        () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final coop = await b.invite('app_mason_hire', terms(headcount: 1));
      expect(coop.status, CooperationStatus.pending);
      expect(b.applications['app_mason_hire']!.status,
          ApplicationStatus.pendingConfirm);
      await expectLater(b.confirm(coop.id), throwsA(isA<ApiFailure>()));
      b.signInAs(SeedIds.mason);
      final done = await b.confirm(coop.id);
      expect(done.status, CooperationStatus.confirmed);
      expect(b.applications['app_mason_hire']!.status,
          ApplicationStatus.cooperating);
      // Hiring one person keeps the demand open for the second.
      expect(b.demands['dem_hire']!.status, DemandStatus.open);
      expect(
          hiredCount(
              b.cooperations.values.where((c) => c.demandId == 'dem_hire')),
          1);
    });

    test('a declined invitation returns the application', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final coop = await b.invite('app_team_wall', terms());
      b.signInAs(SeedIds.team);
      final declined = await b.decline(coop.id);
      expect(declined.status, CooperationStatus.notFormed);
      expect(
          b.applications['app_team_wall']!.status, ApplicationStatus.submitted);
      b.signInAs(SeedIds.owner);
      final again = await b.invite('app_team_wall', terms(amount: 1000000));
      expect(again.id, isNot(coop.id));
    });

    test('changes need the other side and keep history', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final coop = await b.invite('app_team_wall', terms());
      b.signInAs(SeedIds.team);
      await b.confirm(coop.id);
      await b.proposeChange(coop.id, terms(amount: 1100000));
      await expectLater(
          b.answerChange(coop.id, true), throwsA(isA<ApiFailure>()));
      b.signInAs(SeedIds.owner);
      final c = await b.answerChange(coop.id, true);
      expect(c.agreement.amount, 1100000);
      expect(c.agreements.first.status, AgreementStatus.superseded);
      expect(c.agreements, hasLength(2));
    });

    test('an unanswered end is unilateral and opens no reviews', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final coop = await b.invite('app_team_wall', terms());
      b.signInAs(SeedIds.team);
      await b.confirm(coop.id);
      await b.requestEnd(coop.id, '完工');
      b.advanceTime(const Duration(days: 8));
      final c = b.cooperations[coop.id]!;
      expect(c.status, CooperationStatus.ended);
      expect(c.endKind, EndKind.unilateral);
      expect(reviewsOpen(c, b.now), isFalse);
    });

    test('mutual end opens hidden reviews until both are in', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final coop = await b.invite('app_team_wall', terms());
      b.signInAs(SeedIds.team);
      await b.confirm(coop.id);
      await b.requestEnd(coop.id, '');
      b.signInAs(SeedIds.owner);
      await b.confirmEnd(coop.id);
      await b.submitReview(coop.id, {'payment': 5}, '好');
      b.signInAs(SeedIds.team);
      expect(await b.reviewsFor(coop.id), isEmpty);
      await b.submitReview(coop.id, {'scope': 4}, '');
      expect(await b.reviewsFor(coop.id), hasLength(2));
      expect(
          b.profiles['prof_team']!.works.any((w) => w.cooperationId == coop.id),
          isTrue);
    });

    test('profile stats only count proven facts', () async {
      final b = backend();
      final s = await b.stats('prof_team');
      expect(s.confirmedCooperations, 1);
      expect(s.reviewCount, 1);
      final none = await b.stats('prof_elec');
      expect(none.reviewCount, 0);
      expect(none.dimensionAverages, isEmpty);
    });
  });

  group('chat', () {
    test('blocking stops messages; offline sends fail and retry', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final conv = await b.openConversation(SeedIds.mason);
      b.simulateOffline = true;
      final failed = await b.send(conv.id, MessageKind.text, text: '你好');
      expect(failed.state, SendState.failed);
      b.simulateOffline = false;
      final sent = await b.resend(failed.id);
      expect(sent.state, SendState.sent);
      await b.block(SeedIds.mason);
      await expectLater(
          b.send(conv.id, MessageKind.text, text: 'x'),
          throwsA(
              predicate((e) => (e as ApiFailure).code == ApiCodes.blocked)));
    });

    test('rate limit per minute', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      final conv = await b.openConversation(SeedIds.electrician);
      for (var i = 0; i < chatLimitPerMinute; i++) {
        await b.send(conv.id, MessageKind.text, text: '$i');
      }
      await expectLater(
          b.send(conv.id, MessageKind.text, text: 'more'),
          throwsA(predicate(
              (e) => (e as ApiFailure).code == ApiCodes.rateLimited)));
    });

    test('unread counts follow reading', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      expect(await b.unreadMessages(), greaterThan(0));
      final conv = (await b.conversations()).first;
      await b.markConversationRead(conv.id);
      expect(await b.unreadMessages(), 0);
    });
  });

  group('backups', () {
    test('a cloud copy changed elsewhere is never overwritten', () async {
      final b = backend();
      b.signInAs(SeedIds.owner);
      await b.upload(
          projectId: 'p1', name: 'A', houseText: '{}', designUpdatedAt: 't1');
      b.touchBackupFromOtherDevice('p1', '{"x":1}', 't9');
      await expectLater(
          b.upload(
              projectId: 'p1',
              name: 'A',
              houseText: '{}',
              designUpdatedAt: 't2',
              expectedPreviousUpdatedAt: 't1'),
          throwsA(
              predicate((e) => (e as ApiFailure).code == ApiCodes.conflict)));
      b.simulateOffline = true;
      await expectLater(
          b.upload(
              projectId: 'p2',
              name: 'B',
              houseText: '{}',
              designUpdatedAt: 't'),
          throwsA(
              predicate((e) => (e as ApiFailure).code == ApiCodes.network)));
    });
  });

  group('moderation', () {
    test('only moderators review; decisions are audited', () async {
      final b = backend();
      b.autoReviewDelay = null;
      final d = await publishAsOwner(b);
      expect(d.status, DemandStatus.pendingReview);
      await expectLater(b.approve(d.id), throwsA(isA<ApiFailure>()));
      b.signInAs(SeedIds.admin);
      expect(await b.reviewQueue(), hasLength(1));
      await b.approve(d.id);
      expect(b.demands[d.id]!.status, DemandStatus.open);
      await b.resolveReport('rep_seed', true, '工资信息虚假');
      expect(b.demands['dem_rebar']!.status, DemandStatus.rejected);
      expect((await b.audit()).first.by, SeedIds.admin);
    });
  });

  group('rules', () {
    test('quotes with different scopes are flagged', () {
      final b = backend();
      final issues = compareIssues([
        b.applications['app_team_wall']!,
        b.applications['app_mason_wall']!,
      ]);
      expect(issues, isEmpty);
      final mixed = compareIssues([
        b.applications['app_team_wall']!,
        b.applications['app_team_found']!,
      ]);
      expect(mixed, contains(CompareIssue.materials));
    });

    test('per-quantity quotes add up', () {
      final b = backend();
      expect(b.applications['app_team_wall']!.current.total,
          62.5 * 7000 + 21 * 6500);
    });
  });

  group('design snapshot', () {
    test('extracts quantities of the chosen stages from a template', () {
      var n = 0;
      final doc =
          createTemplate('three', '2026-09-30T00:00:00Z', () => 'id${n++}');
      final walls = extractDesign(doc, ['walls']);
      expect(walls.lines, isNotEmpty);
      expect(walls.lines.every((l) => l.stage == 'walls'), isTrue);
      expect(walls.lines.any((l) => l.source == QtySource.design), isTrue);
      final all = extractDesign(doc, const []);
      expect(all.lines.length, greaterThan(walls.lines.length));
      expect(all.width, doc.footprint.width);
    });
  });
}
