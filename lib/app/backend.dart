import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/shared/state/session.dart';

/// One object that serves every feature's repository: [HttpBackend] in the
/// app, the in-memory fake in tests. Each feature reads only its own
/// repository, through its provider; this bundle exists so one session
/// backs them all.
abstract interface class Backend
    implements
        Session,
        VoiceRepositories,
        AuthRepository,
        ProfileRepository,
        DemandRepository,
        ApplicationRepository,
        CooperationRepository,
        ReviewRepository,
        ChatRepository,
        NotificationRepository,
        SnapshotRepository,
        BackupRepository,
        PostRepository,
        ModerationRepository,
        FeedbackRepository,
        TrustRepository,
        AdminRepository {}

/// Points the session and every feature's repository provider at [b].
List<Override> backendOverrides(Backend b) => [
      sessionProvider.overrideWithValue(b),
      authRepositoryProvider.overrideWithValue(b),
      profileRepositoryProvider.overrideWithValue(b),
      demandRepositoryProvider.overrideWithValue(b),
      applicationRepositoryProvider.overrideWithValue(b),
      cooperationRepositoryProvider.overrideWithValue(b),
      reviewRepositoryProvider.overrideWithValue(b),
      chatRepositoryProvider.overrideWithValue(b),
      notificationRepositoryProvider.overrideWithValue(b),
      snapshotRepositoryProvider.overrideWithValue(b),
      backupRepositoryProvider.overrideWithValue(b),
      postRepositoryProvider.overrideWithValue(b),
      moderationRepositoryProvider.overrideWithValue(b),
      feedbackRepositoryProvider.overrideWithValue(b),
      trustRepositoryProvider.overrideWithValue(b),
      adminRepositoryProvider.overrideWithValue(b),
    ];
