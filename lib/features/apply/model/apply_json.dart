import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Apply models to and from yusal-api JSON.

// ── applications ──
ApplicationVersion _appVersion(Map<String, dynamic> j) => ApplicationVersion(
    no: jsonInt(j['no']) ?? 1,
    demandVersionNo: jsonInt(j['demand_version_no']) ?? 1,
    createdAt: jsonTime(j['created_at']),
    note: j['note'] as String? ?? '',
    availableFrom: jsonTimeOrNull(j['available_from']),
    acceptsOffer: j['accepts_offer'] as bool? ?? true,
    expectedWage: jsonInt(j['expected_wage']),
    headcountOffered: jsonInt(j['headcount_offered']) ?? 1,
    scopeText: j['scope_text'] as String? ?? '',
    materials:
        jsonEnum(MaterialMode.values, j['materials'], MaterialMode.labourOnly),
    pricing: jsonEnum(PricingMode.values, j['pricing'], PricingMode.lumpSum),
    lines: [
      for (final l in jsonMaps(j['lines']))
        QuoteLine(
            name: l['name'] as String? ?? '',
            quantity: (l['quantity'] as num? ?? 0).toDouble(),
            unit: l['unit'] as String? ?? '',
            unitPrice: jsonInt(l['unit_price']) ?? 0)
    ],
    lumpSum: jsonInt(j['lump_sum']),
    durationDays: jsonInt(j['duration_days']),
    includes: j['includes'] as String? ?? '',
    excludes: j['excludes'] as String? ?? '',
    validUntil: jsonTimeOrNull(j['valid_until']));

Map<String, dynamic> appVersionJson(ApplicationVersion v) => dropNulls({
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
    status: jsonEnum(
        ApplicationStatus.values, j['status'], ApplicationStatus.submitted),
    versions: [for (final v in jsonMaps(j['versions'])) _appVersion(v)],
    createdAt: jsonTime(j['created_at']),
    needsReconfirm: j['needs_reconfirm'] == true,
    readByOwner: j['read_by_owner'] == true,
    requestId: j['request_id'] as String?);
