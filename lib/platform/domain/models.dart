/// Platform domain: accounts, service profiles, demands, applications
/// (sign-ups and quotes), cooperations, chat, reviews, notifications,
/// design snapshots and backups. Pure Dart, no Flutter; every object has a
/// stable id and versioned objects keep their whole history.
library;

// ───────────────────────── accounts and profiles ─────────────────────────

class Account {
  const Account(
      {required this.id,
      required this.phone,
      required this.displayName,
      required this.createdAt,
      this.phoneVerified = true,
      this.deleted = false,
      this.restricted = false,
      this.isAdmin = false});
  final String id, phone, displayName;
  final DateTime createdAt;
  final bool phoneVerified, deleted, restricted, isAdmin;

  /// What others see once the account is deleted.
  String get publicName => deleted ? '—' : displayName;

  Account copyWith({String? displayName, bool? deleted, bool? restricted}) =>
      Account(
          id: id,
          phone: phone,
          displayName: displayName ?? this.displayName,
          createdAt: createdAt,
          phoneVerified: phoneVerified,
          deleted: deleted ?? this.deleted,
          restricted: restricted ?? this.restricted,
          isAdmin: isAdmin);
}

enum ProfileKind { individual, team }

/// What a professional does on the platform: a worker takes paid work,
/// a contractor leads a crew and takes contracts, an engineer or
/// designer checks and improves designs.
enum ProRole { worker, contractor, engineer }

enum Availability { now, fromDate, notTaking }

enum ProfileStatus { active, hidden }

/// A reference price always carries its unit and what it covers, e.g.
/// "labour only, masonry from 6 000 ₸ per m³".
class RefPrice {
  const RefPrice(
      {required this.amount, required this.unit, required this.scope});
  final int amount;

  /// Unit code, see [priceUnits].
  final String unit;

  /// Free text: what the price covers.
  final String scope;
}

enum WorkSource { uploaded, platform }

class Work {
  const Work(
      {required this.id,
      required this.title,
      required this.source,
      this.cooperationId,
      this.photoCount = 0});
  final String id, title;
  final WorkSource source;
  final String? cooperationId;
  final int photoCount;
}

class ServiceProfile {
  const ServiceProfile(
      {required this.id,
      required this.ownerId,
      required this.kind,
      required this.name,
      required this.trades,
      required this.regions,
      required this.availability,
      required this.availabilityConfirmedAt,
      this.availableFrom,
      this.experienceYears,
      this.teamSize,
      this.refPrices = const [],
      this.bio = '',
      this.works = const [],
      this.status = ProfileStatus.active,
      this.showPhone = false,
      this.role = ProRole.worker});
  final String id, ownerId, name, bio;
  final ProfileKind kind;
  final ProRole role;
  final List<String> trades, regions;
  final Availability availability;
  final DateTime? availableFrom;
  final DateTime availabilityConfirmedAt;
  final int? experienceYears, teamSize;
  final List<RefPrice> refPrices;
  final List<Work> works;
  final ProfileStatus status;

  /// The owner chose to show the phone number on the profile page.
  final bool showPhone;

  bool availableOn(DateTime day) => switch (availability) {
        Availability.now => true,
        Availability.fromDate =>
          availableFrom == null || !availableFrom!.isAfter(day),
        Availability.notTaking => false,
      };

  ServiceProfile copyWith(
          {ProfileKind? kind,
          String? name,
          List<String>? trades,
          List<String>? regions,
          Availability? availability,
          DateTime? availableFrom,
          bool clearAvailableFrom = false,
          DateTime? availabilityConfirmedAt,
          int? experienceYears,
          int? teamSize,
          List<RefPrice>? refPrices,
          String? bio,
          List<Work>? works,
          ProfileStatus? status,
          bool? showPhone}) =>
      ServiceProfile(
          id: id,
          ownerId: ownerId,
          kind: kind ?? this.kind,
          name: name ?? this.name,
          trades: trades ?? this.trades,
          regions: regions ?? this.regions,
          availability: availability ?? this.availability,
          availableFrom:
              clearAvailableFrom ? null : availableFrom ?? this.availableFrom,
          availabilityConfirmedAt:
              availabilityConfirmedAt ?? this.availabilityConfirmedAt,
          experienceYears: experienceYears ?? this.experienceYears,
          teamSize: teamSize ?? this.teamSize,
          refPrices: refPrices ?? this.refPrices,
          bio: bio ?? this.bio,
          works: works ?? this.works,
          status: status ?? this.status,
          showPhone: showPhone ?? this.showPhone);
}

