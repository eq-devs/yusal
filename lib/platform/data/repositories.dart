import 'package:flutter/foundation.dart' show Listenable;
import '../domain/models.dart';

/// Repository interfaces of the platform. The interface only talks to these;
/// today they are served by `MockBackend`, later by a real backend. Every
/// method is asynchronous and fails with [ApiFailure]. Permissions, state
/// changes and two-sided confirmations are decided behind these interfaces,
/// never by the client.

class ApiFailure implements Exception {
  const ApiFailure(this.code, [this.details = '']);

  /// Stable code; see [ApiCodes].
  final String code;
  final String details;
  @override
  String toString() =>
      'ApiFailure($code${details.isEmpty ? '' : ': $details'})';
}

abstract final class ApiCodes {
  static const notSignedIn = 'NOT_SIGNED_IN';
  static const badCode = 'BAD_CODE';
  static const badPhone = 'BAD_PHONE';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const invalidState = 'INVALID_STATE';
  static const invalidInput = 'INVALID_INPUT';
  static const notAccepting = 'NOT_ACCEPTING';
  static const ownDemand = 'OWN_DEMAND';
  static const blocked = 'BLOCKED';
  static const rateLimited = 'RATE_LIMITED';
  static const network = 'NETWORK';
  static const restricted = 'RESTRICTED';
  static const conflict = 'CONFLICT';
}

/// Fires whenever any data behind the repositories changes.
abstract interface class ChangeSource {
  Listenable get changes;
}

abstract interface class AuthRepository {
  Account? get currentAccount;
  Future<void> requestCode(String phone);
  Future<Account> verify(String phone, String code, {String? displayName});
  Future<void> signOut();
  Future<Account> updateName(String name);

  /// Takes profiles and open demands down; cooperation records stay, shown
  /// with an anonymous name.
  Future<void> deleteAccount();
  Future<Account?> account(String id);
}

abstract interface class ProfileRepository {
  Future<List<ServiceProfile>> myProfiles();
  Future<ServiceProfile?> profile(String id);
  Future<List<ServiceProfile>> profilesOf(String accountId);
  Future<List<ServiceProfile>> searchProfiles(ProfileFilter filter);

  /// Creates when [profile.id] is empty, else updates the caller's own.
  Future<ServiceProfile> saveProfile(ServiceProfile profile);

  /// "Still taking work": refreshes the confirmation time.
  Future<ServiceProfile> confirmAvailability(String profileId);
  Future<ProfileStats> stats(String profileId);
  Future<Set<String>> favourites();
  Future<void> toggleFavourite(String id);
}

abstract interface class DemandRepository {
  Future<List<Demand>> searchDemands(DemandFilter filter);
  Future<Demand?> demand(String id);
  Future<List<Demand>> myDemands();

  /// Saves a draft (only visible to the owner).
  Future<Demand> saveDraft(DemandType type, DemandVersion draft,
      {PublisherRole role = PublisherRole.owner,
      String? existingId,
      String? designProjectId});

  /// Sends a draft for review.
  Future<Demand> publish(String demandId);

  /// Publishes a new version; live applications are marked for re-confirm.
  Future<Demand> revise(String demandId, DemandVersion next);
  Future<Demand> pause(String demandId);
  Future<Demand> resume(String demandId);
  Future<Demand> renew(String demandId);
  Future<Demand> markFound(String demandId, OutcomeKind outcome);
  Future<Demand> close(String demandId, String reason);
  Future<Demand> recordOutcome(String demandId, OutcomeKind outcome);
  Future<Demand> setShareRevoked(String demandId, bool revoked);

  /// What an outside web visitor may see through a share link; null when the
  /// link is unknown. The result only carries public fields.
  Future<PublicDemandView?> publicView(String shareToken);
}

/// Public projection of a demand for share pages and signed-out browsing.
class PublicDemandView {
  const PublicDemandView(
      {required this.available,
      required this.type,
      required this.title,
      required this.trades,
      required this.region,
      required this.locality,
      required this.description,
      required this.budget,
      this.hire,
      this.contract,
      this.snapshot,
      this.status});
  final bool available;
  final DemandType type;
  final String title, region, locality, description;
  final List<String> trades;
  final Budget budget;
  final HireTerms? hire;
  final ContractTerms? contract;
  final DesignSnapshot? snapshot;
  final DemandStatus? status;
}

