import 'models.dart';

/// Business rules shared by the in-memory test backend and the interface. A real
/// backend enforces the same rules on the server. Pure Dart.

const demandLifetime = Duration(days: 30);
const unilateralEndAfter = Duration(days: 7);
const reviewWindow = Duration(days: 14);
const followUpAfter = Duration(days: 3);
const chatLimitPerMinute = 20;

/// Words that send a demand back with a reason: workers must never be asked
/// for a hiring deposit.
const bannedWords = ['押金', 'депозит', 'залог', 'кепілақы', 'кепіл ақы'];

/// One record kind's statuses and the named events that move them. Each
/// event fires from the statuses it lists and leads to one; anything else
/// is refused. yusal-api's `market/lifecycle.go` holds the same machines,
/// and `docs/state_machines.json` is both written out: a test on each side
/// fails when its machines and that file differ.
class StateMachine<S extends Enum, E extends Enum> {
  const StateMachine(this.name,
      {required this.initial, required this.statuses, required this.events});

  final String name;

  /// The status a new record starts in.
  final S initial;
  final List<S> statuses;

  /// In the order of the doc; each event once.
  final List<Transition<S, E>> events;

  Transition<S, E>? _of(E event) {
    for (final t in events) {
      if (t.event == event) return t;
    }
    return null;
  }

  bool can(S from, E event) => _of(event)?.from.contains(from) ?? false;

  /// Where [event] leads from [from], or null when it may not fire.
  S? next(S from, E event) => can(from, event) ? _of(event)!.to : null;

  /// The events that may fire from [from], in table order: what a person
  /// or the voice assistant can do with the record now.
  List<E> allowed(S from) => [
        for (final t in events)
          if (t.from.contains(from)) t.event
      ];

  Map<String, Object?> toJson() => {
        'name': name,
        'initial': initial.name,
        'statuses': [for (final s in statuses) s.name],
        'events': [
          for (final t in events)
            {
              'name': t.event.name,
              'from': [for (final f in t.from) f.name],
              'to': t.to.name
            }
        ],
      };
}

class Transition<S extends Enum, E extends Enum> {
  const Transition(this.event, this.from, this.to);
  final E event;
  final List<S> from;
  final S to;
}

enum DemandEvent {
  /// Sent to review by its owner. A published one goes back to review only
  /// through [recheck].
  publish,

  /// A new version that was rejected or has a banned word is reviewed again.
  recheck,
  approve,

  /// By the review, a moderator, or an upheld report.
  reject,
  pause,
  resume,

  /// Another 30 days.
  renew,
  markFound,

  /// When the expiry passes.
  expire,

  /// By its owner, or when the account is deleted.
  close,
}

const _notClosed = [
  DemandStatus.draft,
  DemandStatus.pendingReview,
  DemandStatus.open,
  DemandStatus.paused,
  DemandStatus.found,
  DemandStatus.expired,
  DemandStatus.rejected,
];

const demandMachine = StateMachine<DemandStatus, DemandEvent>('demand',
    initial: DemandStatus.draft,
    statuses: DemandStatus.values,
    events: [
      Transition(
          DemandEvent.publish,
          [DemandStatus.draft, DemandStatus.rejected],
          DemandStatus.pendingReview),
      Transition(
          DemandEvent.recheck,
          [
            DemandStatus.pendingReview,
            DemandStatus.open,
            DemandStatus.paused,
            DemandStatus.found,
            DemandStatus.expired,
            DemandStatus.rejected
          ],
          DemandStatus.pendingReview),
      Transition(
          DemandEvent.approve, [DemandStatus.pendingReview], DemandStatus.open),
      Transition(
          DemandEvent.reject,
          [DemandStatus.pendingReview, DemandStatus.open, DemandStatus.paused],
          DemandStatus.rejected),
      Transition(DemandEvent.pause, [DemandStatus.open], DemandStatus.paused),
      Transition(
          DemandEvent.resume,
          [DemandStatus.paused, DemandStatus.found, DemandStatus.expired],
          DemandStatus.open),
      Transition(DemandEvent.renew, [DemandStatus.open, DemandStatus.expired],
          DemandStatus.open),
      Transition(
          DemandEvent.markFound,
          [DemandStatus.open, DemandStatus.paused, DemandStatus.expired],
          DemandStatus.found),
      Transition(DemandEvent.expire, [DemandStatus.open, DemandStatus.paused],
          DemandStatus.expired),
      Transition(DemandEvent.close, _notClosed, DemandStatus.closed),
    ]);

