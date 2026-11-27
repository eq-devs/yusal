import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Coop models to and from yusal-api JSON.

/// The `/media/` paths a cooperation's photos point to.
Iterable<String> cooperationMedia(Map<String, dynamic> j) => [
      for (final m in [
        ...jsonMaps(j['milestones']),
        ...jsonMaps(j['work_logs'])
      ])
        for (final p in jsonStrings(m['photos']))
          if (p.startsWith('/media/')) p
    ];

// ── cooperations ──
Agreement _agreement(Map<String, dynamic> j) => Agreement(
    version: jsonInt(j['version']) ?? 1,
    scope: j['scope'] as String? ?? '',
    demandVersionNo: jsonInt(j['demand_version_no']) ?? 1,
    proposedBy: j['proposed_by'] as String? ?? '',
    confirmedBy: jsonStrings(j['confirmed_by']).toSet(),
    status:
        jsonEnum(AgreementStatus.values, j['status'], AgreementStatus.proposed),
    createdAt: jsonTime(j['created_at']),
    headcount: jsonInt(j['headcount']),
    amount: jsonInt(j['amount']),
    pricing: jsonEnum(PricingMode.values, j['pricing'], PricingMode.lumpSum),
    amountUnit: j['amount_unit'] as String? ?? 'total',
    startDate: jsonTimeOrNull(j['start_date']),
    endDate: jsonTimeOrNull(j['end_date']),
    paymentTerms: j['payment_terms'] as String? ?? '',
    materialsResponsibility: j['materials_responsibility'] as String? ?? '',
    openItems: j['open_items'] as String? ?? '',
    shareExactAddress: j['share_exact_address'] == true);

Map<String, dynamic> agreementJson(Agreement a) => dropNulls({
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
        percent: jsonInt(j['percent']) ?? 0,
        criteria: j['criteria'] as String? ?? '',
        due: jsonTimeOrNull(j['due']),
        status: jsonEnum(
            MilestoneStatus.values, j['status'], MilestoneStatus.planned),
        photos: jsonPhotos(j['photos'], media),
        note: j['note'] as String? ?? '',
        requestedAt: jsonTimeOrNull(j['requested_at']),
        answeredAt: jsonTimeOrNull(j['answered_at']));

Map<String, dynamic> milestoneJson(Milestone m) => dropNulls({
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
      status: jsonEnum(
          CooperationStatus.values, j['status'], CooperationStatus.pending),
      agreements: [for (final a in jsonMaps(j['agreements'])) _agreement(a)],
      createdAt: jsonTime(j['created_at']),
      endRequest: r == null
          ? null
          : EndRequest(
              by: r['by'] as String,
              at: jsonTime(r['at']),
              note: r['note'] as String? ?? '',
              dispute: r['dispute'] as String?),
      endKind: j['end_kind'] == null
          ? null
          : jsonEnum(EndKind.values, j['end_kind'], EndKind.mutual),
      endedAt: jsonTimeOrNull(j['ended_at']),
      updates: [
        for (final u in jsonMaps(j['updates']))
          ProgressUpdate(
              by: u['by'] as String,
              at: jsonTime(u['at']),
              text: u['text'] as String? ?? '')
      ],
      milestones: [
        for (final m in jsonMaps(j['milestones'])) _milestone(m, media)
      ],
      workLogs: [
        for (final w in jsonMaps(j['work_logs']))
          WorkLog(
              id: w['id'] as String,
              by: w['by'] as String,
              day: jsonTime(w['day']),
              headcount: jsonInt(w['headcount']) ?? 1,
              note: w['note'] as String? ?? '',
              photos: jsonPhotos(w['photos'], media),
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
    createdAt: jsonTime(j['created_at']));