/// Facts the platform can prove about a profile; nothing invented.
class ProfileStats {
  const ProfileStats(
      {required this.phoneVerified,
      required this.confirmedCooperations,
      required this.reviewCount,
      required this.dimensionAverages});
  final bool phoneVerified;
  final int confirmedCooperations, reviewCount;

  /// Average per review dimension, only when there are reviews.
  final Map<String, double> dimensionAverages;
}

// ──────────────────────────────── demands ────────────────────────────────

enum DemandType {
  /// 招人干活: hire workers, they sign up.
  hire,

  /// 找人承包: find someone to take on a scope, they quote.
  contract
}

enum DemandStatus {
  draft,
  pendingReview,
  open,
  paused,
  found,
  expired,
  closed,
  rejected
}

enum BudgetMode { range, fixed, askQuote }

enum MaterialMode { labourOnly, labourAndMaterial, undecided }

enum PayMode { daily, piece, other }

enum ScopeKind { whole, stages, custom }

enum PublisherRole { owner, contractor }

enum QtySource { design, manual, siteMeasure }

class Budget {
  const Budget(
      {required this.mode,
      this.min,
      this.max,
      this.amount,
      this.basis = 'total',
      this.materials = MaterialMode.undecided});
  final BudgetMode mode;
  final int? min, max, amount;

  /// Price unit code the numbers refer to, see [priceUnits].
  final String basis;
  final MaterialMode materials;
}

class QtyItem {
  const QtyItem(
      {required this.name,
      required this.quantity,
      required this.unit,
      required this.source,
      this.stage});
  final String name;

  /// Null when it will be measured on site.
  final double? quantity;
  final String unit;
  final QtySource source;
  final String? stage;
}

/// What the publisher chose to make public from an attached design.
class AttachmentVisibility {
  const AttachmentVisibility(
      {this.quantities = true, this.plan = true, this.render = false});
  final bool quantities, plan, render;
}

class HireTerms {
  const HireTerms(
      {required this.headcount,
      required this.payMode,
      this.wage,
      this.wageUnit = 'day',
      this.days,
      this.foodLodging = false,
      this.toolsByEmployer = false,
      this.settleCycle = 'weekly'});
  final int headcount;
  final PayMode payMode;

  /// Null means negotiable.
  final int? wage;
  final String wageUnit;
  final int? days;
  final bool foodLodging, toolsByEmployer;

  /// daily, weekly, monthly, onFinish.
  final String settleCycle;
}

class ContractTerms {
  const ContractTerms(
      {required this.scopeKind,
      this.stages = const [],
      this.quantities = const [],
      this.materials = MaterialMode.labourOnly,
      this.targetDays,
      this.quoteDeadline});
  final ScopeKind scopeKind;

  /// Stage codes from the build schedule: found, walls, roof, …
  final List<String> stages;
  final List<QtyItem> quantities;
  final MaterialMode materials;
  final int? targetDays;
  final DateTime? quoteDeadline;
}

/// One published version of a demand; earlier versions stay readable.
class DemandVersion {
  const DemandVersion(
      {required this.no,
      required this.title,
      required this.trades,
      required this.region,
      required this.budget,
      required this.createdAt,
      this.locality = '',
      this.exactAddress = '',
      this.startDate,
      this.durationDays,
      this.description = '',
      this.photoCount = 0,
      this.siteNotes = '',
      this.hire,
      this.contract,
      this.snapshotId,
      this.visibility = const AttachmentVisibility()});
  final int no;
  final String title;
  final List<String> trades;

  /// Region code; [locality] is the public village / district text.
  final String region, locality;

  /// Never public; shared with a partner on purpose.
  final String exactAddress;

