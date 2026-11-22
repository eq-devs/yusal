import 'package:yusal/app/backend.dart';
import 'package:yusal/features/admin/repository/admin_repository.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/me/repository/trust_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/voice/repository/voice_repository.dart';
import 'package:yusal/services/api/api_client.dart';

export 'package:yusal/services/api/api_client.dart';

/// Every feature's repository over one yusal-api session.
class HttpBackend extends ApiClient
    with
        HttpAuthRepository,
        HttpProfileRepository,
        HttpDemandRepository,
        HttpApplicationRepository,
        HttpCooperationRepository,
        HttpReviewRepository,
        HttpChatRepository,
        HttpNotificationRepository,
        HttpSnapshotRepository,
        HttpBackupRepository,
        HttpPostRepository,
        HttpModerationRepository,
        HttpFeedbackRepository,
        HttpTrustRepository,
        HttpAdminRepository,
        HttpVoiceRepository
    implements Backend {
  HttpBackend(super.baseUrl, {super.client, super.timeout, super.session});
}
