import 'models.dart';

/// Business rules shared by the mock backend and the interface. A real
/// backend enforces the same rules on the server. Pure Dart.

const demandLifetime = Duration(days: 30);
const unilateralEndAfter = Duration(days: 7);
const reviewWindow = Duration(days: 14);
const followUpAfter = Duration(days: 3);
const chatLimitPerMinute = 20;

/// Words that send a demand back with a reason: workers must never be asked
/// for a hiring deposit.
const bannedWords = ['押金', 'депозит', 'залог', 'кепілақы', 'кепіл ақы'];

/// Allowed demand status changes. Everything else is refused.
const demandTransitions = <DemandStatus, Set<DemandStatus>>{
  DemandStatus.draft: {DemandStatus.pendingReview, DemandStatus.closed},
  DemandStatus.pendingReview: {
    DemandStatus.open,
    DemandStatus.rejected,
    DemandStatus.closed
  },
  DemandStatus.open: {
    DemandStatus.paused,
    DemandStatus.found,
    DemandStatus.expired,
    DemandStatus.closed,
    DemandStatus.rejected,
    DemandStatus.pendingReview,
  },
  DemandStatus.paused: {
    DemandStatus.open,
    DemandStatus.found,
    DemandStatus.closed,
    DemandStatus.expired,
    DemandStatus.pendingReview,
  },
  DemandStatus.found: {DemandStatus.open, DemandStatus.closed},
  DemandStatus.expired: {
    DemandStatus.open,
    DemandStatus.found,
    DemandStatus.closed
  },
  DemandStatus.rejected: {DemandStatus.pendingReview, DemandStatus.closed},
  DemandStatus.closed: {},
};

bool canMoveDemand(DemandStatus from, DemandStatus to) =>
    demandTransitions[from]?.contains(to) ?? false;

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
