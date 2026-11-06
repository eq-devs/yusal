import 'dart:convert';

import '../../domain/models.dart';
import '../repositories.dart';

/// JSON ⇄ models for the yusal-api platform endpoints. Field names are the
/// models' names in snake_case; enums travel by name; bytes as base64;
/// times as UTC ISO-8601.

DateTime? _t(Object? v) => v == null ? null : DateTime.parse(v as String);
DateTime _tt(Object? v) => DateTime.parse(v as String);
String? ts(DateTime? t) => t?.toUtc().toIso8601String();
List<String> _strs(Object? v) => [for (final s in v as List? ?? const []) s as String];
List<Map<String, dynamic>> _maps(Object? v) =>
    [for (final m in v as List? ?? const []) m as Map<String, dynamic>];
int? _i(Object? v) => (v as num?)?.toInt();
T _enum<T extends Enum>(List<T> values, Object? v, T fallback) {
  for (final e in values) {
    if (e.name == v) return e;
  }
  return fallback;
}

/// Photos arrive as `/media/<id>` paths (bytes looked up in [media], which
/// the backend fills before mapping) or, from older records, as base64.
List<List<int>> _photos(Object? v, [Map<String, List<int>> media = const {}]) => [
      for (final p in (v as List? ?? const []).cast<String>())
        if (!p.startsWith('/media/'))
          base64Decode(p)
        else if (media[p] != null)
          media[p]!
    ];

/// The `/media/` paths a cooperation's photos point to.
Iterable<String> cooperationMedia(Map<String, dynamic> j) => [
      for (final m in [..._maps(j['milestones']), ..._maps(j['work_logs'])])
        for (final p in (m['photos'] as List? ?? const []).cast<String>())
          if (p.startsWith('/media/')) p
    ];
List<String> photosJson(List<List<int>> p) => [for (final b in p) base64Encode(b)];

Map<String, dynamic> _drop(Map<String, dynamic> m) =>
    m..removeWhere((_, v) => v == null);

// ── accounts ──

Account accountFrom(Map<String, dynamic> u) => Account(
    id: u['id'] as String,
    phone: u['phone'] as String? ?? '',
    phoneVerified: false,
    displayName: u['display_name'] as String? ?? '',
    deleted: u['deleted'] == true || u['status'] == 'deleted',
    restricted: u['restricted'] == true || u['status'] == 'blocked',
    isAdmin: u['is_admin'] == true,
    createdAt: _tt(u['created_at']));

// ── profiles ──

RefPrice _refPrice(Map<String, dynamic> j) => RefPrice(
    amount: _i(j['amount']) ?? 0,
    unit: j['unit'] as String? ?? 'total',
    scope: j['scope'] as String? ?? '');

Work _work(Map<String, dynamic> j) => Work(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    source: _enum(WorkSource.values, j['source'], WorkSource.uploaded),
    cooperationId: j['cooperation_id'] as String?,
    photoCount: _i(j['photo_count']) ?? 0);

ServiceProfile profileFrom(Map<String, dynamic> j) => ServiceProfile(
    id: j['id'] as String,
    ownerId: j['owner_id'] as String,
    kind: _enum(ProfileKind.values, j['kind'], ProfileKind.individual),
    role: _enum(ProRole.values, j['role'], ProRole.worker),
    name: j['name'] as String? ?? '',
    trades: _strs(j['trades']),
    regions: _strs(j['regions']),
    availability:
        _enum(Availability.values, j['availability'], Availability.now),
    availableFrom: _t(j['available_from']),
    availabilityConfirmedAt: _tt(j['availability_confirmed_at']),
    experienceYears: _i(j['experience_years']),
    teamSize: _i(j['team_size']),
    refPrices: [for (final r in _maps(j['ref_prices'])) _refPrice(r)],
    bio: j['bio'] as String? ?? '',
    works: [for (final w in _maps(j['works'])) _work(w)],
    status: _enum(ProfileStatus.values, j['status'], ProfileStatus.active),
    showPhone: j['show_phone'] == true);

