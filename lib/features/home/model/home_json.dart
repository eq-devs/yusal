import 'package:yusal/features/profile/model/profile_json.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Home models to and from yusal-api JSON.

PostBuild postBuildFrom(Map<String, dynamic> j) => PostBuild(
        builders: [
          for (final b in jsonMaps(j['builders']))
            (
              profile: profileFrom(b['profile'] as Map<String, dynamic>),
              scope: b['scope'] as String? ?? '',
              ended: b['ended'] == true
            )
        ],
        agreedAmount: jsonInt(j['agreed_amount']) ?? 0,
        acceptedAmount: jsonInt(j['accepted_amount']) ?? 0,
        finished: j['finished'] == true);
