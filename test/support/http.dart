import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:yusal/features/admin/repository/admin_repository.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/trust/repository/trust_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/shared/state/session.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/repository/voice_repository.dart';
import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/api/session_store.dart';

/// The real repositories over one [ApiClient], for tests that talk HTTP
/// (to a fake server or a live one). [overrides] puts these same instances
/// behind the app's providers.
class TestHttp {
  TestHttp(String baseUrl,
      {http.Client? client,
      Duration timeout = const Duration(seconds: 45),
      SessionStore session = const SessionStore()})
      : api = ApiClient(baseUrl,
            client: client, timeout: timeout, session: session);

  final ApiClient api;
  late final auth = HttpAuthRepository(api);
  late final profiles = HttpProfileRepository(api);
  late final demands = HttpDemandRepository(api);
  late final applications = HttpApplicationRepository(api);
  late final cooperations = HttpCooperationRepository(api);
  late final reviews = HttpReviewRepository(api);
  late final chat = HttpChatRepository(api);
  late final notifications = HttpNotificationRepository(api);
  late final snapshots = HttpSnapshotRepository(api);
  late final backups = HttpBackupRepository(api);
  late final posts = HttpPostRepository(api);
  late final moderation = HttpModerationRepository(api);
  late final feedback = HttpFeedbackRepository(api);
  late final trust = HttpTrustRepository(api);
  late final admin = HttpAdminRepository(api);
  late final voice = HttpVoiceRepository(api);

  VoiceRepositories get voiceRepos => VoiceRepositories(
      session: api, demands: demands, cooperations: cooperations);

  List<Override> get overrides => [
        sessionProvider.overrideWithValue(api),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        demandRepositoryProvider.overrideWithValue(demands),
        applicationRepositoryProvider.overrideWithValue(applications),
        cooperationRepositoryProvider.overrideWithValue(cooperations),
        reviewRepositoryProvider.overrideWithValue(reviews),
        chatRepositoryProvider.overrideWithValue(chat),
        notificationRepositoryProvider.overrideWithValue(notifications),
        snapshotRepositoryProvider.overrideWithValue(snapshots),
        backupRepositoryProvider.overrideWithValue(backups),
        postRepositoryProvider.overrideWithValue(posts),
        moderationRepositoryProvider.overrideWithValue(moderation),
        feedbackRepositoryProvider.overrideWithValue(feedback),
        trustRepositoryProvider.overrideWithValue(trust),
        adminRepositoryProvider.overrideWithValue(admin),
        voiceRepositoryProvider.overrideWithValue(voice),
      ];
}
