import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Demand models to and from yusal-api JSON.

// ── demands ──
Budget _budget(Map<String, dynamic> j) => Budget(
    mode: jsonEnum(BudgetMode.values, j['mode'], BudgetMode.askQuote),
    min: jsonInt(j['min']),
    max: jsonInt(j['max']),
    amount: jsonInt(j['amount']),
    basis: j['basis'] as String? ?? 'total',
    materials:
        jsonEnum(MaterialMode.values, j['materials'], MaterialMode.undecided));

Map<String, dynamic> _budgetJson(Budget b) => dropNulls({
      'mode': b.mode.name,
      'min': b.min,
      'max': b.max,
      'amount': b.amount,
      'basis': b.basis,
      'materials': b.materials.name,
    });

QtyItem qtyFrom(Map<String, dynamic> j) => QtyItem(
    name: j['name'] as String? ?? '',
    quantity: (j['quantity'] as num?)?.toDouble(),
    unit: j['unit'] as String? ?? '',
    source: jsonEnum(QtySource.values, j['source'], QtySource.manual),
    stage: j['stage'] as String?);

Map<String, dynamic> qtyJson(QtyItem q) => dropNulls({
      'name': q.name,
      'quantity': q.quantity,
      'unit': q.unit,
      'source': q.source.name,
      'stage': q.stage,
    })
      ..putIfAbsent('quantity', () => null);

HireTerms? _hire(Object? v) {
  if (v == null) return null;
  final j = v as Map<String, dynamic>;
  return HireTerms(
      headcount: jsonInt(j['headcount']) ?? 1,
      payMode: jsonEnum(PayMode.values, j['pay_mode'], PayMode.daily),
      wage: jsonInt(j['wage']),
      wageUnit: j['wage_unit'] as String? ?? 'day',
      days: jsonInt(j['days']),
      foodLodging: j['food_lodging'] == true,
      toolsByEmployer: j['tools_by_employer'] == true,
      settleCycle: j['settle_cycle'] as String? ?? 'weekly');
}

Map<String, dynamic>? _hireJson(HireTerms? h) => h == null
    ? null
    : dropNulls({
        'headcount': h.headcount,
        'pay_mode': h.payMode.name,
        'wage': h.wage,
        'wage_unit': h.wageUnit,
        'days': h.days,
        'food_lodging': h.foodLodging,
        'tools_by_employer': h.toolsByEmployer,
        'settle_cycle': h.settleCycle,
      });

ContractTerms? _contract(Object? v) {
  if (v == null) return null;
  final j = v as Map<String, dynamic>;
  return ContractTerms(
      scopeKind: jsonEnum(ScopeKind.values, j['scope_kind'], ScopeKind.whole),
      stages: jsonStrings(j['stages']),
      quantities: [for (final q in jsonMaps(j['quantities'])) qtyFrom(q)],
      materials: jsonEnum(
          MaterialMode.values, j['materials'], MaterialMode.labourOnly),
      targetDays: jsonInt(j['target_days']),
      quoteDeadline: jsonTimeOrNull(j['quote_deadline']));
}

Map<String, dynamic>? _contractJson(ContractTerms? c) => c == null
    ? null
    : dropNulls({
        'scope_kind': c.scopeKind.name,
        'stages': c.stages,
        'quantities': [for (final q in c.quantities) qtyJson(q)],
        'materials': c.materials.name,
        'target_days': c.targetDays,
        'quote_deadline': ts(c.quoteDeadline),
      });

DemandVersion _version(Map<String, dynamic> j) {
  final vis = j['visibility'] as Map<String, dynamic>? ?? const {};
  return DemandVersion(
      no: jsonInt(j['no']) ?? 1,
      title: j['title'] as String? ?? '',
      trades: jsonStrings(j['trades']),
      region: j['region'] as String? ?? '',
      locality: j['locality'] as String? ?? '',
      exactAddress: j['exact_address'] as String? ?? '',
      startDate: jsonTimeOrNull(j['start_date']),
      durationDays: jsonInt(j['duration_days']),
      description: j['description'] as String? ?? '',
      photoCount: jsonInt(j['photo_count']) ?? 0,
      siteNotes: j['site_notes'] as String? ?? '',
      budget: _budget(j['budget'] as Map<String, dynamic>? ?? const {}),
      hire: _hire(j['hire']),
      contract: _contract(j['contract']),
      snapshotId: j['snapshot_id'] as String?,
      visibility: AttachmentVisibility(
          quantities: vis['quantities'] as bool? ?? true,
          plan: vis['plan'] as bool? ?? true,
          render: vis['render'] as bool? ?? false),
      createdAt: jsonTime(j['created_at']));
}

Map<String, dynamic> versionJson(DemandVersion v) => dropNulls({
      'no': v.no,
      'title': v.title,
      'trades': v.trades,
      'region': v.region,
      'locality': v.locality,
      'exact_address': v.exactAddress,
      'start_date': ts(v.startDate),
      'duration_days': v.durationDays,
      'description': v.description,
      'photo_count': v.photoCount,
      'site_notes': v.siteNotes,
      'budget': _budgetJson(v.budget),
      'hire': _hireJson(v.hire),
      'contract': _contractJson(v.contract),
      'snapshot_id': v.snapshotId,
      'visibility': {
        'quantities': v.visibility.quantities,
        'plan': v.visibility.plan,
        'render': v.visibility.render,
      },
      'created_at': ts(v.createdAt),
    });

Demand demandFrom(Map<String, dynamic> j) => Demand(
    id: j['id'] as String,
    ownerId: j['owner_id'] as String,
    type: jsonEnum(DemandType.values, j['type'], DemandType.hire),
    status: jsonEnum(DemandStatus.values, j['status'], DemandStatus.draft),
    versions: [for (final v in jsonMaps(j['versions'])) _version(v)],
    createdAt: jsonTime(j['created_at']),
    shareToken: j['share_token'] as String? ?? '',
    publishedAt: jsonTimeOrNull(j['published_at']),
    expiresAt: jsonTimeOrNull(j['expires_at']),
    publisherRole: jsonEnum(
        PublisherRole.values, j['publisher_role'], PublisherRole.owner),
    closeReason: j['close_reason'] as String?,
    rejectReason: j['reject_reason'] as String?,
    outcome: j['outcome'] == null
        ? null
        : jsonEnum(OutcomeKind.values, j['outcome'], OutcomeKind.notFound),
    outcomeAt: jsonTimeOrNull(j['outcome_at']),
    shareRevoked: j['share_revoked'] == true,
    followUpsSent: jsonInt(j['follow_ups_sent']) ?? 0,
    designProjectId: j['design_project_id'] as String?);

PublicDemandView publicViewFrom(Map<String, dynamic> j, DesignSnapshot? snap) =>
    PublicDemandView(
        available: j['available'] == true,
        type: jsonEnum(DemandType.values, j['type'], DemandType.hire),
        title: j['title'] as String? ?? '',
        trades: jsonStrings(j['trades']),
        region: j['region'] as String? ?? '',
        locality: j['locality'] as String? ?? '',
        description: j['description'] as String? ?? '',
        budget: _budget(j['budget'] as Map<String, dynamic>? ?? const {}),
        hire: _hire(j['hire']),
        contract: _contract(j['contract']),
        snapshot: snap,
        status: j['status'] == null
            ? null
            : jsonEnum(DemandStatus.values, j['status'], DemandStatus.open));