  /// Null means to be agreed.
  final DateTime? startDate;
  final int? durationDays;
  final String description, siteNotes;
  final int photoCount;
  final Budget budget;
  final HireTerms? hire;
  final ContractTerms? contract;
  final String? snapshotId;
  final AttachmentVisibility visibility;
  final DateTime createdAt;
}

/// How the publisher says the search ended.
enum OutcomeKind {
  platformConfirmed,
  selfReportedYusal,
  otherChannel,
  notFound,
  notNeeded
}

class Demand {
  const Demand(
      {required this.id,
      required this.ownerId,
      required this.type,
      required this.status,
      required this.versions,
      required this.createdAt,
      required this.shareToken,
      this.publishedAt,
      this.expiresAt,
      this.publisherRole = PublisherRole.owner,
      this.closeReason,
      this.rejectReason,
      this.outcome,
      this.outcomeAt,
      this.shareRevoked = false,
      this.followUpsSent = 0,
      this.designProjectId});
  final String id, ownerId, shareToken;
  final DemandType type;
  final DemandStatus status;
  final List<DemandVersion> versions;
  final DateTime createdAt;
  final DateTime? publishedAt, expiresAt;
  final PublisherRole publisherRole;
  final String? closeReason, rejectReason;
  final OutcomeKind? outcome;
  final DateTime? outcomeAt;
  final bool shareRevoked;
  final int followUpsSent;

  /// Local design project the demand was published from, if any.
  final String? designProjectId;

  DemandVersion get current => versions.last;

  Demand copyWith(
          {DemandStatus? status,
          List<DemandVersion>? versions,
          DateTime? publishedAt,
          DateTime? expiresAt,
          String? closeReason,
          String? rejectReason,
          OutcomeKind? outcome,
          DateTime? outcomeAt,
          bool? shareRevoked,
          int? followUpsSent}) =>
      Demand(
          id: id,
          ownerId: ownerId,
          type: type,
          status: status ?? this.status,
          versions: versions ?? this.versions,
          createdAt: createdAt,
          shareToken: shareToken,
          publishedAt: publishedAt ?? this.publishedAt,
          expiresAt: expiresAt ?? this.expiresAt,
          publisherRole: publisherRole,
          closeReason: closeReason ?? this.closeReason,
          rejectReason: rejectReason ?? this.rejectReason,
          outcome: outcome ?? this.outcome,
          outcomeAt: outcomeAt ?? this.outcomeAt,
          shareRevoked: shareRevoked ?? this.shareRevoked,
          followUpsSent: followUpsSent ?? this.followUpsSent,
          designProjectId: designProjectId);
}

/// Search filter for the "find work" list.
class DemandFilter {
  const DemandFilter(
      {this.type,
      this.trade,
      this.region,
      this.query = '',
      this.includeInactive = false});
  final DemandType? type;
  final String? trade, region;
  final String query;
  final bool includeInactive;
}

/// Search filter for the "find people" list.
class ProfileFilter {
  const ProfileFilter(
      {this.kind,
      this.trade,
      this.region,
      this.availableNow = false,
      this.query = ''});
  final ProfileKind? kind;
  final String? trade, region;
  final bool availableNow;
  final String query;
}

// ───────────────────────── applications and quotes ─────────────────────────

enum ApplicationStatus {
  submitted,
  withdrawn,
  notSelected,
  pendingConfirm,
  cooperating
}

enum PricingMode { perQuantity, lumpSum, siteConfirm }

class QuoteLine {
  const QuoteLine(
      {required this.name,
      required this.quantity,
      required this.unit,
      required this.unitPrice});
  final String name, unit;
  final double quantity;
  final int unitPrice;
  double get total => quantity * unitPrice;
}

/// One version of a sign-up (hire) or quote (contract).
class ApplicationVersion {
  const ApplicationVersion(
      {required this.no,
      required this.demandVersionNo,
      required this.createdAt,
      this.note = '',
      this.availableFrom,
      this.acceptsOffer = true,
      this.expectedWage,
      this.headcountOffered = 1,
      this.scopeText = '',
      this.materials = MaterialMode.labourOnly,
      this.pricing = PricingMode.lumpSum,
      this.lines = const [],
      this.lumpSum,
      this.durationDays,
      this.includes = '',
      this.excludes = '',
      this.validUntil});
  final int no, demandVersionNo;
  final DateTime createdAt;
  final String note;

