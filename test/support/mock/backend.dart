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
import 'package:yusal/features/shared/state/session.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/repository/voice_repository.dart';
import 'package:yusal/features/voice/state/session.dart';

/// Every repository in one object: what the in-memory fake serves.
abstract interface class Backend
    implements
        Session,
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

/// Points the session and every repository provider at [b], and the
/// assistant too when [b] also scripts it.
List<Override> mockOverrides(Backend b) => [
      if (b case final VoiceBackend voice)
        voiceRepositoryProvider.overrideWithValue(voice),
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

/// The three repositories the assistant reaches, all served by [b].
VoiceRepositories voiceRepos(Backend b) =>
    VoiceRepositories(session: b, demands: b, cooperations: b);