enum ApplicationEvent {
  /// Sending again adds a version.
  resubmit,
  withdraw,
  notSelect,

  /// The demand's owner proposes a cooperation.
  invite,

  /// That cooperation was declined or revoked.
  uninvite,

  /// Both sides confirmed it.
  cooperate,
}

const applicationMachine = StateMachine<ApplicationStatus, ApplicationEvent>(
    'application',
    initial: ApplicationStatus.submitted,
    statuses: ApplicationStatus.values,
    events: [
      Transition(
          ApplicationEvent.resubmit,
          [
            ApplicationStatus.submitted,
            ApplicationStatus.withdrawn,
            ApplicationStatus.notSelected
          ],
          ApplicationStatus.submitted),
      Transition(
          ApplicationEvent.withdraw,
          [
            ApplicationStatus.submitted,
            ApplicationStatus.notSelected,
            ApplicationStatus.pendingConfirm
          ],
          ApplicationStatus.withdrawn),
      Transition(ApplicationEvent.notSelect, [ApplicationStatus.submitted],
          ApplicationStatus.notSelected),
      Transition(ApplicationEvent.invite, [ApplicationStatus.submitted],
          ApplicationStatus.pendingConfirm),
      Transition(ApplicationEvent.uninvite, [ApplicationStatus.pendingConfirm],
          ApplicationStatus.submitted),
      Transition(ApplicationEvent.cooperate, [ApplicationStatus.pendingConfirm],
          ApplicationStatus.cooperating),
    ]);

enum CooperationEvent {
  confirm,

  /// Declined, revoked, or its application withdrawn.
  notForm,

  /// Both sides agreed, or the other side did not answer in seven days.
  end,
}

/// Who asked to end a confirmed one and whether that is disputed is in
/// [Cooperation.endRequest].
const cooperationMachine = StateMachine<CooperationStatus, CooperationEvent>(
    'cooperation',
    initial: CooperationStatus.pending,
    statuses: CooperationStatus.values,
    events: [
      Transition(CooperationEvent.confirm, [CooperationStatus.pending],
          CooperationStatus.confirmed),
      Transition(CooperationEvent.notForm, [CooperationStatus.pending],
          CooperationStatus.notFormed),
      Transition(CooperationEvent.end, [CooperationStatus.confirmed],
          CooperationStatus.ended),
    ]);

enum AgreementEvent {
  accept,
  reject,

  /// A newer version was accepted.
  supersede,
}

const agreementMachine = StateMachine<AgreementStatus, AgreementEvent>(
    'agreement',
    initial: AgreementStatus.proposed,
    statuses: AgreementStatus.values,
    events: [
      Transition(AgreementEvent.accept, [AgreementStatus.proposed],
          AgreementStatus.active),
      Transition(AgreementEvent.reject, [AgreementStatus.proposed],
          AgreementStatus.rejected),
      Transition(AgreementEvent.supersede, [AgreementStatus.active],
          AgreementStatus.superseded),
    ]);

enum MilestoneEvent {
  /// Asking again replaces the note and photos.
  request,
  accept,
  dispute,
}

const milestoneMachine = StateMachine<MilestoneStatus, MilestoneEvent>(
    'milestone',
    initial: MilestoneStatus.planned,
    statuses: MilestoneStatus.values,
    events: [
      Transition(
          MilestoneEvent.request,
          [
            MilestoneStatus.planned,
            MilestoneStatus.requested,
            MilestoneStatus.disputed
          ],
          MilestoneStatus.requested),
      Transition(MilestoneEvent.accept, [MilestoneStatus.requested],
          MilestoneStatus.accepted),
      Transition(MilestoneEvent.dispute, [MilestoneStatus.requested],
          MilestoneStatus.disputed),
    ]);

enum ReportEvent { uphold, dismiss }

const reportMachine = StateMachine<ReportStatus, ReportEvent>('report',
    initial: ReportStatus.open,
    statuses: ReportStatus.values,
    events: [
      Transition(ReportEvent.uphold, [ReportStatus.open], ReportStatus.upheld),
      Transition(
          ReportEvent.dismiss, [ReportStatus.open], ReportStatus.dismissed),
    ]);

/// All of the above, in the order of `docs/state_machines.json`.
const List<StateMachine> marketMachines = [
  demandMachine,
  applicationMachine,
  cooperationMachine,
  agreementMachine,
  milestoneMachine,
  reportMachine,
];