  // Sign-up fields.
  final DateTime? availableFrom;
  final bool acceptsOffer;
  final int? expectedWage;
  final int headcountOffered;

  // Quote fields.
  final String scopeText;
  final MaterialMode materials;
  final PricingMode pricing;
  final List<QuoteLine> lines;
  final int? lumpSum;
  final int? durationDays;
  final String includes, excludes;
  final DateTime? validUntil;

  /// Quantity × unit price for line quotes, the lump sum otherwise; null
  /// when the price waits for a site visit.
  double? get total => switch (pricing) {
        PricingMode.perQuantity => lines.fold<double>(0, (s, l) => s + l.total),
        PricingMode.lumpSum => lumpSum?.toDouble(),
        PricingMode.siteConfirm => null,
      };
}

class Application {
  const Application(
      {required this.id,
      required this.demandId,
      required this.profileId,
      required this.applicantId,
      required this.status,
      required this.versions,
      required this.createdAt,
      this.needsReconfirm = false,
      this.readByOwner = false,
      this.requestId});
  final String id, demandId, profileId, applicantId;
  final ApplicationStatus status;
  final List<ApplicationVersion> versions;
  final DateTime createdAt;

  /// The demand changed after this was sent.
  final bool needsReconfirm;
  final bool readByOwner;

  /// Client token that makes a double tap create one application only.
  final String? requestId;

  ApplicationVersion get current => versions.last;

  Application copyWith(
          {ApplicationStatus? status,
          List<ApplicationVersion>? versions,
          bool? needsReconfirm,
          bool? readByOwner}) =>
      Application(
          id: id,
          demandId: demandId,
          profileId: profileId,
          applicantId: applicantId,
          status: status ?? this.status,
          versions: versions ?? this.versions,
          createdAt: createdAt,
          needsReconfirm: needsReconfirm ?? this.needsReconfirm,
          readByOwner: readByOwner ?? this.readByOwner,
          requestId: requestId);
}

// ────────────────────────────── cooperations ──────────────────────────────

enum CooperationStatus { pending, confirmed, ended, notFormed }

enum EndKind { mutual, unilateral, cancelled, disputed }

enum AgreementStatus { proposed, active, superseded, rejected }

/// One version of the cooperation agreement ("合作约定"). It is not
/// presented as a legal contract.
class Agreement {
  const Agreement(
      {required this.version,
      required this.scope,
      required this.demandVersionNo,
      required this.proposedBy,
      required this.confirmedBy,
      required this.status,
      required this.createdAt,
      this.headcount,
      this.amount,
      this.pricing = PricingMode.lumpSum,
      this.amountUnit = 'total',
      this.startDate,
      this.endDate,
      this.paymentTerms = '',
      this.materialsResponsibility = '',
      this.openItems = '',
      this.shareExactAddress = false});
  final int version, demandVersionNo;
  final String scope, proposedBy;
  final Set<String> confirmedBy;
  final AgreementStatus status;
  final DateTime createdAt;
  final int? headcount, amount;
  final PricingMode pricing;
  final String amountUnit;
  final DateTime? startDate, endDate;
  final String paymentTerms, materialsResponsibility, openItems;

  /// The publisher grants the partner the exact address.
  final bool shareExactAddress;

  Agreement copyWith({Set<String>? confirmedBy, AgreementStatus? status}) =>
      Agreement(
          version: version,
          scope: scope,
          demandVersionNo: demandVersionNo,
          proposedBy: proposedBy,
          confirmedBy: confirmedBy ?? this.confirmedBy,
          status: status ?? this.status,
          createdAt: createdAt,
          headcount: headcount,
          amount: amount,
          pricing: pricing,
          amountUnit: amountUnit,
          startDate: startDate,
          endDate: endDate,
          paymentTerms: paymentTerms,
          materialsResponsibility: materialsResponsibility,
          openItems: openItems,
          shareExactAddress: shareExactAddress);
}

