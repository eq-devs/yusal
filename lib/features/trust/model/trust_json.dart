import 'package:yusal/features/shared/model/admin_models.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Trust and safety models to and from yusal-api JSON.

Appeal appealFrom(Map<String, dynamic> j) => Appeal(
    id: j['id'] as String,
    accountId: j['account_id'] as String? ?? '',
    accountName: j['account_name'] as String? ?? '',
    target: j['target'] as String? ?? '',
    targetId: j['target_id'] as String? ?? '',
    targetTitle: j['target_title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    status: jsonEnum(AppealStatus.values, j['status'], AppealStatus.open),
    createdAt: jsonTime(j['created_at']),
    handledAt: jsonTimeOrNull(j['handled_at']),
    resolution: j['resolution'] as String? ?? '');

Verification verificationFrom(Map<String, dynamic> j) => Verification(
    id: j['id'] as String,
    profileId: j['profile_id'] as String? ?? '',
    ownerId: j['owner_id'] as String? ?? '',
    ownerName: j['owner_name'] as String? ?? '',
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    photos: jsonStrings(j['photos']),
    note: j['note'] as String? ?? '',
    status: jsonEnum(
        VerificationStatus.values, j['status'], VerificationStatus.pending),
    createdAt: jsonTime(j['created_at']),
    resolution: j['resolution'] as String? ?? '');

DemandAlert alertFrom(Map<String, dynamic> j) => DemandAlert(
        on: j['on'] == true,
        regions: jsonStrings(j['regions']),
        trades: jsonStrings(j['trades']),
        types: [
          for (final t in jsonStrings(j['types']))
            for (final e in DemandType.values)
              if (e.name == t) e
        ]);

Map<String, dynamic> alertJson(DemandAlert a) => {
      'on': a.on,
      'regions': a.regions,
      'trades': a.trades,
      'types': [for (final t in a.types) t.name],
    };

NotificationSettings settingsFrom(Map<String, dynamic> j) =>
    NotificationSettings(
        muted: jsonStrings(j['muted']),
        quietStart: j['quiet_start'] as String? ?? '',
        quietEnd: j['quiet_end'] as String? ?? '');
