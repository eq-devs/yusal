import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Profile models to and from yusal-api JSON.

// ── profiles ──
RefPrice _refPrice(Map<String, dynamic> j) => RefPrice(
    amount: jsonInt(j['amount']) ?? 0,
    unit: j['unit'] as String? ?? 'total',
    scope: j['scope'] as String? ?? '');

Work _work(Map<String, dynamic> j) => Work(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    source: jsonEnum(WorkSource.values, j['source'], WorkSource.uploaded),
    cooperationId: j['cooperation_id'] as String?,
    photoCount: jsonInt(j['photo_count']) ?? 0);

ServiceProfile profileFrom(Map<String, dynamic> j) => ServiceProfile(
    id: j['id'] as String,
    ownerId: j['owner_id'] as String,
    kind: jsonEnum(ProfileKind.values, j['kind'], ProfileKind.individual),
    role: jsonEnum(ProRole.values, j['role'], ProRole.worker),
    name: j['name'] as String? ?? '',
    trades: jsonStrings(j['trades']),
    regions: jsonStrings(j['regions']),
    availability:
        jsonEnum(Availability.values, j['availability'], Availability.now),
    availableFrom: jsonTimeOrNull(j['available_from']),
    availabilityConfirmedAt: jsonTime(j['availability_confirmed_at']),
    experienceYears: jsonInt(j['experience_years']),
    teamSize: jsonInt(j['team_size']),
    refPrices: [for (final r in jsonMaps(j['ref_prices'])) _refPrice(r)],
    bio: j['bio'] as String? ?? '',
    works: [for (final w in jsonMaps(j['works'])) _work(w)],
    status: jsonEnum(ProfileStatus.values, j['status'], ProfileStatus.active),
    showPhone: j['show_phone'] == true,
    verified: j['verified'] == true);

Map<String, dynamic> profileJson(ServiceProfile p) => dropNulls({
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
          dropNulls({
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
        confirmedCooperations: jsonInt(j['confirmed_cooperations']) ?? 0,
        reviewCount: jsonInt(j['review_count']) ?? 0,
        dimensionAverages: {
          for (final e in (j['dimension_averages'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        });