abstract interface class ApplicationRepository {
  /// The publisher's view of all applications of one demand.
  Future<List<Application>> applicationsFor(String demandId);
  Future<List<Application>> myApplications();
  Future<Application?> application(String id);

  /// Idempotent per [requestId]; one live application per profile and
  /// demand, later submissions become new versions.
  Future<Application> submit(
      {required String demandId,
      required String profileId,
      required ApplicationVersion version,
      required String requestId});
  Future<Application> withdraw(String applicationId);
  Future<Application> markNotSelected(String applicationId);
}

abstract interface class CooperationRepository {
  /// The publisher proposes an agreement on an application and confirms
  /// their own side.
  Future<Cooperation> invite(String applicationId, Agreement terms);
  Future<Cooperation> confirm(String cooperationId);
  Future<Cooperation> decline(String cooperationId);

  /// The publisher takes back an unanswered invitation.
  Future<Cooperation> revoke(String cooperationId);
  Future<Cooperation> proposeChange(String cooperationId, Agreement terms);
  Future<Cooperation> answerChange(String cooperationId, bool accept);
  Future<Cooperation> requestEnd(String cooperationId, String note);
  Future<Cooperation> confirmEnd(String cooperationId);
  Future<Cooperation> disputeEnd(String cooperationId, String note);
  Future<Cooperation> addUpdate(String cooperationId, String text);
  Future<Cooperation?> cooperation(String id);
  Future<List<Cooperation>> myCooperations();
  Future<List<Cooperation>> cooperationsFor(String demandId);
}

abstract interface class ReviewRepository {
  Future<Review> submitReview(
      String cooperationId, Map<String, int> scores, String text);

  /// Reviews of one cooperation the caller may see: their own, plus the
  /// other side's once visible.
  Future<List<Review>> reviewsFor(String cooperationId);

  /// Public reviews about an account.
  Future<List<Review>> reviewsAbout(String accountId);
}

abstract interface class ChatRepository {
  Future<List<Conversation>> conversations();
  Future<Conversation> openConversation(String otherAccountId,
      {String? demandId});
  Future<List<ChatMessage>> messages(String conversationId);
  Future<ChatMessage> send(String conversationId, MessageKind kind,
      {String text = '', String? refId});

  /// Retries a failed message.
  Future<ChatMessage> resend(String messageId);
  Future<void> markConversationRead(String conversationId);
  Future<void> block(String accountId);
  Future<void> unblock(String accountId);
  Future<Set<String>> blocked();

  /// Shows the caller's phone number to one partner, on purpose.
  Future<ChatMessage> sharePhone(String conversationId);
  Future<int> unreadMessages();
}

abstract interface class NotificationRepository {
  Future<List<AppNotification>> notifications();
  Future<int> unreadNotifications();
  Future<void> markRead(String id);
  Future<void> markAllRead();
}

abstract interface class SnapshotRepository {
  Future<DesignSnapshot> saveSnapshot(DesignSnapshot snapshot);
  Future<DesignSnapshot?> snapshot(String id);
}

/// Result of comparing a local design with its cloud backup.
enum BackupState { none, inSync, localNewer, cloudNewer, diverged }

abstract interface class BackupRepository {
  Future<List<BackupRecord>> backups();
  Future<BackupRecord?> backup(String projectId);
  Future<BackupRecord> upload(
      {required String projectId,
      required String name,
      required String houseText,
      required String designUpdatedAt,
      String? expectedPreviousUpdatedAt});
}

abstract interface class ModerationRepository {
  Future<void> report(ReportTarget target, String targetId, String reason);
  Future<List<Demand>> reviewQueue();
  Future<void> approve(String demandId);
  Future<void> reject(String demandId, String reason);
  Future<List<Report>> reports();
  Future<void> resolveReport(String reportId, bool upheld, String note);
  Future<List<AuditEntry>> audit();
}

/// Everything the platform interface needs, in one bundle.
abstract interface class PlatformRepositories
    implements
        ChangeSource,
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
        ModerationRepository {}
