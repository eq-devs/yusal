import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';

/// The server's rules that only the in-memory fake needs; yusal-api keeps
/// the real ones.

const unilateralEndAfter = Duration(days: 7);

const followUpAfter = Duration(days: 3);

const chatLimitPerMinute = 20;

/// The expiry for a demand published at [now]: 30 days, or the quote
/// deadline when that comes first.
DateTime expiryFor(DemandVersion v, DateTime now) {
  final standard = now.add(demandLifetime);
  final deadline = v.contract?.quoteDeadline;
  if (deadline != null &&
      deadline.isBefore(standard) &&
      deadline.isAfter(now)) {
    return deadline;
  }
  return standard;
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

/// Reviews of a cooperation become public once both sides submitted, or the
/// review window after the end has passed.
bool reviewsVisible(Cooperation c, List<Review> reviews, DateTime now) {
  final authors = reviews.map((r) => r.authorId).toSet();
  if (authors.contains(c.ownerId) && authors.contains(c.providerId)) {
    return true;
  }
  final ended = c.endedAt;
  return ended != null && now.isAfter(ended.add(reviewWindow));
}

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

extension AccountRules on Account {
  Account withRole(String? role) => Account(
      id: id,
      phone: phone,
      displayName: displayName,
      createdAt: createdAt,
      email: email,
      deleted: deleted,
      restricted: restricted,
      role: role);
}

extension CooperationRules on Cooperation {
  bool involves(String accountId) =>
      ownerId == accountId || providerId == accountId;
}

extension ReportRules on Report {
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