/// New sign-ups and quotes are accepted only while recruiting and before
/// the expiry. Existing cooperations are never affected.
bool acceptsApplications(Demand d, DateTime now) =>
    d.status == DemandStatus.open &&
    (d.expiresAt == null || d.expiresAt!.isAfter(now));

/// The expiry for a demand published at [now]: 30 days, or the quote
/// deadline when that comes first.
DateTime expiryFor(DemandVersion v, DateTime now) {
  final standard = now.add(demandLifetime);
  final deadline = v.contract?.quoteDeadline;
  if (deadline != null && deadline.isBefore(standard) && deadline.isAfter(now))
    return deadline;
  return standard;
}

/// Statuses in which the application is still "live" for the publisher.
const liveApplicationStatuses = {
  ApplicationStatus.submitted,
  ApplicationStatus.pendingConfirm,
  ApplicationStatus.cooperating,
};

/// Text containing a banned word, or null when clean.
String? bannedWordIn(String text) {
  final lower = text.toLowerCase();
  for (final w in bannedWords) {
    if (lower.contains(w)) return w;
  }
  return null;
}

const _negationWords = {'не', 'без', 'нет', 'ни', 'жоқ', 'емес'};
const _negationChars = ['不', '无', '免', '没'];

/// Whether every clause holding a banned word also holds a negation
/// ("залог не берём", "不收押金"). Such text goes to a moderator instead of
/// being rejected, because "залог не возвращается" negates too.
bool onlyNegatedBanned(String text) {
  var found = false;
  for (final clause in text.toLowerCase().split(RegExp(r'[.!?;,\n。！？；，、]'))) {
    if (bannedWordIn(clause) == null) continue;
    found = true;
    final negated = _negationChars.any(clause.contains) ||
        clause
            .split(RegExp(r'[^\p{L}]+', unicode: true))
            .any(_negationWords.contains);
    if (!negated) return false;
  }
  return found;
}

/// Inspection point closing each demand stage.
const _stageMilestone = {
  'found': 'foundation',
  'walls': 'walls',
  'roof': 'roof',
  'openings': 'finish',
  'mep': 'finish',
  'finish': 'finish',
  'site': 'finish',
};

/// The four default points, or for a contract over some stages only the
/// points of those stages, their shares rescaled to 100. Either side can
/// replan before confirming.
List<Milestone> milestonesForStages(ContractTerms? c) {
  var plan = defaultMilestones;
  if (c != null && c.scopeKind == ScopeKind.stages) {
    final keep = {for (final s in c.stages) _stageMilestone[s]};
    final some = [
      for (final m in defaultMilestones)
        if (keep.contains(m.key)) m
    ];
    if (some.isNotEmpty) plan = some;
  }
  final total = plan.fold<int>(0, (n, m) => n + m.percent);
  final out = <Milestone>[];
  var left = 100;
  for (final m in plan) {
    final p = m == plan.last ? left : m.percent * 100 ~/ total;
    left -= p;
    out.add(Milestone(key: m.key, percent: p));
  }
  return out;
}

/// Why two or more quotes cannot be compared directly.
enum CompareIssue {
  /// Based on different demand versions.
  versions,

  /// Labour-only next to labour and materials.
  materials,

  /// A "confirm on site" quote next to firm prices.
  siteConfirm,

  /// Line items use different units for the same work.
  units,

  /// The demand changed after the quote was sent.
  outdated,
}

Set<CompareIssue> compareIssues(Iterable<Application> quotes) {
  final list = quotes.toList();
  final issues = <CompareIssue>{};
  if (list.length < 2) {
    if (list.any((a) => a.needsReconfirm)) issues.add(CompareIssue.outdated);
    return issues;
  }
  final versions = list.map((a) => a.current.demandVersionNo).toSet();
  if (versions.length > 1) issues.add(CompareIssue.versions);
  final materials = list.map((a) => a.current.materials).toSet();
  if (materials.length > 1) issues.add(CompareIssue.materials);
  final site =
      list.where((a) => a.current.pricing == PricingMode.siteConfirm).length;
  if (site > 0 && site < list.length) issues.add(CompareIssue.siteConfirm);
  final unitsByName = <String, Set<String>>{};
  for (final a in list) {
    for (final l in a.current.lines) {
      unitsByName.putIfAbsent(_norm(l.name), () => {}).add(l.unit);
    }
  }
  if (unitsByName.values.any((u) => u.length > 1))
    issues.add(CompareIssue.units);
  if (list.any((a) => a.needsReconfirm)) issues.add(CompareIssue.outdated);
  return issues;
}