class EndRequest {
  const EndRequest(
      {required this.by, required this.at, this.note = '', this.dispute});
  final String by;
  final DateTime at;
  final String note;

  /// The other side's objection, when raised.
  final String? dispute;
}

class ProgressUpdate {
  const ProgressUpdate(
      {required this.by, required this.at, required this.text});
  final String by, text;
  final DateTime at;
}

enum MilestoneStatus { planned, requested, accepted, disputed }

/// A payment and inspection point of a contract: what must be done, what
/// share of the amount it unlocks and when. Yusal only records the
/// inspection; money moves outside the app until escrow exists.
class Milestone {
  const Milestone(
      {required this.key,
      required this.percent,
      this.criteria = '',
      this.due,
      this.status = MilestoneStatus.planned,
      this.photos = const [],
      this.note = '',
      this.answeredAt,
      this.requestedAt});

  /// A built-in point ("foundation", "walls", "roof", "finish") or a
  /// custom one written as "c:<name>".
  final String key;
  final String criteria, note;
  final int percent;

  /// Photos attached to the latest inspection request (compressed JPEG/WebP).
  final List<List<int>> photos;
  final DateTime? due, requestedAt, answeredAt;
  final MilestoneStatus status;
  int get photoCount => photos.length;

  /// Same point with a new plan (name, share, criteria, date).
  Milestone replan(
          {String? key, int? percent, String? criteria, DateTime? due}) =>
      Milestone(
          key: key ?? this.key,
          percent: percent ?? this.percent,
          criteria: criteria ?? this.criteria,
          due: due ?? this.due,
          status: status,
          photos: photos,
          note: note,
          requestedAt: requestedAt,
          answeredAt: answeredAt);

  Milestone copyWith(
          {MilestoneStatus? status,
          List<List<int>>? photos,
          String? note,
          DateTime? requestedAt,
          DateTime? answeredAt}) =>
      Milestone(
          key: key,
          percent: percent,
          criteria: criteria,
          due: due,
          status: status ?? this.status,
          photos: photos ?? this.photos,
          note: note ?? this.note,
          requestedAt: requestedAt ?? this.requestedAt,
          answeredAt: answeredAt ?? this.answeredAt);
}

/// A day on site logged by the pro: how many people came, photos and a
/// note. The owner confirms it, which settles wage questions later.
class WorkLog {
  const WorkLog(
      {required this.id,
      required this.by,
      required this.day,
      required this.headcount,
      this.note = '',
      this.photos = const [],
      this.confirmed = false});
  final String id, by, note;
  final DateTime day;
  final int headcount;
  final List<List<int>> photos;
  final bool confirmed;
  int get photoCount => photos.length;
  WorkLog confirm() => WorkLog(
      id: id,
      by: by,
      day: day,
      headcount: headcount,
      note: note,
      photos: photos,
      confirmed: true);
}

/// Default inspection points for a house: foundation, walls, roof, done.
const defaultMilestones = [
  Milestone(key: 'foundation', percent: 20),
  Milestone(key: 'walls', percent: 40),
  Milestone(key: 'roof', percent: 25),
  Milestone(key: 'finish', percent: 15),
];

class Cooperation {
  const Cooperation(
      {required this.id,
      required this.demandId,
      required this.applicationId,
      required this.ownerId,
      required this.providerId,
      required this.profileId,
      required this.status,
      required this.agreements,
      required this.createdAt,
      this.endRequest,
      this.endKind,
      this.endedAt,
      this.updates = const [],
      this.milestones = const [],
      this.workLogs = const []});
  final String id, demandId, applicationId, ownerId, providerId, profileId;
  final CooperationStatus status;
  final List<Agreement> agreements;
  final DateTime createdAt;
  final EndRequest? endRequest;
  final EndKind? endKind;
  final DateTime? endedAt;
  final List<ProgressUpdate> updates;
  final List<Milestone> milestones;
  final List<WorkLog> workLogs;

