import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/data/http/codec.dart';
import 'package:yusal/platform/domain/models.dart';

/// The JSON the app sends must decode back to the same model (the server
/// echoes these field names).
void main() {
  final t = DateTime.utc(2026, 11, 5, 10);

  test('demand version round-trips', () {
    final v = DemandVersion(
        no: 2,
        title: 'Коробка',
        trades: const ['mason'],
        region: 'almaty',
        locality: 'Талгар',
        exactAddress: 'Абая 1',
        budget: const Budget(mode: BudgetMode.range, min: 100, max: 200),
        hire: const HireTerms(headcount: 3, payMode: PayMode.daily, wage: 15000),
        contract: ContractTerms(
            scopeKind: ScopeKind.stages,
            stages: const ['walls'],
            quantities: const [
              QtyItem(name: 'Кладка', quantity: null, unit: 'm3', source: QtySource.siteMeasure)
            ],
            quoteDeadline: t),
        snapshotId: 's1',
        visibility: const AttachmentVisibility(plan: false),
        createdAt: t);
    final d = demandFrom(jsonDecode(jsonEncode({
      'id': 'd1',
      'owner_id': 'u1',
      'type': 'contract',
      'status': 'pendingReview',
      'versions': [versionJson(v)],
      'created_at': ts(t),
      'share_token': 'tok',
    })) as Map<String, dynamic>);
    final back = d.current;
    expect(d.status, DemandStatus.pendingReview);
    expect(back.no, 2);
    expect(back.exactAddress, 'Абая 1');
    expect(back.budget.mode, BudgetMode.range);
    expect(back.budget.max, 200);
    expect(back.hire!.wage, 15000);
    expect(back.contract!.quantities.single.quantity, isNull);
    expect(back.contract!.quoteDeadline, t);
    expect(back.visibility.plan, isFalse);
    expect(back.snapshotId, 's1');
  });

  test('cooperation decodes photos, agreements and end request', () {
    final c = cooperationFrom(jsonDecode(jsonEncode({
      'id': 'c1',
      'demand_id': 'd1',
      'application_id': 'a1',
      'owner_id': 'o',
      'provider_id': 'p',
      'profile_id': 'pr',
      'status': 'confirmed',
      'created_at': ts(t),
      'agreements': [
        {
          'version': 1,
          'scope': 'Стены',
          'demand_version_no': 1,
          'proposed_by': 'o',
          'confirmed_by': ['o', 'p'],
          'status': 'active',
          'created_at': ts(t),
          'amount': 900000,
          'pricing': 'lumpSum',
          'amount_unit': 'total',
          'share_exact_address': true,
        }
      ],
      'end_request': {'by': 'p', 'at': ts(t), 'note': 'Готово'},
      'milestones': [
        {'key': 'walls', 'percent': 40, 'status': 'requested', 'photos': [base64Encode([1, 2])]}
      ],
      'work_logs': [],
      'updates': [],
    })) as Map<String, dynamic>);
    expect(c.agreement.amount, 900000);
    expect(c.agreement.confirmedBy, {'o', 'p'});
    expect(c.endRequest!.by, 'p');
    expect(c.milestones.single.photos.single, [1, 2]);
    expect(c.milestones.single.status, MilestoneStatus.requested);
  });

  test('cooperation photos given as /media/ paths come from the media map',
      () {
    final j = {
      'id': 'c1',
      'demand_id': 'd1',
      'application_id': 'a1',
      'owner_id': 'o',
      'provider_id': 'p',
      'profile_id': 'pr',
      'status': 'confirmed',
      'created_at': ts(t),
      'agreements': [],
      'milestones': [
        {'key': 'walls', 'percent': 40, 'status': 'requested', 'photos': ['/media/a', '/media/missing']}
      ],
      'work_logs': [
        {'id': 'w1', 'by': 'p', 'day': ts(t), 'headcount': 2, 'photos': ['/media/b']}
      ],
      'updates': [],
    };
    expect(cooperationMedia(j), ['/media/a', '/media/missing', '/media/b']);
    final c = cooperationFrom(j, media: {
      '/media/a': [1],
      '/media/b': [2]
    });
    expect(c.milestones.single.photos, [
      [1]
    ]);
    expect(c.workLogs.single.photos, [
      [2]
    ]);
  });

  test('profile JSON keeps what the server needs', () {
    final p = ServiceProfile(
        id: '',
        ownerId: '',
        kind: ProfileKind.team,
        name: 'Бригада',
        trades: const ['mason'],
        regions: const ['almaty'],
        availability: Availability.fromDate,
        availableFrom: t,
        availabilityConfirmedAt: t,
        refPrices: const [RefPrice(amount: 6000, unit: 'm3', scope: 'кладка')],
        role: ProRole.contractor);
    final j = profileJson(p);
    expect(j['kind'], 'team');
    expect(j['role'], 'contractor');
    expect(j['available_from'], '2026-11-05T10:00:00.000Z');
    final back = profileFrom({...j, 'id': 'x', 'owner_id': 'u'});
    expect(back.refPrices.single.unit, 'm3');
    expect(back.availability, Availability.fromDate);
  });
}
