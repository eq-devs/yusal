// Back-office and trust records: paged lists, the to-do list, the dashboard,
// appeals, worker verification, new-demand alerts and push settings.
import 'models.dart';

/// One page of a back-office list.
class Paged<T> {
  const Paged(this.items, {required this.total, this.page = 1, this.pageSize = 20});
  final List<T> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
  static Paged<T> of<T>(List<T> all, int page, int size) {
    final from = ((page - 1) * size).clamp(0, all.length);
    final to = (from + size).clamp(0, all.length);
    return Paged(all.sublist(from, to), total: all.length, page: page, pageSize: size);
  }
}

/// A report with what a moderator needs to judge it.
class ReportView {
  const ReportView(
      {required this.report,
      this.reporterName = '',
      this.targetTitle = '',
      this.targetOwnerId = '',
      this.targetOwnerName = '',
      this.postId});
  final Report report;
  final String reporterName, targetTitle, targetOwnerId, targetOwnerName;

  /// The house a reported comment belongs to.
  final String? postId;
}

enum AppealStatus { open, accepted, rejected }

/// A request to look again at a decision about one's own record.
class Appeal {
  const Appeal(
      {required this.id,
      required this.accountId,
      required this.target,
      required this.targetId,
      required this.text,
      required this.createdAt,
      this.targetTitle = '',
      this.accountName = '',
      this.status = AppealStatus.open,
      this.resolution = '',
      this.handledAt});
  final String id, accountId, targetId, text, targetTitle, accountName, resolution;

  /// demand | profile | post | account
  final String target;
  final AppealStatus status;
  final DateTime createdAt;
  final DateTime? handledAt;
}

enum VerificationStatus { pending, approved, rejected }

/// A worker's request to have a profile verified (phone + site photos).
class Verification {
  const Verification(
      {required this.id,
      required this.profileId,
      required this.ownerId,
      required this.name,
      required this.phone,
      required this.createdAt,
      this.photos = const [],
      this.note = '',
      this.ownerName = '',
      this.status = VerificationStatus.pending,
      this.resolution = ''});
  final String id, profileId, ownerId, name, phone, note, ownerName, resolution;
  final List<String> photos;
  final DateTime createdAt;
  final VerificationStatus status;
}

/// Which new demands a worker wants to hear about; empty lists match all.
class DemandAlert {
  const DemandAlert(
      {this.on = false,
      this.regions = const [],
      this.trades = const [],
      this.types = const []});
  final bool on;
  final List<String> regions, trades;
  final List<DemandType> types;

  bool matches(Demand d) {
    final v = d.current;
    return on &&
        (regions.isEmpty || regions.contains(v.region)) &&
        (trades.isEmpty || trades.any(v.trades.contains)) &&
        (types.isEmpty || types.contains(d.type));
  }
}

/// Push categories the user can mute (deal notices always push).
abstract final class PushCategory {
  static const community = 'community', alerts = 'alerts';
}

/// One account's push preferences.
class NotificationSettings {
  const NotificationSettings(
      {this.muted = const [], this.quietStart = '', this.quietEnd = ''});
  final List<String> muted;
  final String quietStart, quietEnd;
}

/// The platform's push restraint.
class PushPolicy {
  const PushPolicy(
      {this.quietStart = '22:00', this.quietEnd = '08:00', this.dailyCap = 10});
  final String quietStart, quietEnd;
  final int dailyCap;
}

/// One kind of waiting work: how many and the oldest few.
class TodoList<T> {
  const TodoList(this.count, this.items);
  final int count;
  final List<T> items;
}

/// The back office's first screen.
class AdminTodo {
  const AdminTodo(
      {required this.review,
      required this.reports,
      required this.appeals,
      required this.verifications,
      required this.disputes,
      this.health = const []});
  final TodoList<Demand> review;
  final TodoList<Report> reports;
  final TodoList<Appeal> appeals;
  final TodoList<Verification> verifications;
  final TodoList<Cooperation> disputes;

  /// Warnings: sweep_stalled, manual_review_on.
  final List<String> health;
  int get total =>
      review.count + reports.count + appeals.count + verifications.count + disputes.count;
}

class DashboardDay {
  const DashboardDay(this.day, {this.active = 0, this.demands = 0, this.quotes = 0});
  final String day;
  final int active, demands, quotes;
}

class RegionSupply {
  const RegionSupply(this.region, {this.demands = 0, this.workers = 0});
  final String region;
  final int demands, workers;
}

/// The back office's numbers.
class AdminDashboard {
  const AdminDashboard(
      {this.today = const {},
      this.daily = const [],
      this.funnel = const [],
      this.regions = const [],
      this.firstQuoteHours,
      this.totals = const {}});

  /// active, new_users, new_posts, new_demands, new_quotes, new_cooperations, inspections
  final Map<String, int> today;
  final List<DashboardDay> daily;

  /// posts, reuses, demands, quoted, cooperations, inspected, reviews
  final List<(String, int)> funnel;
  final List<RegionSupply> regions;
  final double? firstQuoteHours;

  /// users, posts, profiles, demands
  final Map<String, int> totals;
}

/// One account in the back office's user list.
class AdminUserRow {
  const AdminUserRow(
      {required this.id,
      required this.name,
      required this.createdAt,
      this.email = '',
      this.restricted = false,
      this.deleted = false,
      this.role});
  final String id, name, email;
  final bool restricted, deleted;
  final String? role;
  final DateTime createdAt;
}

/// Everything about one account on one page.
class AccountDetail {
  const AccountDetail(
      {required this.account,
      this.email = '',
      this.lastLogin,
      this.profiles = const [],
      this.demands = const [],
      this.applications = 0,
      this.cooperations = const [],
      this.posts = const [],
      this.reportsAbout = const [],
      this.reportsFiled = 0,
      this.appeals = const [],
      this.audit = const []});
  final Account account;
  final String email;
  final DateTime? lastLogin;
  final List<ServiceProfile> profiles;
  final List<Demand> demands;
  final int applications, reportsFiled;
  final List<Cooperation> cooperations;
  final List<({String id, String title, bool hidden})> posts;
  final List<Report> reportsAbout;
  final List<Appeal> appeals;
  final List<AuditEntry> audit;
}

/// Result of a batch decision.
class BatchResult {
  const BatchResult(this.done, this.failed);
  final int done;
  final List<String> failed;
}