  /// Share of the agreed amount whose milestones the owner accepted.
  int get acceptedPercent => milestones
      .where((m) => m.status == MilestoneStatus.accepted)
      .fold(0, (s, m) => s + m.percent);

  /// The agreement in force, or the first one while still pending.
  Agreement get agreement =>
      agreements.lastWhere((a) => a.status == AgreementStatus.active,
          orElse: () => agreements.first);

  /// A change waiting for the other side, if any.
  Agreement? get pendingChange => status == CooperationStatus.confirmed
      ? agreements.where((a) => a.status == AgreementStatus.proposed).lastOrNull
      : null;

  bool involves(String accountId) =>
      ownerId == accountId || providerId == accountId;
  String otherSide(String accountId) =>
      accountId == ownerId ? providerId : ownerId;

  Cooperation copyWith(
          {CooperationStatus? status,
          List<Agreement>? agreements,
          EndRequest? endRequest,
          bool clearEndRequest = false,
          EndKind? endKind,
          DateTime? endedAt,
          List<ProgressUpdate>? updates,
          List<Milestone>? milestones,
          List<WorkLog>? workLogs}) =>
      Cooperation(
          id: id,
          demandId: demandId,
          applicationId: applicationId,
          ownerId: ownerId,
          providerId: providerId,
          profileId: profileId,
          status: status ?? this.status,
          agreements: agreements ?? this.agreements,
          createdAt: createdAt,
          endRequest: clearEndRequest ? null : endRequest ?? this.endRequest,
          endKind: endKind ?? this.endKind,
          endedAt: endedAt ?? this.endedAt,
          updates: updates ?? this.updates,
          milestones: milestones ?? this.milestones,
          workLogs: workLogs ?? this.workLogs);
}

// ──────────────────────────────── reviews ────────────────────────────────

/// Review dimensions: on-time payment, clear scope, communication, work.
const reviewDimensions = [
  'payment',
  'scope',
  'communication',
  'work',
  'quality',
  'time',
  'site'
];

/// What an owner rates a pro on, and what a pro rates an owner on.
const proReviewDimensions = ['quality', 'time', 'communication', 'site'];
const ownerReviewDimensions = ['payment', 'scope', 'communication'];

class Review {
  const Review(
      {required this.id,
      required this.cooperationId,
      required this.authorId,
      required this.targetId,
      required this.scores,
      required this.createdAt,
      this.text = ''});
  final String id, cooperationId, authorId, targetId, text;
  final Map<String, int> scores;
  final DateTime createdAt;
}

// ────────────────────────────── chat ──────────────────────────────

enum MessageKind { text, image, demandCard, quoteCard, phoneShared, system }

enum SendState { sending, sent, failed }

class ChatMessage {
  const ChatMessage(
      {required this.id,
      required this.conversationId,
      required this.senderId,
      required this.kind,
      required this.sentAt,
      this.text = '',
      this.refId,
      this.state = SendState.sent});
  final String id, conversationId, senderId, text;
  final MessageKind kind;
  final String? refId;
  final DateTime sentAt;
  final SendState state;

  ChatMessage copyWith({SendState? state, DateTime? sentAt}) => ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      kind: kind,
      sentAt: sentAt ?? this.sentAt,
      text: text,
      refId: refId,
      state: state ?? this.state);
}

class Conversation {
  const Conversation(
      {required this.id,
      required this.participants,
      required this.createdAt,
      this.demandId,
      this.lastMessage,
      this.unread = 0});
  final String id;
  final List<String> participants;
  final DateTime createdAt;
  final String? demandId;
  final ChatMessage? lastMessage;

  /// Unread count for the account that asked.
  final int unread;

  String otherSide(String me) =>
      participants.firstWhere((p) => p != me, orElse: () => me);
}

// ─────────────────────────── notifications ───────────────────────────

enum NoticeKind {
  newApplication,
  confirmRequest,
  cooperationConfirmed,
  cooperationDeclined,
  agreementChange,
  endRequest,
  ended,
  reviewReceived,
  demandExpiring,
  demandExpired,
  outcomeFollowUp,
  reviewApproved,
  reviewRejected,
  demandChanged,
  applicationNotSelected,
  postLiked,
  postCommented,
  postReused,
  milestoneRequested,
  milestoneAnswered,
  workLogged,
}

