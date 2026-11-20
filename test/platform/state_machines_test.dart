import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/data/mock/mock_seed.dart';
import 'package:yusal/data/repositories.dart';
import 'package:yusal/domain/models.dart';
import 'package:yusal/domain/rules.dart';

import 'mock_backend_test.dart' show backend, publishAsOwner;

void main() {
  test('the machines are the ones in docs/state_machines.json', () {
    // yusal-api checks its copy of the file against market/lifecycle.go,
    // so the app and the server refuse the same moves.
    final doc = jsonDecode(File('docs/state_machines.json').readAsStringSync());
    expect({
      'machines': [for (final m in marketMachines) m.toJson()]
    }, doc);
  });

  test('every status is reachable and every event leads somewhere', () {
    for (final StateMachine m in marketMachines) {
      final reached = {m.initial};
      final names = <String>{};
      for (final t in m.events) {
        expect(names.add(t.event.name), isTrue, reason: '${m.name} ${t.event}');
        expect(t.from, isNotEmpty);
        reached.add(t.to);
      }
      expect(reached, containsAll(m.statuses), reason: m.name);
    }
  });

  test('allowed events are what each status lets a person do', () {
    expect(demandMachine.allowed(DemandStatus.draft),
        [DemandEvent.publish, DemandEvent.close]);
    expect(demandMachine.allowed(DemandStatus.closed), isEmpty);
    expect(demandMachine.allowed(DemandStatus.found),
        [DemandEvent.recheck, DemandEvent.resume, DemandEvent.close]);
    expect(applicationMachine.allowed(ApplicationStatus.cooperating), isEmpty);
    expect(milestoneMachine.allowed(MilestoneStatus.accepted), isEmpty);
    expect(
        milestoneMachine.next(MilestoneStatus.disputed, MilestoneEvent.request),
        MilestoneStatus.requested);
    expect(
        reportMachine.next(ReportStatus.upheld, ReportEvent.dismiss), isNull);
  });

  test('a refused demand move names it and changes nothing', () async {
    final b = backend();
    final d = await publishAsOwner(b);
    await b.markFound(d.id, OutcomeKind.platformConfirmed);
    await expectLater(
        b.pause(d.id),
        throwsA(predicate((e) =>
            e is ApiFailure &&
            e.code == ApiCodes.invalidState &&
            e.details == 'found→paused')));
    expect(b.demands[d.id]!.status, DemandStatus.found);
  });

  test('a published demand goes back to review only by a new version',
      () async {
    final b = backend();
    final d = await publishAsOwner(b);
    expect(d.status, DemandStatus.open);
    await expectLater(b.publish(d.id), throwsA(isA<ApiFailure>()));
    expect(b.demands[d.id]!.status, DemandStatus.open);
  });

  test('an upheld report takes a paused demand down too', () async {
    final b = backend();
    b.signInAs(SeedIds.team);
    await b.pause('dem_rebar');
    b.signInAs(SeedIds.admin);
    await b.resolveReport('rep_seed', true, '工资信息虚假');
    expect(b.demands['dem_rebar']!.status, DemandStatus.rejected);
    expect(b.reportsById['rep_seed']!.status, ReportStatus.upheld);
    await expectLater(b.resolveReport('rep_seed', false, 'again'),
        throwsA(isA<ApiFailure>()));
  });

  test('a confirmed cooperation\'s ending: none, asked, disputed, asked again',
      () {
    final at = DateTime.utc(2026);
    Cooperation coop(CooperationStatus status, EndRequest? r) => Cooperation(
        id: 'c',
        demandId: 'd',
        applicationId: 'a',
        ownerId: 'owner',
        providerId: 'worker',
        profileId: 'p',
        status: status,
        agreements: const [],
        createdAt: at,
        endRequest: r);
    final asked = EndRequest(by: 'worker', at: at);
    final disputed = EndRequest(by: 'worker', at: at, dispute: '还没完工');
    expect(coop(CooperationStatus.confirmed, null).endPhase, EndPhase.none);
    expect(coop(CooperationStatus.confirmed, asked).endPhase, EndPhase.asked);
    expect(coop(CooperationStatus.confirmed, disputed).endPhase,
        EndPhase.disputed);
    // An ended one keeps its last request but has nothing left to answer.
    expect(coop(CooperationStatus.ended, asked).endPhase, EndPhase.none);
    expect(
        coop(CooperationStatus.confirmed, asked).endAskedOf('owner'), isTrue);
    expect(
        coop(CooperationStatus.confirmed, asked).endAskedOf('worker'), isFalse);
  });
}