Map<String, dynamic> profileJson(ServiceProfile p) => _drop({
      'id': p.id,
      'kind': p.kind.name,
      'role': p.role.name,
      'name': p.name,
      'trades': p.trades,
      'regions': p.regions,
      'availability': p.availability.name,
      'available_from': ts(p.availableFrom),
      'availability_confirmed_at': ts(p.availabilityConfirmedAt),
      'experience_years': p.experienceYears,
      'team_size': p.teamSize,
      'ref_prices': [
        for (final r in p.refPrices)
          {'amount': r.amount, 'unit': r.unit, 'scope': r.scope}
      ],
      'bio': p.bio,
      'works': [
        for (final w in p.works)
          _drop({
            'id': w.id,
            'title': w.title,
            'source': w.source.name,
            'cooperation_id': w.cooperationId,
            'photo_count': w.photoCount,
          })
      ],
      'status': p.status.name,
      'show_phone': p.showPhone,
      'created_at': ts(DateTime.now()),
    });

ProfileStats statsFrom(Map<String, dynamic> j) => ProfileStats(
    phoneVerified: j['phone_verified'] == true,
    confirmedCooperations: _i(j['confirmed_cooperations']) ?? 0,
    reviewCount: _i(j['review_count']) ?? 0,
    dimensionAverages: {
      for (final e in (j['dimension_averages'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toDouble()
    });

// ── demands ──

Budget _budget(Map<String, dynamic> j) => Budget(
    mode: _enum(BudgetMode.values, j['mode'], BudgetMode.askQuote),
    min: _i(j['min']),
    max: _i(j['max']),
    amount: _i(j['amount']),
    basis: j['basis'] as String? ?? 'total',
    materials: _enum(MaterialMode.values, j['materials'], MaterialMode.undecided));

Map<String, dynamic> _budgetJson(Budget b) => _drop({
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
    source: _enum(QtySource.values, j['source'], QtySource.manual),
    stage: j['stage'] as String?);

Map<String, dynamic> qtyJson(QtyItem q) => _drop({
      'name': q.name,
      'quantity': q.quantity,
      'unit': q.unit,
      'source': q.source.name,
      'stage': q.stage,
    })..putIfAbsent('quantity', () => null);

HireTerms? _hire(Object? v) {
  if (v == null) return null;
  final j = v as Map<String, dynamic>;
  return HireTerms(
      headcount: _i(j['headcount']) ?? 1,
      payMode: _enum(PayMode.values, j['pay_mode'], PayMode.daily),
      wage: _i(j['wage']),
      wageUnit: j['wage_unit'] as String? ?? 'day',
      days: _i(j['days']),
      foodLodging: j['food_lodging'] == true,
      toolsByEmployer: j['tools_by_employer'] == true,
      settleCycle: j['settle_cycle'] as String? ?? 'weekly');
}

Map<String, dynamic>? _hireJson(HireTerms? h) => h == null
    ? null
    : _drop({
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
      scopeKind: _enum(ScopeKind.values, j['scope_kind'], ScopeKind.whole),
      stages: _strs(j['stages']),
      quantities: [for (final q in _maps(j['quantities'])) qtyFrom(q)],
      materials:
          _enum(MaterialMode.values, j['materials'], MaterialMode.labourOnly),
      targetDays: _i(j['target_days']),
      quoteDeadline: _t(j['quote_deadline']));
}

Map<String, dynamic>? _contractJson(ContractTerms? c) => c == null
    ? null
    : _drop({
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
      no: _i(j['no']) ?? 1,
      title: j['title'] as String? ?? '',
      trades: _strs(j['trades']),
      region: j['region'] as String? ?? '',
      locality: j['locality'] as String? ?? '',
      exactAddress: j['exact_address'] as String? ?? '',
      startDate: _t(j['start_date']),
      durationDays: _i(j['duration_days']),
      description: j['description'] as String? ?? '',
      photoCount: _i(j['photo_count']) ?? 0,
      siteNotes: j['site_notes'] as String? ?? '',
      budget: _budget(j['budget'] as Map<String, dynamic>? ?? const {}),
      hire: _hire(j['hire']),
      contract: _contract(j['contract']),
      snapshotId: j['snapshot_id'] as String?,
      visibility: AttachmentVisibility(
          quantities: vis['quantities'] as bool? ?? true,
          plan: vis['plan'] as bool? ?? true,
          render: vis['render'] as bool? ?? false),
      createdAt: _tt(j['created_at']));
}

Map<String, dynamic> versionJson(DemandVersion v) => _drop({
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
    type: _enum(DemandType.values, j['type'], DemandType.hire),
    status: _enum(DemandStatus.values, j['status'], DemandStatus.draft),
    versions: [for (final v in _maps(j['versions'])) _version(v)],
    createdAt: _tt(j['created_at']),
    shareToken: j['share_token'] as String? ?? '',
    publishedAt: _t(j['published_at']),
    expiresAt: _t(j['expires_at']),
    publisherRole: _enum(PublisherRole.values, j['publisher_role'], PublisherRole.owner),
    closeReason: j['close_reason'] as String?,
    rejectReason: j['reject_reason'] as String?,
    outcome: j['outcome'] == null
        ? null
        : _enum(OutcomeKind.values, j['outcome'], OutcomeKind.notFound),
    outcomeAt: _t(j['outcome_at']),
    shareRevoked: j['share_revoked'] == true,
    followUpsSent: _i(j['follow_ups_sent']) ?? 0,
    designProjectId: j['design_project_id'] as String?);

PublicDemandView publicViewFrom(Map<String, dynamic> j, DesignSnapshot? snap) =>
    PublicDemandView(
        available: j['available'] == true,
        type: _enum(DemandType.values, j['type'], DemandType.hire),
        title: j['title'] as String? ?? '',
        trades: _strs(j['trades']),
        region: j['region'] as String? ?? '',
        locality: j['locality'] as String? ?? '',
        description: j['description'] as String? ?? '',
        budget: _budget(j['budget'] as Map<String, dynamic>? ?? const {}),
        hire: _hire(j['hire']),
        contract: _contract(j['contract']),
        snapshot: snap,
        status: j['status'] == null
            ? null
            : _enum(DemandStatus.values, j['status'], DemandStatus.open));

// ── applications ──

ApplicationVersion _appVersion(Map<String, dynamic> j) => ApplicationVersion(
    no: _i(j['no']) ?? 1,
    demandVersionNo: _i(j['demand_version_no']) ?? 1,
    createdAt: _tt(j['created_at']),
    note: j['note'] as String? ?? '',
    availableFrom: _t(j['available_from']),
    acceptsOffer: j['accepts_offer'] as bool? ?? true,
    expectedWage: _i(j['expected_wage']),
    headcountOffered: _i(j['headcount_offered']) ?? 1,
    scopeText: j['scope_text'] as String? ?? '',
    materials:
        _enum(MaterialMode.values, j['materials'], MaterialMode.labourOnly),
    pricing: _enum(PricingMode.values, j['pricing'], PricingMode.lumpSum),
    lines: [
      for (final l in _maps(j['lines']))
        QuoteLine(
            name: l['name'] as String? ?? '',
            quantity: (l['quantity'] as num? ?? 0).toDouble(),
            unit: l['unit'] as String? ?? '',
            unitPrice: _i(l['unit_price']) ?? 0)
    ],
    lumpSum: _i(j['lump_sum']),
    durationDays: _i(j['duration_days']),
    includes: j['includes'] as String? ?? '',
    excludes: j['excludes'] as String? ?? '',
    validUntil: _t(j['valid_until']));

Map<String, dynamic> appVersionJson(ApplicationVersion v) => _drop({
      'no': v.no,
      'demand_version_no': v.demandVersionNo,
      'created_at': ts(v.createdAt),
      'note': v.note,
      'available_from': ts(v.availableFrom),
      'accepts_offer': v.acceptsOffer,
      'expected_wage': v.expectedWage,
      'headcount_offered': v.headcountOffered,
      'scope_text': v.scopeText,
      'materials': v.materials.name,
      'pricing': v.pricing.name,
      'lines': [
        for (final l in v.lines)
          {
            'name': l.name,
            'quantity': l.quantity,
            'unit': l.unit,
            'unit_price': l.unitPrice
          }
      ],
      'lump_sum': v.lumpSum,
      'duration_days': v.durationDays,
      'includes': v.includes,
      'excludes': v.excludes,
      'valid_until': ts(v.validUntil),
    });

Application applicationFrom(Map<String, dynamic> j) => Application(
    id: j['id'] as String,
    demandId: j['demand_id'] as String,
    profileId: j['profile_id'] as String,
    applicantId: j['applicant_id'] as String,
    status: _enum(
        ApplicationStatus.values, j['status'], ApplicationStatus.submitted),
    versions: [for (final v in _maps(j['versions'])) _appVersion(v)],
    createdAt: _tt(j['created_at']),
    needsReconfirm: j['needs_reconfirm'] == true,
    readByOwner: j['read_by_owner'] == true,
    requestId: j['request_id'] as String?);

// ── cooperations ──

Agreement _agreement(Map<String, dynamic> j) => Agreement(
    version: _i(j['version']) ?? 1,
    scope: j['scope'] as String? ?? '',
    demandVersionNo: _i(j['demand_version_no']) ?? 1,
    proposedBy: j['proposed_by'] as String? ?? '',
    confirmedBy: _strs(j['confirmed_by']).toSet(),
    status: _enum(AgreementStatus.values, j['status'], AgreementStatus.proposed),
    createdAt: _tt(j['created_at']),
    headcount: _i(j['headcount']),
    amount: _i(j['amount']),
    pricing: _enum(PricingMode.values, j['pricing'], PricingMode.lumpSum),
    amountUnit: j['amount_unit'] as String? ?? 'total',
    startDate: _t(j['start_date']),
    endDate: _t(j['end_date']),
    paymentTerms: j['payment_terms'] as String? ?? '',
    materialsResponsibility: j['materials_responsibility'] as String? ?? '',
    openItems: j['open_items'] as String? ?? '',
    shareExactAddress: j['share_exact_address'] == true);

Map<String, dynamic> agreementJson(Agreement a) => _drop({
      'scope': a.scope,
      'headcount': a.headcount,
      'amount': a.amount,
      'pricing': a.pricing.name,
      'amount_unit': a.amountUnit,
      'start_date': ts(a.startDate),
      'end_date': ts(a.endDate),
      'payment_terms': a.paymentTerms,
      'materials_responsibility': a.materialsResponsibility,
      'open_items': a.openItems,
      'share_exact_address': a.shareExactAddress,
    });

Milestone _milestone(Map<String, dynamic> j, Map<String, List<int>> media) =>
    Milestone(
    key: j['key'] as String? ?? '',
    percent: _i(j['percent']) ?? 0,
    criteria: j['criteria'] as String? ?? '',
    due: _t(j['due']),
    status: _enum(MilestoneStatus.values, j['status'], MilestoneStatus.planned),
    photos: _photos(j['photos'], media),
    note: j['note'] as String? ?? '',
    requestedAt: _t(j['requested_at']),
    answeredAt: _t(j['answered_at']));

Map<String, dynamic> milestoneJson(Milestone m) => _drop({
      'key': m.key,
      'percent': m.percent,
      'criteria': m.criteria,
      'due': ts(m.due),
    });

Cooperation cooperationFrom(Map<String, dynamic> j,
    {Map<String, List<int>> media = const {}}) {
  final r = j['end_request'] as Map<String, dynamic>?;
  return Cooperation(
      id: j['id'] as String,
      demandId: j['demand_id'] as String,
      applicationId: j['application_id'] as String,
      ownerId: j['owner_id'] as String,
      providerId: j['provider_id'] as String,
      profileId: j['profile_id'] as String,
      status: _enum(
          CooperationStatus.values, j['status'], CooperationStatus.pending),
      agreements: [for (final a in _maps(j['agreements'])) _agreement(a)],
      createdAt: _tt(j['created_at']),
      endRequest: r == null
          ? null
          : EndRequest(
              by: r['by'] as String,
              at: _tt(r['at']),
              note: r['note'] as String? ?? '',
              dispute: r['dispute'] as String?),
      endKind: j['end_kind'] == null
          ? null
          : _enum(EndKind.values, j['end_kind'], EndKind.mutual),
      endedAt: _t(j['ended_at']),
      updates: [
        for (final u in _maps(j['updates']))
          ProgressUpdate(
              by: u['by'] as String,
              at: _tt(u['at']),
              text: u['text'] as String? ?? '')
      ],
      milestones: [
        for (final m in _maps(j['milestones'])) _milestone(m, media)
      ],
      workLogs: [
        for (final w in _maps(j['work_logs']))
          WorkLog(
              id: w['id'] as String,
              by: w['by'] as String,
              day: _tt(w['day']),
              headcount: _i(w['headcount']) ?? 1,
              note: w['note'] as String? ?? '',
              photos: _photos(w['photos'], media),
              confirmed: w['confirmed'] == true)
      ]);
}

// ── reviews, chat, notices, moderation ──

Review reviewFrom(Map<String, dynamic> j) => Review(
    id: j['id'] as String,
    cooperationId: j['cooperation_id'] as String,
    authorId: j['author_id'] as String,
    targetId: j['target_id'] as String,
    scores: {
      for (final e in (j['scores'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toInt()
    },
    text: j['text'] as String? ?? '',
    createdAt: _tt(j['created_at']));

ChatMessage messageFrom(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    conversationId: j['conversation_id'] as String,
    senderId: j['sender_id'] as String,
    kind: _enum(MessageKind.values, j['kind'], MessageKind.text),
    sentAt: _tt(j['sent_at']),
    text: j['text'] as String? ?? '',
    refId: j['ref_id'] as String?);

Conversation conversationFrom(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    participants: _strs(j['participants']),
    createdAt: _tt(j['created_at']),
    demandId: j['demand_id'] as String?,
    lastMessage: j['last_message'] == null
        ? null
        : messageFrom(j['last_message'] as Map<String, dynamic>),
    unread: _i(j['unread']) ?? 0);

AppNotification noticeFrom(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    accountId: j['account_id'] as String,
    kind: _enum(NoticeKind.values, j['kind'], NoticeKind.newApplication),
    refType: _enum(RefType.values, j['ref_type'], RefType.demand),
    refId: j['ref_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    read: j['read'] == true,
    createdAt: _tt(j['created_at']));

Report reportFrom(Map<String, dynamic> j) => Report(
    id: j['id'] as String,
    reporterId: j['reporter_id'] as String,
    target: _enum(ReportTarget.values, j['target'], ReportTarget.account),
    targetId: j['target_id'] as String,
    reason: j['reason'] as String? ?? '',
    createdAt: _tt(j['created_at']),
    status: _enum(ReportStatus.values, j['status'], ReportStatus.open),
    handledBy: j['handled_by'] as String?,
    handledAt: _t(j['handled_at']),
    resolution: j['resolution'] as String? ?? '');

AuditEntry auditFrom(Map<String, dynamic> j) => AuditEntry(
    by: j['by'] as String? ?? '',
    at: _tt(j['at']),
    action: j['action'] as String? ?? '',
    targetId: j['target_id'] as String? ?? '',
    reason: j['reason'] as String? ?? '');

PostBuild postBuildFrom(Map<String, dynamic> j) => PostBuild(
    builders: [
      for (final b in _maps(j['builders']))
        (
          profile: profileFrom(b['profile'] as Map<String, dynamic>),
          scope: b['scope'] as String? ?? '',
          ended: b['ended'] == true
        )
    ],
    agreedAmount: _i(j['agreed_amount']) ?? 0,
    acceptedAmount: _i(j['accepted_amount']) ?? 0,
    finished: j['finished'] == true);