enum RefType { demand, application, cooperation, conversation, profile, post }

class AppNotification {
  const AppNotification(
      {required this.id,
      required this.accountId,
      required this.kind,
      required this.refType,
      required this.refId,
      required this.createdAt,
      this.title = '',
      this.read = false});
  final String id, accountId, refId;

  /// Short subject, e.g. the demand title.
  final String title;
  final NoticeKind kind;
  final RefType refType;
  final DateTime createdAt;
  final bool read;

  AppNotification markRead() => AppNotification(
      id: id,
      accountId: accountId,
      kind: kind,
      refType: refType,
      refId: refId,
      createdAt: createdAt,
      title: title,
      read: true);
}

// ───────────────────────── design snapshot and backup ─────────────────────────

/// A frozen extract of a design at publish time; later design edits never
/// change it.
class DesignSnapshot {
  const DesignSnapshot(
      {required this.id,
      required this.ownerId,
      required this.projectId,
      required this.projectName,
      required this.designUpdatedAt,
      required this.extractedAt,
      required this.stages,
      required this.lines,
      required this.summary,
      this.preview,
      this.planJson});
  final String id, ownerId, projectId, projectName;
  final String designUpdatedAt;
  final DateTime extractedAt;
  final List<String> stages;
  final List<QtyItem> lines;

  /// Footprint, floors and areas in plain words.
  final String summary;

  /// Plan thumbnail bytes (WebP/PNG) when the design has one.
  final List<int>? preview;

  /// Frozen public geometry only; excludes private notes, specs and budget.
  final String? planJson;
}

class BackupRecord {
  const BackupRecord(
      {required this.projectId,
      required this.name,
      required this.houseText,
      required this.backedUpAt,
      required this.designUpdatedAt});
  final String projectId, name, houseText;
  final DateTime backedUpAt;

  /// The design's own updatedAt when it was backed up.
  final String designUpdatedAt;
}

// ───────────────────────────── moderation ─────────────────────────────

enum ReportTarget { demand, profile, account, message }

enum ReportStatus { open, upheld, dismissed }

class Report {
  const Report(
      {required this.id,
      required this.reporterId,
      required this.target,
      required this.targetId,
      required this.reason,
      required this.createdAt,
      this.status = ReportStatus.open,
      this.handledBy,
      this.handledAt,
      this.resolution = ''});
  final String id, reporterId, targetId, reason;
  final ReportTarget target;
  final DateTime createdAt;
  final ReportStatus status;
  final String? handledBy;
  final DateTime? handledAt;
  final String resolution;

  Report handle(ReportStatus status, String by, DateTime at, String note) =>
      Report(
          id: id,
          reporterId: reporterId,
          target: target,
          targetId: targetId,
          reason: reason,
          createdAt: createdAt,
          status: status,
          handledBy: by,
          handledAt: at,
          resolution: note);
}

/// Every moderation decision keeps who, when and why.
class AuditEntry {
  const AuditEntry(
      {required this.by,
      required this.at,
      required this.action,
      required this.targetId,
      required this.reason});
  final String by, action, targetId, reason;
  final DateTime at;
}

// ─────────────────────────── house posts ───────────────────────────

enum PostStatus { published, hidden }

/// A house design someone shares with everyone: the heart of the feed.
/// Others look, like, rate and comment; the owner can recruit builders
/// for exactly this house, and professionals can offer to build it.
class HousePost {
  const HousePost(
      {required this.id,
      required this.ownerId,
      required this.projectId,
      required this.snapshotId,
      required this.title,
      required this.story,
      required this.region,
      required this.createdAt,
      required this.updatedAt,
      this.area = 0,
      this.floors = 1,
      this.rooms = 0,
      this.estimatedCost,
      this.tags = const [],
      this.openForBuilders = true,
      this.status = PostStatus.published,
      this.likeCount = 0,
      this.commentCount = 0,
      this.ratingSum = 0,
      this.ratingCount = 0,
      this.reuseCount = 0,
      this.showBuild = false,
      this.preview});
  final String id, ownerId, projectId, snapshotId, title, story, region;
  final DateTime createdAt, updatedAt;