String _norm(String s) => s.trim().toLowerCase();

/// Reviews of a cooperation become public once both sides submitted, or the
/// review window after the end has passed.
bool reviewsVisible(Cooperation c, List<Review> reviews, DateTime now) {
  final authors = reviews.map((r) => r.authorId).toSet();
  if (authors.contains(c.ownerId) && authors.contains(c.providerId))
    return true;
  final ended = c.endedAt;
  return ended != null && now.isAfter(ended.add(reviewWindow));
}

/// Only a mutually ended cooperation opens reviews; a unilateral report or a
/// dispute is never shown as a verified review.
bool reviewsOpen(Cooperation c, DateTime now) =>
    c.status == CooperationStatus.ended &&
    c.endKind == EndKind.mutual &&
    c.endedAt != null &&
    !now.isAfter(c.endedAt!.add(reviewWindow));

/// Hired headcount of a hire demand: the people agreed in confirmed
/// cooperations.
int hiredCount(Iterable<Cooperation> coops) => coops
    .where((c) =>
        c.status == CooperationStatus.confirmed ||
        (c.status == CooperationStatus.ended && c.endKind != EndKind.cancelled))
    .fold(0, (s, c) => s + (c.agreement.headcount ?? 1));

/// A short default title built from the fields; the publisher may edit it.
String autoTitle(
    {required DemandType type,
    required String tradeName,
    required String regionName,
    int? headcount,
    String? scope}) {
  if (type == DemandType.hire) {
    final n = headcount == null || headcount <= 1 ? '' : ' × $headcount';
    return '$tradeName$n · $regionName';
  }
  final s = (scope == null || scope.isEmpty) ? tradeName : scope;
  return '$s · $regionName';
}

/// What one side can do with a cooperation now, beyond reading it: the
/// cooperation page's buttons and the voice assistant's coop.* actions.
enum CoopMove {
  /// The provider says yes to an invitation.
  confirm,

  /// The provider says no to it.
  decline,

  /// The owner takes it back.
  revoke,

  /// The other side asked to end: say yes…
  confirmEnd,

  /// …or object.
  disputeEnd,

  /// Ask to end, unless an ask is waiting for an answer.
  requestEnd,

  /// Accept or reject the other side's proposed change of terms.
  answerChange,
}

Set<CoopMove> coopMoves(Cooperation c, String me) {
  switch (c.status) {
    case CooperationStatus.pending:
      return me == c.ownerId
          ? {CoopMove.revoke}
          : {CoopMove.confirm, CoopMove.decline};
    case CooperationStatus.confirmed:
      if (c.endAskedOf(me)) return {CoopMove.confirmEnd, CoopMove.disputeEnd};
      if (c.endPhase == EndPhase.asked) return {};
      final change = c.pendingChange;
      return {
        if (change != null && change.proposedBy != me) CoopMove.answerChange,
        CoopMove.requestEnd,
      };
    case CooperationStatus.ended:
    case CooperationStatus.notFormed:
      return {};
  }
}

/// What one side can do with milestone [i] of a cooperation now: the
/// provider asks for inspection of the first open point while the
/// cooperation runs; the owner accepts or questions a requested one. The
/// site section's buttons and the voice assistant's milestone actions both
/// come from it.
Set<MilestoneEvent> milestoneMoves(Cooperation c, String? me, int i) {
  final m = c.milestones[i];
  final current =
      c.milestones.indexWhere((m) => m.status != MilestoneStatus.accepted);
  return {
    if (me == c.providerId &&
        c.status == CooperationStatus.confirmed &&
        i == current &&
        m.status != MilestoneStatus.requested)
      MilestoneEvent.request,
    if (me == c.ownerId && m.status == MilestoneStatus.requested) ...[
      MilestoneEvent.accept,
      MilestoneEvent.dispute,
    ],
  };
}

/// The milestone voice acts on: the first one not yet accepted, since
/// inspections go in order. Null when all are accepted or there are none.
int? currentMilestone(Cooperation c) {
  final i =
      c.milestones.indexWhere((m) => m.status != MilestoneStatus.accepted);
  return i < 0 ? null : i;
}