  /// m² over all floors, number of floors and rooms, measured from the design.
  final double area;
  final int floors, rooms;

  /// Estimated building cost in tenge, from the design's estimate.
  final int? estimatedCost;
  final List<String> tags;

  /// The owner welcomes builders to apply and quote for this house.
  final bool openForBuilders;
  final PostStatus status;
  final int likeCount, commentCount, ratingSum, ratingCount;

  /// How many people started their own house from this design.
  final int reuseCount;

  /// The owner shows who is building this house and what has been
  /// inspected and paid out so far.
  final bool showBuild;
  final List<int>? preview;

  double? get rating => ratingCount == 0 ? null : ratingSum / ratingCount;

  HousePost copyWith(
          {String? title,
          String? story,
          String? region,
          bool? openForBuilders,
          PostStatus? status,
          int? likeCount,
          int? commentCount,
          int? ratingSum,
          int? ratingCount,
          int? reuseCount,
          bool? showBuild,
          DateTime? updatedAt,
          List<String>? tags}) =>
      HousePost(
          id: id,
          ownerId: ownerId,
          projectId: projectId,
          snapshotId: snapshotId,
          title: title ?? this.title,
          story: story ?? this.story,
          region: region ?? this.region,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt,
          area: area,
          floors: floors,
          rooms: rooms,
          estimatedCost: estimatedCost,
          tags: tags ?? this.tags,
          openForBuilders: openForBuilders ?? this.openForBuilders,
          status: status ?? this.status,
          likeCount: likeCount ?? this.likeCount,
          commentCount: commentCount ?? this.commentCount,
          ratingSum: ratingSum ?? this.ratingSum,
          ratingCount: ratingCount ?? this.ratingCount,
          reuseCount: reuseCount ?? this.reuseCount,
          showBuild: showBuild ?? this.showBuild,
          preview: preview);
}

/// Who builds a house and how far it got, as shown on its public page.
class PostBuild {
  const PostBuild(
      {required this.builders,
      required this.agreedAmount,
      required this.acceptedAmount,
      required this.finished});

  /// One entry per confirmed or ended cooperation: the pro's card and the
  /// stage of the house they took on.
  final List<({ServiceProfile profile, String scope, bool ended})> builders;

  /// Sums over agreements with a known amount, in tenge.
  final int agreedAmount, acceptedAmount;

  /// Every cooperation ended by both sides.
  final bool finished;
}

/// A comment on a house post, optionally with a 1–5 rating. One rating
/// per person per house; the text can be edited by its author.
class PostComment {
  const PostComment(
      {required this.id,
      required this.postId,
      required this.authorId,
      required this.text,
      required this.createdAt,
      this.rating});
  final String id, postId, authorId, text;
  final DateTime createdAt;
  final int? rating;
}

/// Feed ordering.
enum FeedSort { newest, popular, topRated }

class FeedFilter {
  const FeedFilter(
      {this.region,
      this.sort = FeedSort.newest,
      this.query = '',
      this.openForBuilders = false});
  final String? region;
  final FeedSort sort;
  final String query;
  final bool openForBuilders;
}

const postTags = [
  'one_floor',
  'two_floors',
  'brick',
  'wood',
  'sip',
  'garage',
  'budget',
  'large'
];

// ───────────────────────────── dictionaries ─────────────────────────────

/// Trade codes; the interface translates them.
const tradeCodes = [
  'mason',
  'concrete',
  'rebar',
  'carpenter',
  'roofer',
  'electrician',
  'plumber',
  'welder',
  'plasterer',
  'tiler',
  'laborer',
  'general',
];

/// Pilot region: Almaty and its surroundings.
const regionCodes = [
  'almaty',
  'talgar',
  'kaskelen',
  'esik',
  'konaev',
  'otegen',
];

/// Price unit codes.
const priceUnits = ['total', 'day', 'm3', 'm2', 'm', 'pcs', 't', 'hour'];
