import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../repositories.dart';
import 'mock_clock.dart';
import 'mock_seed.dart';

/// In-memory stand-in for the platform backend. It enforces the same
/// permissions and state rules a real server must: the client can never
/// mark itself hired, confirm for the other side, or skip review.
///
/// Data lives only in memory and is re-seeded on every launch.
class MockBackend implements PlatformRepositories {
  MockBackend(
      {MockClock? clock,
      this.latency = const Duration(milliseconds: 120),
      this.autoReviewDelay = const Duration(milliseconds: 900),
      bool seed = true})
      : clock = clock ?? MockClock() {
    if (seed) seedMockData(this);
  }

  final MockClock clock;

  /// Simulated network delay of every call; zero in tests.
  Duration latency;

  /// Null: demands wait for a moderator. Zero: reviewed synchronously.
  /// Otherwise reviewed automatically after the delay.
  Duration? autoReviewDelay;

  /// Developer switch: chat sends and backups fail as if offline.
  bool simulateOffline = false;

  /// The phone code the mock SMS "sends".
  static const verificationCode = '1234';

  final _changes = ChangeNotifier();
  @override
  Listenable get changes => _changes;

  // ── storage ──
  final accounts = <String, Account>{};
  final profiles = <String, ServiceProfile>{};
  final demands = <String, Demand>{};
  final applications = <String, Application>{};
  final cooperations = <String, Cooperation>{};
  final reviews = <String, Review>{};
  final convs = <String, Conversation>{};
  final messagesById = <String, ChatMessage>{};
  final notices = <String, AppNotification>{};
  final snapshots = <String, DesignSnapshot>{};
  final backupsByAccount = <String, Map<String, BackupRecord>>{};
  final reportsById = <String, Report>{};
  final posts = <String, HousePost>{};
  final commentsById = <String, PostComment>{};
  final likes = <String, Set<String>>{}; // postId -> account ids
  final _commentTimes = <String, List<DateTime>>{};
  final auditLog = <AuditEntry>[];
  final _favourites = <String, Set<String>>{};
  final _blocks = <String, Set<String>>{};
  final _lastRead = <String, DateTime>{};
  final _codesSent = <String>{};
  String? currentId;
  int _seq = 0;

  String newId(String prefix) => '${prefix}_${++_seq}';
  DateTime get now => clock.now();

  void notify() {
    _sweep();
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _changes.notifyListeners();
  }

  /// Developer tool: move time forward and apply what it triggers.
  void advanceTime(Duration d) {
    clock.advance(d);
    notify();
  }

  /// Developer tool: switch to a seeded account without a code.
  void signInAs(String? accountId) {
    currentId = accountId;
    notify();
  }

  Future<T> _io<T>(T Function() body) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    _sweep();
    final result = body();
    notify();
    return result;
  }

  Future<T> _read<T>(T Function() body) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    _sweep();
    return body();
  }

  String get _me {
    final id = currentId;
    if (id == null || accounts[id] == null || accounts[id]!.deleted)
      throw const ApiFailure(ApiCodes.notSignedIn);
    return id;
  }

  Account get _meAccount => accounts[_me]!;

  void _requireActive() {
    if (_meAccount.restricted) throw const ApiFailure(ApiCodes.restricted);
  }

  void _requireAdmin() {
    if (!_meAccount.isAdmin) throw const ApiFailure(ApiCodes.forbidden);
  }

  bool _isBlocked(String a, String b) =>
      (_blocks[a]?.contains(b) ?? false) || (_blocks[b]?.contains(a) ?? false);

  void notice(String accountId, NoticeKind kind, RefType refType, String refId,
      {String title = ''}) {
    final id = newId('n');
    notices[id] = AppNotification(
        id: id,
        accountId: accountId,
        kind: kind,
        refType: refType,
        refId: refId,
        title: title,
        createdAt: now);
  }

  /// Time-driven changes: expiry, follow-ups and unanswered end requests.
  void _sweep() {
    final t = now;
    for (final d in demands.values.toList()) {
      if ((d.status == DemandStatus.open || d.status == DemandStatus.paused) &&
          d.expiresAt != null &&
          !d.expiresAt!.isAfter(t)) {
        demands[d.id] = d.copyWith(status: DemandStatus.expired);
        notice(d.ownerId, NoticeKind.demandExpired, RefType.demand, d.id,
            title: d.current.title);
        if (d.outcome == null && d.followUpsSent < 2) {
          notice(d.ownerId, NoticeKind.outcomeFollowUp, RefType.demand, d.id,
              title: d.current.title);
          demands[d.id] = demands[d.id]!.copyWith(followUpsSent: 2);
        }
      } else if (d.status == DemandStatus.open &&
          d.outcome == null &&
          d.followUpsSent == 0 &&
          d.publishedAt != null &&
          !d.publishedAt!.add(followUpAfter).isAfter(t)) {
        notice(d.ownerId, NoticeKind.outcomeFollowUp, RefType.demand, d.id,
            title: d.current.title);
        demands[d.id] = d.copyWith(followUpsSent: 1);
      }
    }
    for (final c in cooperations.values.toList()) {
      final r = c.endRequest;
      if (c.status == CooperationStatus.confirmed &&
          r != null &&
          r.dispute == null &&
          !r.at.add(unilateralEndAfter).isAfter(t)) {
        cooperations[c.id] = c.copyWith(
            status: CooperationStatus.ended,
            endKind: EndKind.unilateral,
            endedAt: t);
        for (final p in [c.ownerId, c.providerId]) {
          notice(p, NoticeKind.ended, RefType.cooperation, c.id,
              title: demands[c.demandId]?.current.title ?? '');
        }
      }
    }
  }

  // ───────────────────────────── auth ─────────────────────────────

  @override
  Account? get currentAccount {
    final a = currentId == null ? null : accounts[currentId];
    return a == null || a.deleted ? null : a;
  }

  static String normalisePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Future<void> requestCode(String phone) => _io(() {
        final p = normalisePhone(phone);
        if (p.replaceAll('+', '').length < 10)
          throw const ApiFailure(ApiCodes.badPhone);
        _codesSent.add(p);
      });

  @override
  Future<Account> verify(String phone, String code, {String? displayName}) =>
      _io(() {
        final p = normalisePhone(phone);
        if (!_codesSent.contains(p) || code.trim() != verificationCode)
          throw const ApiFailure(ApiCodes.badCode);
        var account = accounts.values
            .where((a) => a.phone == p && !a.deleted)
            .firstOrNull;
        if (account == null) {
          final id = newId('acc');
          account = Account(
              id: id,
              phone: p,
              displayName: (displayName ?? '').trim().isEmpty
                  ? '${p.substring(p.length - 4)}'
                  : displayName!.trim(),
              createdAt: now);
          accounts[id] = account;
        }
        currentId = account.id;
        return account;
      });

  @override
  Future<void> signOut() => _io(() => currentId = null);

  @override
  Future<Account> updateName(String name) => _io(() {
        if (name.trim().isEmpty) throw const ApiFailure(ApiCodes.invalidInput);
        final a = _meAccount.copyWith(displayName: name.trim());
        accounts[a.id] = a;
        return a;
      });

  @override
  Future<void> deleteAccount() => _io(() {
        final me = _me;
        accounts[me] = accounts[me]!.copyWith(deleted: true);
        for (final p
            in profiles.values.where((p) => p.ownerId == me).toList()) {
          profiles[p.id] = p.copyWith(status: ProfileStatus.hidden);
        }
        for (final d in demands.values.where((d) => d.ownerId == me).toList()) {
          if (d.status != DemandStatus.closed)
            demands[d.id] = d.copyWith(
                status: DemandStatus.closed, closeReason: 'accountDeleted');
        }
        backupsByAccount.remove(me);
        currentId = null;
      });

  @override
  Future<Account?> account(String id) => _read(() => accounts[id]);

  // ─────────────────────────── profiles ───────────────────────────

  @override
  Future<List<ServiceProfile>> myProfiles() =>
      _read(() => profiles.values.where((p) => p.ownerId == _me).toList());

  bool _profileVisible(ServiceProfile p) =>
      p.status == ProfileStatus.active &&
          !(accounts[p.ownerId]?.deleted ?? true) ||
      p.ownerId == currentId;

  @override
  Future<ServiceProfile?> profile(String id) => _read(() {
        final p = profiles[id];
        return p != null && _profileVisible(p) ? p : null;
      });

  @override
  Future<List<ServiceProfile>> profilesOf(String accountId) =>
      _read(() => profiles.values
          .where((p) => p.ownerId == accountId && _profileVisible(p))
          .toList());

  @override
  Future<List<ServiceProfile>> searchProfiles(ProfileFilter f) => _read(() {
        final q = f.query.trim().toLowerCase();
        final mine = currentId;
        final list = profiles.values.where((p) {
          if (p.status != ProfileStatus.active) return false;
          if (accounts[p.ownerId]?.deleted ?? true) return false;
          if (mine != null && _isBlocked(mine, p.ownerId)) return false;
          if (f.kind != null && p.kind != f.kind) return false;
          if (f.trade != null && !p.trades.contains(f.trade)) return false;
          if (f.region != null && !p.regions.contains(f.region)) return false;
          if (f.availableNow && !p.availableOn(now)) return false;
          if (q.isNotEmpty &&
              !p.name.toLowerCase().contains(q) &&
              !p.bio.toLowerCase().contains(q)) return false;
          return true;
        }).toList()
          ..sort((a, b) {
            final av = a.availableOn(now) ? 0 : 1,
                bv = b.availableOn(now) ? 0 : 1;
            if (av != bv) return av - bv;
            return b.availabilityConfirmedAt
                .compareTo(a.availabilityConfirmedAt);
          });
        return list;
      });

  @override
  Future<ServiceProfile> saveProfile(ServiceProfile p) => _io(() {
        final me = _me;
        _requireActive();
        if (p.name.trim().isEmpty || p.trades.isEmpty || p.regions.isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput);
        for (final r in p.refPrices) {
          if (r.amount <= 0 || !priceUnits.contains(r.unit))
            throw const ApiFailure(ApiCodes.invalidInput, 'refPrice');
        }
        if (p.id.isEmpty) {
          final id = newId('prof');
          final created = ServiceProfile(
              id: id,
              ownerId: me,
              kind: p.kind,
              name: p.name.trim(),
              trades: p.trades,
              regions: p.regions,
              availability: p.availability,
              availableFrom: p.availableFrom,
              availabilityConfirmedAt: now,
              experienceYears: p.experienceYears,
              teamSize: p.teamSize,
              refPrices: p.refPrices,
              bio: p.bio,
              works: p.works,
              showPhone: p.showPhone);
          profiles[id] = created;
          return created;
        }
        final old = profiles[p.id];
        if (old == null) throw const ApiFailure(ApiCodes.notFound);
        if (old.ownerId != me) throw const ApiFailure(ApiCodes.forbidden);
        // Works from cooperations come from the platform and cannot be
        // added or forged by the client.
        final platformWorks =
            old.works.where((w) => w.source == WorkSource.platform);
        final uploaded = p.works.where((w) => w.source == WorkSource.uploaded);
        final saved = p.copyWith(
            name: p.name.trim(),
            availabilityConfirmedAt: now,
            works: [...platformWorks, ...uploaded],
            status: old.status == ProfileStatus.hidden &&
                    p.status == ProfileStatus.active
                ? ProfileStatus.active
                : p.status);
        profiles[p.id] = ServiceProfile(
            id: old.id,
            ownerId: old.ownerId,
            kind: saved.kind,
            name: saved.name,
            trades: saved.trades,
            regions: saved.regions,
            availability: saved.availability,
            availableFrom: saved.availableFrom,
            availabilityConfirmedAt: saved.availabilityConfirmedAt,
            experienceYears: saved.experienceYears,
            teamSize: saved.teamSize,
            refPrices: saved.refPrices,
            bio: saved.bio,
            works: saved.works,
            status: saved.status,
            showPhone: saved.showPhone);
        return profiles[p.id]!;
      });

  @override
  Future<ServiceProfile> confirmAvailability(String profileId) => _io(() {
        final p = profiles[profileId];
        if (p == null) throw const ApiFailure(ApiCodes.notFound);
        if (p.ownerId != _me) throw const ApiFailure(ApiCodes.forbidden);
        return profiles[p.id] = p.copyWith(availabilityConfirmedAt: now);
      });

  @override
  Future<ProfileStats> stats(String profileId) => _read(() {
        final p = profiles[profileId];
        if (p == null) throw const ApiFailure(ApiCodes.notFound);
        final coops = cooperations.values.where((c) =>
            c.profileId == profileId &&
            (c.status == CooperationStatus.confirmed ||
                c.status == CooperationStatus.ended));
        final coopIds = coops.map((c) => c.id).toSet();
        final visible = reviews.values.where((r) {
          if (!coopIds.contains(r.cooperationId) || r.targetId != p.ownerId)
            return false;
          final c = cooperations[r.cooperationId]!;
          return reviewsVisible(c, _reviewsOf(c.id), now);
        }).toList();
        final avg = <String, double>{};
        for (final d in reviewDimensions) {
          final scores =
              visible.map((r) => r.scores[d]).whereType<int>().toList();
          if (scores.isNotEmpty)
            avg[d] = scores.reduce((a, b) => a + b) / scores.length;
        }
        return ProfileStats(
            phoneVerified: accounts[p.ownerId]?.phoneVerified ?? false,
            confirmedCooperations: coops.length,
            reviewCount: visible.length,
            dimensionAverages: avg);
      });

  @override
  Future<Set<String>> favourites() => _read(() => {...?_favourites[currentId]});

  @override
  Future<void> toggleFavourite(String id) => _io(() {
        final set = _favourites.putIfAbsent(_me, () => {});
        if (!set.remove(id)) set.add(id);
      });

  // ─────────────────────────── demands ───────────────────────────

  bool _demandVisible(Demand d) {
    if (d.ownerId == currentId) return true;
    if (currentId != null && accounts[currentId]!.isAdmin) return true;
    if (currentId != null &&
        applications.values
            .any((a) => a.demandId == d.id && a.applicantId == currentId))
      return true;
    return const {
      DemandStatus.open,
      DemandStatus.paused,
      DemandStatus.found,
      DemandStatus.expired,
      DemandStatus.closed,
    }.contains(d.status);
  }

  @override
  Future<List<Demand>> searchDemands(DemandFilter f) => _read(() {
        final q = f.query.trim().toLowerCase();
        final mine = currentId;
        final list = demands.values.where((d) {
          final active = d.status == DemandStatus.open;
          final inactiveOk = f.includeInactive &&
              const {
                DemandStatus.paused,
                DemandStatus.found,
                DemandStatus.expired
              }.contains(d.status);
          if (!active && !inactiveOk) return false;
          if (accounts[d.ownerId]?.deleted ?? true) return false;
          if (mine != null && _isBlocked(mine, d.ownerId)) return false;
          final v = d.current;
          if (f.type != null && d.type != f.type) return false;
          if (f.trade != null && !v.trades.contains(f.trade)) return false;
          if (f.region != null && v.region != f.region) return false;
          if (q.isNotEmpty &&
              !v.title.toLowerCase().contains(q) &&
              !v.description.toLowerCase().contains(q) &&
              !v.locality.toLowerCase().contains(q)) return false;
          return true;
        }).toList()
          ..sort((a, b) => (b.publishedAt ?? b.createdAt)
              .compareTo(a.publishedAt ?? a.createdAt));
        return list.map(_redact).toList();
      });

  @override
  Future<Demand?> demand(String id) => _read(() {
        final d = demands[id];
        return d != null && _demandVisible(d) ? _redact(d) : null;
      });

  /// The exact address only reaches the owner, or a partner the owner
  /// granted it to in a confirmed agreement.
  Demand _redact(Demand d) {
    final me = currentId;
    if (me == d.ownerId) return d;
    final granted = me != null &&
        cooperations.values.any((c) =>
            c.demandId == d.id &&
            c.providerId == me &&
            c.status != CooperationStatus.notFormed &&
            c.status != CooperationStatus.pending &&
            c.agreement.shareExactAddress);
    if (granted) return d;
    return d.copyWith(versions: [
      for (final v in d.versions)
        DemandVersion(
            no: v.no,
            title: v.title,
            trades: v.trades,
            region: v.region,
            locality: v.locality,
            budget: v.budget,
            createdAt: v.createdAt,
            startDate: v.startDate,
            durationDays: v.durationDays,
            description: v.description,
            photoCount: v.photoCount,
            siteNotes: v.siteNotes,
            hire: v.hire,
            contract: v.contract,
            snapshotId: v.snapshotId,
            visibility: v.visibility)
    ]);
  }

  @override
  Future<List<Demand>> myDemands() =>
      _read(() => demands.values.where((d) => d.ownerId == _me).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  DemandVersion _numbered(DemandVersion v, int no) => DemandVersion(
      no: no,
      title: v.title.trim(),
      trades: v.trades,
      region: v.region,
      locality: v.locality.trim(),
      exactAddress: v.exactAddress.trim(),
      budget: v.budget,
      createdAt: now,
      startDate: v.startDate,
      durationDays: v.durationDays,
      description: v.description.trim(),
      photoCount: v.photoCount,
      siteNotes: v.siteNotes.trim(),
      hire: v.hire,
      contract: v.contract,
      snapshotId: v.snapshotId,
      visibility: v.visibility);

  void _validateDemand(DemandType type, DemandVersion v) {
    String? bad;
    if (v.title.trim().isEmpty) bad = 'title';
    if (v.trades.isEmpty) bad = 'trades';
    if (!regionCodes.contains(v.region)) bad = 'region';
    final b = v.budget;
    switch (b.mode) {
      case BudgetMode.fixed:
        if ((b.amount ?? 0) <= 0) bad = 'budget';
      case BudgetMode.range:
        if ((b.min ?? 0) <= 0 || (b.max ?? 0) < (b.min ?? 0)) bad = 'budget';
      case BudgetMode.askQuote:
        break;
    }
    if (type == DemandType.hire) {
      final h = v.hire;
      if (h == null || h.headcount < 1) bad = 'hire';
      if (h != null && h.wage != null && h.wage! <= 0) bad = 'wage';
    } else {
      final c = v.contract;
      if (c == null) bad = 'contract';
      if (c != null && c.scopeKind == ScopeKind.stages && c.stages.isEmpty)
        bad = 'stages';
      if (c != null &&
          c.quantities.any((q) => q.quantity != null && q.quantity! <= 0))
        bad = 'quantity';
    }
    if (v.snapshotId != null) {
      final s = snapshots[v.snapshotId];
      if (s == null || s.ownerId != _me) bad = 'snapshot';
    }
    if (bad != null) throw ApiFailure(ApiCodes.invalidInput, bad);
  }

  Demand _owned(String id) {
    final d = demands[id];
    if (d == null) throw const ApiFailure(ApiCodes.notFound);
    if (d.ownerId != _me) throw const ApiFailure(ApiCodes.forbidden);
    return d;
  }

  Demand _move(Demand d, DemandStatus to) {
    if (!canMoveDemand(d.status, to))
      throw ApiFailure(ApiCodes.invalidState, '${d.status.name}→${to.name}');
    return d.copyWith(status: to);
  }

  @override
  Future<Demand> saveDraft(DemandType type, DemandVersion draft,
          {PublisherRole role = PublisherRole.owner,
          String? existingId,
          String? designProjectId}) =>
      _io(() {
        final me = _me;
        _requireActive();
        _validateDemand(type, draft);
        if (existingId != null) {
          final d = _owned(existingId);
          if (d.status != DemandStatus.draft &&
              d.status != DemandStatus.rejected)
            throw const ApiFailure(ApiCodes.invalidState);
          final versions = [...d.versions];
          versions[versions.length - 1] = _numbered(draft, versions.last.no);
          return demands[d.id] = d.copyWith(versions: versions);
        }
        final id = newId('dem');
        return demands[id] = Demand(
            id: id,
            ownerId: me,
            type: type,
            status: DemandStatus.draft,
            versions: [_numbered(draft, 1)],
            createdAt: now,
            shareToken: 'share_${id}_${now.microsecondsSinceEpoch % 100000}',
            publisherRole: role,
            designProjectId: designProjectId);
      });

  /// Content review: banned words reject with a reason, the rest opens.
  void _autoReview(String id) {
    final d = demands[id];
    if (d == null || d.status != DemandStatus.pendingReview) return;
    final v = d.current;
    final word = bannedWordIn('${v.title} ${v.description} ${v.siteNotes}');
    if (word != null) {
      _decide(d, false, 'system', 'banned:$word');
    } else {
      _decide(d, true, 'system', 'auto');
    }
  }

  void _decide(Demand d, bool approve, String by, String reason) {
    if (approve) {
      final first = d.publishedAt == null;
      demands[d.id] = d.copyWith(
          status: DemandStatus.open,
          publishedAt: first ? now : d.publishedAt,
          expiresAt: d.expiresAt != null && d.expiresAt!.isAfter(now)
              ? d.expiresAt
              : expiryFor(d.current, now));
      notice(d.ownerId, NoticeKind.reviewApproved, RefType.demand, d.id,
          title: d.current.title);
    } else {
      demands[d.id] =
          d.copyWith(status: DemandStatus.rejected, rejectReason: reason);
      notice(d.ownerId, NoticeKind.reviewRejected, RefType.demand, d.id,
          title: d.current.title);
    }
    auditLog.add(AuditEntry(
        by: by,
        at: now,
        action: approve ? 'approve' : 'reject',
        targetId: d.id,
        reason: reason));
  }

  void _queueReview(String id) {
    final delay = autoReviewDelay;
    if (delay == null) return;
    if (delay == Duration.zero) {
      _autoReview(id);
    } else {
      Timer(delay, () {
        _autoReview(id);
        notify();
      });
    }
  }

  @override
  Future<Demand> publish(String demandId) => _io(() {
        _requireActive();
        final d = _owned(demandId);
        demands[d.id] = _move(d, DemandStatus.pendingReview);
        _queueReview(d.id);
        return demands[d.id]!;
      });

  @override
  Future<Demand> revise(String demandId, DemandVersion next) => _io(() {
        _requireActive();
        final d = _owned(demandId);
        if (!const {
          DemandStatus.open,
          DemandStatus.paused,
          DemandStatus.expired,
          DemandStatus.rejected,
          DemandStatus.pendingReview,
          DemandStatus.found,
        }.contains(d.status)) throw const ApiFailure(ApiCodes.invalidState);
        _validateDemand(d.type, next);
        final version = _numbered(next, d.current.no + 1);
        var updated = d.copyWith(versions: [...d.versions, version]);
        // Rejected content goes back to review; a published one is checked
        // again for banned words.
        if (d.status == DemandStatus.rejected) {
          updated = updated.copyWith(status: DemandStatus.pendingReview);
          demands[d.id] = updated;
          _queueReview(d.id);
        } else if (bannedWordIn(
                '${version.title} ${version.description} ${version.siteNotes}') !=
            null) {
          demands[d.id] = updated.copyWith(status: DemandStatus.pendingReview);
          _queueReview(d.id);
        } else {
          demands[d.id] = updated;
        }
        for (final a in applications.values
            .where((a) =>
                a.demandId == d.id &&
                (a.status == ApplicationStatus.submitted ||
                    a.status == ApplicationStatus.pendingConfirm))
            .toList()) {
          applications[a.id] = a.copyWith(needsReconfirm: true);
          notice(a.applicantId, NoticeKind.demandChanged, RefType.demand, d.id,
              title: version.title);
        }
        return demands[d.id]!;
      });

  @override
  Future<Demand> pause(String demandId) => _io(
      () => demands[demandId] = _move(_owned(demandId), DemandStatus.paused));

  @override
  Future<Demand> resume(String demandId) => _io(() {
        final d = _owned(demandId);
        if (d.status == DemandStatus.found) {
          return demands[d.id] = _move(d, DemandStatus.open).copyWith(
              expiresAt: d.expiresAt != null && d.expiresAt!.isAfter(now)
                  ? d.expiresAt
                  : now.add(demandLifetime));
        }
        return demands[d.id] = _move(d, DemandStatus.open);
      });

  @override
  Future<Demand> renew(String demandId) => _io(() {
        final d = _owned(demandId);
        if (d.status != DemandStatus.expired && d.status != DemandStatus.open)
          throw const ApiFailure(ApiCodes.invalidState);
        return demands[d.id] = d.copyWith(
            status: DemandStatus.open, expiresAt: now.add(demandLifetime));
      });

  @override
  Future<Demand> markFound(String demandId, OutcomeKind outcome) => _io(() {
        final d = _owned(demandId);
        return demands[d.id] = _move(d, DemandStatus.found)
            .copyWith(outcome: outcome, outcomeAt: now);
      });

  @override
  Future<Demand> close(String demandId, String reason) => _io(() {
        final d = _owned(demandId);
        if (reason.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput);
        return demands[d.id] =
            _move(d, DemandStatus.closed).copyWith(closeReason: reason.trim());
      });

  @override
  Future<Demand> recordOutcome(String demandId, OutcomeKind outcome) => _io(() {
        final d = _owned(demandId);
        // A self-reported success is kept apart from two-sided cooperations.
        return demands[d.id] = d.copyWith(outcome: outcome, outcomeAt: now);
      });

  @override
  Future<Demand> setShareRevoked(String demandId, bool revoked) => _io(() {
        final d = _owned(demandId);
        return demands[d.id] = d.copyWith(shareRevoked: revoked);
      });

  DesignSnapshot? _publicSnapshot(String? id, AttachmentVisibility v) {
    final s = id == null ? null : snapshots[id];
    if (s == null) return null;
    return DesignSnapshot(
        id: s.id,
        ownerId: s.ownerId,
        projectId: '',
        projectName: s.projectName,
        designUpdatedAt: s.designUpdatedAt,
        extractedAt: s.extractedAt,
        stages: s.stages,
        lines: v.quantities ? s.lines : const [],
        summary: s.summary,
        preview: v.plan ? s.preview : null,
        planJson: v.plan ? s.planJson : null);
  }

  @override
  Future<PublicDemandView?> publicView(String shareToken) => _read(() {
        final d =
            demands.values.where((d) => d.shareToken == shareToken).firstOrNull;
        if (d == null) return null;
        final v = d.current;
        final available = !d.shareRevoked &&
            !(accounts[d.ownerId]?.deleted ?? true) &&
            const {
              DemandStatus.open,
              DemandStatus.paused,
              DemandStatus.found,
              DemandStatus.expired
            }.contains(d.status);
        return PublicDemandView(
            available: available,
            type: d.type,
            title: available ? v.title : '',
            trades: available ? v.trades : const [],
            region: available ? v.region : '',
            locality: available ? v.locality : '',
            description: available ? v.description : '',
            budget: v.budget,
            hire: available ? v.hire : null,
            contract: available ? v.contract : null,
            snapshot:
                available ? _publicSnapshot(v.snapshotId, v.visibility) : null,
            status: available ? d.status : null);
      });

  // ───────────────────────── applications ─────────────────────────

  @override
  Future<Map<String, ({int total, int unread})>> myQuoteCounts() => _read(() {
        final me = _me;
        final out = <String, ({int total, int unread})>{};
        for (final a in applications.values) {
          final d = demands[a.demandId];
          if (d == null || d.ownerId != me) continue;
          if (a.status == ApplicationStatus.withdrawn ||
              a.status == ApplicationStatus.notSelected) continue;
          final c = out[d.id] ?? (total: 0, unread: 0);
          out[d.id] =
              (total: c.total + 1, unread: c.unread + (a.readByOwner ? 0 : 1));
        }
        return out;
      });

  @override
  Future<List<Application>> applicationsFor(String demandId) => _io(() {
        final d = _owned(demandId);
        final list = applications.values
            .where((a) => a.demandId == d.id)
            .toList()
          ..sort((a, b) => b.current.createdAt.compareTo(a.current.createdAt));
        for (final a in list) {
          if (!a.readByOwner)
            applications[a.id] = a.copyWith(readByOwner: true);
        }
        return [for (final a in list) applications[a.id]!];
      });

  @override
  Future<List<Application>> myApplications() => _read(() =>
      applications.values.where((a) => a.applicantId == _me).toList()
        ..sort((a, b) => b.current.createdAt.compareTo(a.current.createdAt)));

  @override
  Future<Application?> application(String id) => _read(() {
        final a = applications[id];
        if (a == null) return null;
        final me = currentId;
        if (a.applicantId == me || demands[a.demandId]?.ownerId == me) return a;
        return null;
      });

  ApplicationVersion _numberedApp(ApplicationVersion v, int no, int demandNo) =>
      ApplicationVersion(
          no: no,
          demandVersionNo: demandNo,
          createdAt: now,
          note: v.note.trim(),
          availableFrom: v.availableFrom,
          acceptsOffer: v.acceptsOffer,
          expectedWage: v.acceptsOffer ? null : v.expectedWage,
          headcountOffered: v.headcountOffered,
          scopeText: v.scopeText.trim(),
          materials: v.materials,
          pricing: v.pricing,
          lines: v.pricing == PricingMode.perQuantity ? v.lines : const [],
          lumpSum: v.pricing == PricingMode.lumpSum ? v.lumpSum : null,
          durationDays: v.durationDays,
          includes: v.includes.trim(),
          excludes: v.excludes.trim(),
          validUntil: v.validUntil);

  @override
  Future<Application> submit(
          {required String demandId,
          required String profileId,
          required ApplicationVersion version,
          required String requestId}) =>
      _io(() {
        final me = _me;
        _requireActive();
        final same = applications.values
            .where((a) => a.requestId == requestId && a.applicantId == me)
            .firstOrNull;
        if (same != null) return same;
        final d = demands[demandId];
        if (d == null) throw const ApiFailure(ApiCodes.notFound);
        if (d.ownerId == me) throw const ApiFailure(ApiCodes.ownDemand);
        if (_isBlocked(me, d.ownerId)) throw const ApiFailure(ApiCodes.blocked);
        if (!acceptsApplications(d, now))
          throw const ApiFailure(ApiCodes.notAccepting);
        final p = profiles[profileId];
        if (p == null || p.ownerId != me || p.status != ProfileStatus.active)
          throw const ApiFailure(ApiCodes.forbidden, 'profile');
        if (d.type == DemandType.hire) {
          if (version.headcountOffered < 1)
            throw const ApiFailure(ApiCodes.invalidInput, 'headcount');
          if (!version.acceptsOffer && (version.expectedWage ?? 0) <= 0)
            throw const ApiFailure(ApiCodes.invalidInput, 'wage');
        } else {
          final ok = switch (version.pricing) {
            PricingMode.perQuantity => version.lines.isNotEmpty &&
                version.lines.every((l) =>
                    l.name.trim().isNotEmpty &&
                    l.quantity > 0 &&
                    l.unitPrice > 0),
            PricingMode.lumpSum => (version.lumpSum ?? 0) > 0,
            PricingMode.siteConfirm => true,
          };
          if (!ok) throw const ApiFailure(ApiCodes.invalidInput, 'price');
          if (version.scopeText.trim().isEmpty)
            throw const ApiFailure(ApiCodes.invalidInput, 'scope');
        }
        final existing = applications.values
            .where((a) => a.demandId == d.id && a.profileId == p.id)
            .firstOrNull;
        if (existing != null) {
          if (existing.status == ApplicationStatus.cooperating ||
              existing.status == ApplicationStatus.pendingConfirm)
            throw const ApiFailure(ApiCodes.invalidState);
          final next =
              _numberedApp(version, existing.current.no + 1, d.current.no);
          applications[existing.id] = Application(
              id: existing.id,
              demandId: existing.demandId,
              profileId: existing.profileId,
              applicantId: existing.applicantId,
              status: ApplicationStatus.submitted,
              versions: [...existing.versions, next],
              createdAt: existing.createdAt,
              requestId: requestId);
          notice(d.ownerId, NoticeKind.newApplication, RefType.demand, d.id,
              title: d.current.title);
          return applications[existing.id]!;
        }
        final id = newId('app');
        applications[id] = Application(
            id: id,
            demandId: d.id,
            profileId: p.id,
            applicantId: me,
            status: ApplicationStatus.submitted,
            versions: [_numberedApp(version, 1, d.current.no)],
            createdAt: now,
            requestId: requestId);
        notice(d.ownerId, NoticeKind.newApplication, RefType.demand, d.id,
            title: d.current.title);
        return applications[id]!;
      });

  @override
  Future<Application> withdraw(String applicationId) => _io(() {
        final a = applications[applicationId];
        if (a == null) throw const ApiFailure(ApiCodes.notFound);
        if (a.applicantId != _me) throw const ApiFailure(ApiCodes.forbidden);
        if (a.status == ApplicationStatus.cooperating ||
            a.status == ApplicationStatus.withdrawn)
          throw const ApiFailure(ApiCodes.invalidState);
        for (final c in cooperations.values
            .where((c) =>
                c.applicationId == a.id &&
                c.status == CooperationStatus.pending)
            .toList()) {
          cooperations[c.id] = c.copyWith(
              status: CooperationStatus.notFormed,
              agreements: [
                for (final g in c.agreements)
                  g.copyWith(status: AgreementStatus.rejected)
              ]);
        }
        return applications[a.id] =
            a.copyWith(status: ApplicationStatus.withdrawn);
      });

  @override
  Future<Application> markNotSelected(String applicationId) => _io(() {
        final a = applications[applicationId];
        if (a == null) throw const ApiFailure(ApiCodes.notFound);
        _owned(a.demandId);
        if (a.status != ApplicationStatus.submitted)
          throw const ApiFailure(ApiCodes.invalidState);
        notice(a.applicantId, NoticeKind.applicationNotSelected, RefType.demand,
            a.demandId,
            title: demands[a.demandId]!.current.title);
        return applications[a.id] =
            a.copyWith(status: ApplicationStatus.notSelected);
      });

  // ───────────────────────── cooperations ─────────────────────────

  Cooperation _coop(String id) {
    final c = cooperations[id];
    if (c == null) throw const ApiFailure(ApiCodes.notFound);
    if (!c.involves(_me)) throw const ApiFailure(ApiCodes.forbidden);
    return c;
  }

  Agreement _agreementFrom(Agreement t, int version, String by, int demandNo,
          AgreementStatus status) =>
      Agreement(
          version: version,
          scope: t.scope.trim(),
          demandVersionNo: demandNo,
          proposedBy: by,
          confirmedBy: {by},
          status: status,
          createdAt: now,
          headcount: t.headcount,
          amount: t.amount,
          pricing: t.pricing,
          amountUnit: t.amountUnit,
          startDate: t.startDate,
          endDate: t.endDate,
          paymentTerms: t.paymentTerms.trim(),
          materialsResponsibility: t.materialsResponsibility.trim(),
          openItems: t.openItems.trim(),
          shareExactAddress: t.shareExactAddress);

  String _title(Cooperation c) => demands[c.demandId]?.current.title ?? '';

  @override
  Future<Cooperation> invite(String applicationId, Agreement terms) => _io(() {
        final me = _me;
        _requireActive();
        final a = applications[applicationId];
        if (a == null) throw const ApiFailure(ApiCodes.notFound);
        final d = _owned(a.demandId);
        if (a.status != ApplicationStatus.submitted)
          throw const ApiFailure(ApiCodes.invalidState);
        if (d.status == DemandStatus.closed)
          throw const ApiFailure(ApiCodes.invalidState);
        if (_isBlocked(me, a.applicantId))
          throw const ApiFailure(ApiCodes.blocked);
        if (terms.scope.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput, 'scope');
        if (terms.amount != null && terms.amount! <= 0)
          throw const ApiFailure(ApiCodes.invalidInput, 'amount');
        final id = newId('coop');
        cooperations[id] = Cooperation(
            id: id,
            demandId: d.id,
            applicationId: a.id,
            ownerId: me,
            providerId: a.applicantId,
            profileId: a.profileId,
            status: CooperationStatus.pending,
            agreements: [
              _agreementFrom(
                  terms, 1, me, d.current.no, AgreementStatus.proposed)
            ],
            milestones:
                d.type == DemandType.contract ? defaultMilestones : const [],
            createdAt: now);
        applications[a.id] =
            a.copyWith(status: ApplicationStatus.pendingConfirm);
        notice(
            a.applicantId, NoticeKind.confirmRequest, RefType.cooperation, id,
            title: d.current.title);
        return cooperations[id]!;
      });

  @override
  Future<Cooperation> confirm(String cooperationId) => _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.pending)
          throw const ApiFailure(ApiCodes.invalidState);
        final g = c.agreements.first;
        if (g.confirmedBy.contains(me))
          throw const ApiFailure(ApiCodes.invalidState, 'alreadyConfirmed');
        final confirmed = {...g.confirmedBy, me};
        final both =
            confirmed.contains(c.ownerId) && confirmed.contains(c.providerId);
        cooperations[c.id] = c.copyWith(
            status: both ? CooperationStatus.confirmed : null,
            agreements: [
              g.copyWith(
                  confirmedBy: confirmed,
                  status: both ? AgreementStatus.active : null)
            ]);
        if (both) {
          final a = applications[c.applicationId]!;
          applications[a.id] =
              a.copyWith(status: ApplicationStatus.cooperating);
          notice(c.otherSide(me), NoticeKind.cooperationConfirmed,
              RefType.cooperation, c.id,
              title: _title(c));
        }
        return cooperations[c.id]!;
      });

  Cooperation _notFormed(Cooperation c, NoticeKind kind, String to) {
    cooperations[c.id] = c
        .copyWith(status: CooperationStatus.notFormed, agreements: [
      for (final g in c.agreements) g.copyWith(status: AgreementStatus.rejected)
    ]);
    final a = applications[c.applicationId]!;
    if (a.status == ApplicationStatus.pendingConfirm)
      applications[a.id] = a.copyWith(status: ApplicationStatus.submitted);
    notice(to, kind, RefType.cooperation, c.id, title: _title(c));
    return cooperations[c.id]!;
  }

  @override
  Future<Cooperation> decline(String cooperationId) => _io(() {
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.pending || c.providerId != _me)
          throw const ApiFailure(ApiCodes.invalidState);
        return _notFormed(c, NoticeKind.cooperationDeclined, c.ownerId);
      });

  @override
  Future<Cooperation> revoke(String cooperationId) => _io(() {
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.pending || c.ownerId != _me)
          throw const ApiFailure(ApiCodes.invalidState);
        return _notFormed(c, NoticeKind.cooperationDeclined, c.providerId);
      });

  @override
  Future<Cooperation> proposeChange(String cooperationId, Agreement terms) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.confirmed || c.pendingChange != null)
          throw const ApiFailure(ApiCodes.invalidState);
        if (terms.scope.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput, 'scope');
        final next = _agreementFrom(terms, c.agreements.last.version + 1, me,
            demands[c.demandId]!.current.no, AgreementStatus.proposed);
        cooperations[c.id] = c.copyWith(agreements: [...c.agreements, next]);
        notice(c.otherSide(me), NoticeKind.agreementChange, RefType.cooperation,
            c.id,
            title: _title(c));
        return cooperations[c.id]!;
      });

  @override
  Future<Cooperation> answerChange(String cooperationId, bool accept) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        final change = c.pendingChange;
        if (change == null || change.proposedBy == me)
          throw const ApiFailure(ApiCodes.invalidState);
        final list = [
          for (final g in c.agreements)
            if (identical(g, change))
              g.copyWith(
                  confirmedBy: accept ? {...g.confirmedBy, me} : g.confirmedBy,
                  status: accept
                      ? AgreementStatus.active
                      : AgreementStatus.rejected)
            else if (accept && g.status == AgreementStatus.active)
              g.copyWith(status: AgreementStatus.superseded)
            else
              g
        ];
        cooperations[c.id] = c.copyWith(agreements: list);
        notice(change.proposedBy, NoticeKind.agreementChange,
            RefType.cooperation, c.id,
            title: _title(c));
        return cooperations[c.id]!;
      });

  @override
  Future<Cooperation> requestEnd(String cooperationId, String note) => _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.confirmed)
          throw const ApiFailure(ApiCodes.invalidState);
        if (c.endRequest != null && c.endRequest!.dispute == null)
          throw const ApiFailure(ApiCodes.invalidState, 'pending');
        cooperations[c.id] = c.copyWith(
            endRequest: EndRequest(by: me, at: now, note: note.trim()));
        notice(
            c.otherSide(me), NoticeKind.endRequest, RefType.cooperation, c.id,
            title: _title(c));
        return cooperations[c.id]!;
      });

  @override
  Future<Cooperation> confirmEnd(String cooperationId) => _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        final r = c.endRequest;
        if (c.status != CooperationStatus.confirmed ||
            r == null ||
            r.by == me ||
            r.dispute != null) throw const ApiFailure(ApiCodes.invalidState);
        cooperations[c.id] = c.copyWith(
            status: CooperationStatus.ended,
            endKind: EndKind.mutual,
            endedAt: now);
        // Record the cooperation on the profile; no owner drawings or
        // address are attached.
        final p = profiles[c.profileId];
        if (p != null && !p.works.any((w) => w.cooperationId == c.id)) {
          profiles[p.id] = p.copyWith(works: [
            ...p.works,
            Work(
                id: newId('work'),
                title: _title(c),
                source: WorkSource.platform,
                cooperationId: c.id)
          ]);
        }
        notice(r.by, NoticeKind.ended, RefType.cooperation, c.id,
            title: _title(c));
        return cooperations[c.id]!;
      });

  @override
  Future<Cooperation> disputeEnd(String cooperationId, String note) => _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        final r = c.endRequest;
        if (c.status != CooperationStatus.confirmed || r == null || r.by == me)
          throw const ApiFailure(ApiCodes.invalidState);
        if (note.trim().isEmpty) throw const ApiFailure(ApiCodes.invalidInput);
        cooperations[c.id] = c.copyWith(
            endRequest: EndRequest(
                by: r.by, at: r.at, note: r.note, dispute: note.trim()));
        notice(r.by, NoticeKind.endRequest, RefType.cooperation, c.id,
            title: _title(c));
        return cooperations[c.id]!;
      });

  @override
  Future<Cooperation> addUpdate(String cooperationId, String text) => _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.confirmed || text.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidState);
        return cooperations[c.id] = c.copyWith(updates: [
          ...c.updates,
          ProgressUpdate(by: me, at: now, text: text.trim())
        ]);
      });

  @override
  Future<Cooperation> requestMilestone(String cooperationId, int index,
          {String note = '', int photos = 0}) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.confirmed || me != c.providerId)
          throw const ApiFailure(ApiCodes.invalidState);
        if (index < 0 || index >= c.milestones.length)
          throw const ApiFailure(ApiCodes.invalidInput, 'milestone');
        final m = c.milestones[index];
        if (m.status == MilestoneStatus.accepted)
          throw const ApiFailure(ApiCodes.invalidState, 'accepted');
        final list = [...c.milestones];
        list[index] = m.copyWith(
            status: MilestoneStatus.requested,
            note: note.trim(),
            photoCount: photos,
            requestedAt: now);
        notice(
            c.ownerId, NoticeKind.milestoneRequested, RefType.cooperation, c.id,
            title: _title(c));
        return cooperations[c.id] = c.copyWith(milestones: list);
      });

  @override
  Future<Cooperation> answerMilestone(
          String cooperationId, int index, bool accept,
          {String note = ''}) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (me != c.ownerId) throw const ApiFailure(ApiCodes.forbidden);
        if (index < 0 || index >= c.milestones.length)
          throw const ApiFailure(ApiCodes.invalidInput, 'milestone');
        final m = c.milestones[index];
        if (m.status != MilestoneStatus.requested)
          throw const ApiFailure(ApiCodes.invalidState);
        if (!accept && note.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput, 'note');
        final list = [...c.milestones];
        list[index] = m.copyWith(
            status:
                accept ? MilestoneStatus.accepted : MilestoneStatus.disputed,
            note: accept ? m.note : note.trim(),
            answeredAt: now);
        notice(c.providerId, NoticeKind.milestoneAnswered, RefType.cooperation,
            c.id,
            title: _title(c));
        return cooperations[c.id] = c.copyWith(milestones: list);
      });

  @override
  Future<Cooperation> logWork(String cooperationId, int headcount,
          {String note = '', int photos = 0}) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (c.status != CooperationStatus.confirmed || me != c.providerId)
          throw const ApiFailure(ApiCodes.invalidState);
        if (headcount < 1 || headcount > 200)
          throw const ApiFailure(ApiCodes.invalidInput, 'headcount');
        final day = DateTime.utc(now.year, now.month, now.day);
        final rest = c.workLogs.where((w) => w.day != day);
        final log = WorkLog(
            id: newId('wl'),
            by: me,
            day: day,
            headcount: headcount,
            note: note.trim(),
            photoCount: photos);
        notice(c.ownerId, NoticeKind.workLogged, RefType.cooperation, c.id,
            title: _title(c));
        return cooperations[c.id] = c.copyWith(workLogs: [log, ...rest]);
      });

  @override
  Future<Cooperation> confirmWork(String cooperationId, String logId) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (me != c.ownerId) throw const ApiFailure(ApiCodes.forbidden);
        if (!c.workLogs.any((w) => w.id == logId))
          throw const ApiFailure(ApiCodes.notFound);
        return cooperations[c.id] = c.copyWith(workLogs: [
          for (final w in c.workLogs) w.id == logId ? w.confirm() : w
        ]);
      });

  @override
  Future<Cooperation?> cooperation(String id) => _read(() {
        final c = cooperations[id];
        return c != null && currentId != null && c.involves(currentId!)
            ? c
            : null;
      });

  @override
  Future<List<Cooperation>> myCooperations() =>
      _read(() => cooperations.values.where((c) => c.involves(_me)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<List<Cooperation>> cooperationsFor(String demandId) => _read(() {
        final me = _me;
        final d = demands[demandId];
        if (d == null) return const <Cooperation>[];
        return cooperations.values
            .where((c) =>
                c.demandId == demandId &&
                (d.ownerId == me || c.providerId == me))
            .toList();
      });

  // ─────────────────────────── reviews ───────────────────────────

  List<Review> _reviewsOf(String coopId) =>
      reviews.values.where((r) => r.cooperationId == coopId).toList();

  @override
  Future<Review> submitReview(
          String cooperationId, Map<String, int> scores, String text) =>
      _io(() {
        final me = _me;
        final c = _coop(cooperationId);
        if (!reviewsOpen(c, now)) throw const ApiFailure(ApiCodes.invalidState);
        if (_reviewsOf(c.id).any((r) => r.authorId == me))
          throw const ApiFailure(ApiCodes.invalidState, 'reviewed');
        if (scores.isEmpty ||
            scores.entries.any((e) =>
                !reviewDimensions.contains(e.key) ||
                e.value < 1 ||
                e.value > 5)) throw const ApiFailure(ApiCodes.invalidInput);
        final id = newId('rev');
        reviews[id] = Review(
            id: id,
            cooperationId: c.id,
            authorId: me,
            targetId: c.otherSide(me),
            scores: scores,
            text: text.trim(),
            createdAt: now);
        notice(c.otherSide(me), NoticeKind.reviewReceived, RefType.cooperation,
            c.id,
            title: _title(c));
        return reviews[id]!;
      });

  @override
  Future<List<Review>> reviewsFor(String cooperationId) => _read(() {
        final me = _me;
        final c = _coop(cooperationId);
        final all = _reviewsOf(c.id);
        final visible = reviewsVisible(c, all, now);
        return all.where((r) => r.authorId == me || visible).toList();
      });

  @override
  Future<List<Review>> reviewsAbout(String accountId) =>
      _read(() => reviews.values.where((r) {
            if (r.targetId != accountId) return false;
            final c = cooperations[r.cooperationId]!;
            return reviewsVisible(c, _reviewsOf(c.id), now);
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  // ───────────────────────────── chat ─────────────────────────────

  Conversation _conv(String id) {
    final c = convs[id];
    if (c == null) throw const ApiFailure(ApiCodes.notFound);
    if (!c.participants.contains(_me))
      throw const ApiFailure(ApiCodes.forbidden);
    return c;
  }

  List<ChatMessage> _messagesOf(String convId) =>
      messagesById.values.where((m) => m.conversationId == convId).toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  int _unreadIn(String convId, String me) {
    final since = _lastRead['$me|$convId'];
    return _messagesOf(convId)
        .where((m) =>
            m.senderId != me &&
            m.state == SendState.sent &&
            (since == null || m.sentAt.isAfter(since)))
        .length;
  }

  Conversation _withSummary(Conversation c, String me) {
    final list = _messagesOf(c.id);
    return Conversation(
        id: c.id,
        participants: c.participants,
        createdAt: c.createdAt,
        demandId: c.demandId,
        lastMessage: list.lastOrNull,
        unread: _unreadIn(c.id, me));
  }

  @override
  Future<List<Conversation>> conversations() => _read(() {
        final me = _me;
        return convs.values
            .where((c) => c.participants.contains(me))
            .map((c) => _withSummary(c, me))
            .toList()
          ..sort((a, b) => (b.lastMessage?.sentAt ?? b.createdAt)
              .compareTo(a.lastMessage?.sentAt ?? a.createdAt));
      });

  Conversation openOrCreate(String me, String other, {String? demandId}) {
    final existing = convs.values
        .where((c) =>
            c.participants.contains(me) && c.participants.contains(other))
        .firstOrNull;
    if (existing != null) {
      if (demandId != null && existing.demandId != demandId) {
        convs[existing.id] = Conversation(
            id: existing.id,
            participants: existing.participants,
            createdAt: existing.createdAt,
            demandId: demandId);
      }
      return convs[existing.id]!;
    }
    final id = newId('conv');
    return convs[id] = Conversation(
        id: id, participants: [me, other], createdAt: now, demandId: demandId);
  }

  @override
  Future<Conversation> openConversation(String otherAccountId,
          {String? demandId}) =>
      _io(() {
        final me = _me;
        if (otherAccountId == me || accounts[otherAccountId] == null)
          throw const ApiFailure(ApiCodes.invalidInput);
        return _withSummary(
            openOrCreate(me, otherAccountId, demandId: demandId), me);
      });

  @override
  Future<List<ChatMessage>> messages(String conversationId) =>
      _read(() => _messagesOf(_conv(conversationId).id));

  ChatMessage addMessage(String convId, String sender, MessageKind kind,
      {String text = '', String? refId, SendState state = SendState.sent}) {
    final id = newId('msg');
    return messagesById[id] = ChatMessage(
        id: id,
        conversationId: convId,
        senderId: sender,
        kind: kind,
        sentAt: now,
        text: text,
        refId: refId,
        state: state);
  }

  @override
  Future<ChatMessage> send(String conversationId, MessageKind kind,
          {String text = '', String? refId}) =>
      _io(() {
        final me = _me;
        _requireActive();
        final c = _conv(conversationId);
        if (_isBlocked(me, c.otherSide(me)))
          throw const ApiFailure(ApiCodes.blocked);
        if (kind == MessageKind.text && text.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput);
        if (kind == MessageKind.system || kind == MessageKind.phoneShared)
          throw const ApiFailure(ApiCodes.forbidden);
        final recent = _messagesOf(c.id).where((m) =>
            m.senderId == me &&
            m.sentAt.isAfter(now.subtract(const Duration(minutes: 1))));
        if (recent.length >= chatLimitPerMinute)
          throw const ApiFailure(ApiCodes.rateLimited);
        _lastRead['$me|${c.id}'] = now;
        return addMessage(c.id, me, kind,
            text: text.trim(),
            refId: refId,
            state: simulateOffline ? SendState.failed : SendState.sent);
      });

  @override
  Future<ChatMessage> resend(String messageId) => _io(() {
        final m = messagesById[messageId];
        if (m == null) throw const ApiFailure(ApiCodes.notFound);
        if (m.senderId != _me) throw const ApiFailure(ApiCodes.forbidden);
        if (m.state != SendState.failed) return m;
        if (simulateOffline) throw const ApiFailure(ApiCodes.network);
        return messagesById[m.id] =
            m.copyWith(state: SendState.sent, sentAt: now);
      });

  @override
  Future<void> markConversationRead(String conversationId) => _io(() {
        final c = _conv(conversationId);
        _lastRead['$_me|${c.id}'] = now;
      });

  @override
  Future<void> block(String accountId) =>
      _io(() => _blocks.putIfAbsent(_me, () => {}).add(accountId));

  @override
  Future<void> unblock(String accountId) =>
      _io(() => _blocks[_me]?.remove(accountId));

  @override
  Future<Set<String>> blocked() => _read(() => {...?_blocks[currentId]});

  @override
  Future<ChatMessage> sharePhone(String conversationId) => _io(() {
        final me = _me;
        final c = _conv(conversationId);
        if (_isBlocked(me, c.otherSide(me)))
          throw const ApiFailure(ApiCodes.blocked);
        return addMessage(c.id, me, MessageKind.phoneShared,
            text: _meAccount.phone);
      });

  @override
  Future<int> unreadMessages() => _read(() {
        final me = currentId;
        if (me == null) return 0;
        return convs.values
            .where((c) => c.participants.contains(me))
            .fold(0, (s, c) => s + _unreadIn(c.id, me));
      });

  // ───────────────────────── notifications ─────────────────────────

  @override
  Future<List<AppNotification>> notifications() =>
      _read(() => notices.values.where((n) => n.accountId == _me).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<int> unreadNotifications() => _read(() => currentId == null
      ? 0
      : notices.values
          .where((n) => n.accountId == currentId && !n.read)
          .length);

  @override
  Future<void> markRead(String id) => _io(() {
        final n = notices[id];
        if (n != null && n.accountId == _me) notices[id] = n.markRead();
      });

  @override
  Future<void> markAllRead() => _io(() {
        final me = _me;
        for (final n
            in notices.values.where((n) => n.accountId == me).toList()) {
          notices[n.id] = n.markRead();
        }
      });

  // ─────────────────────────── snapshots ───────────────────────────

  @override
  Future<DesignSnapshot> saveSnapshot(DesignSnapshot s) => _io(() {
        final me = _me;
        final id = newId('snap');
        return snapshots[id] = DesignSnapshot(
            id: id,
            ownerId: me,
            projectId: s.projectId,
            projectName: s.projectName,
            designUpdatedAt: s.designUpdatedAt,
            extractedAt: now,
            stages: s.stages,
            lines: s.lines,
            summary: s.summary,
            preview: s.preview,
            planJson: s.planJson);
      });

  @override
  Future<DesignSnapshot?> snapshot(String id,
          {String? postId, String? demandId}) =>
      _read(() {
        final s = snapshots[id];
        if (s == null) return null;
        if (postId != null) {
          final p = posts[postId];
          if (p == null || p.snapshotId != id || !_postVisible(p)) return null;
          return _publicSnapshot(id, const AttachmentVisibility());
        }
        if (demandId != null) {
          final d = demands[demandId];
          if (d == null || d.current.snapshotId != id || !_demandVisible(d))
            return null;
          return s.ownerId == currentId
              ? s
              : _publicSnapshot(id, d.current.visibility);
        }
        if (s.ownerId == currentId) return s;
        if (posts.values.any((p) => p.snapshotId == id && _postVisible(p))) {
          return _publicSnapshot(id, const AttachmentVisibility());
        }
        final d = demands.values
            .where((d) => d.current.snapshotId == id && _demandVisible(d))
            .firstOrNull;
        return d == null ? null : _publicSnapshot(id, d.current.visibility);
      });

  // ──────────────────────────── backups ────────────────────────────

  @override
  Future<List<BackupRecord>> backups() =>
      _read(() => [...?backupsByAccount[_me]?.values]);

  @override
  Future<BackupRecord?> backup(String projectId) =>
      _read(() => backupsByAccount[_me]?[projectId]);

  @override
  Future<BackupRecord> upload(
          {required String projectId,
          required String name,
          required String houseText,
          required String designUpdatedAt,
          String? expectedPreviousUpdatedAt}) =>
      _io(() {
        final me = _me;
        if (simulateOffline) throw const ApiFailure(ApiCodes.network);
        final store = backupsByAccount.putIfAbsent(me, () => {});
        final old = store[projectId];
        // Never overwrite a backup that changed elsewhere since this device
        // last saw it.
        if (old != null &&
            expectedPreviousUpdatedAt != null &&
            old.designUpdatedAt != expectedPreviousUpdatedAt &&
            old.designUpdatedAt != designUpdatedAt)
          throw const ApiFailure(ApiCodes.conflict);
        return store[projectId] = BackupRecord(
            projectId: projectId,
            name: name,
            houseText: houseText,
            backedUpAt: now,
            designUpdatedAt: designUpdatedAt);
      });

  /// Developer tool: pretend another device changed the cloud copy.
  void touchBackupFromOtherDevice(
      String projectId, String houseText, String designUpdatedAt) {
    final store = backupsByAccount[currentId];
    final old = store?[projectId];
    if (store == null || old == null) return;
    store[projectId] = BackupRecord(
        projectId: projectId,
        name: old.name,
        houseText: houseText,
        backedUpAt: now,
        designUpdatedAt: designUpdatedAt);
    notify();
  }

  // ─────────────────────────── house posts ───────────────────────────

  bool _postVisible(HousePost p) {
    if (p.ownerId == currentId) return true;
    final owner = accounts[p.ownerId];
    if (owner == null || owner.deleted) return false;
    if (currentId != null && _isBlocked(currentId!, p.ownerId)) return false;
    return p.status == PostStatus.published;
  }

  @override
  Future<List<HousePost>> feed(FeedFilter f) => _read(() {
        final q = f.query.trim().toLowerCase();
        final list = posts.values.where((p) {
          if (!_postVisible(p) || p.status != PostStatus.published)
            return false;
          if (f.region != null && p.region != f.region) return false;
          if (f.openForBuilders && !p.openForBuilders) return false;
          if (q.isNotEmpty &&
              !p.title.toLowerCase().contains(q) &&
              !p.story.toLowerCase().contains(q)) return false;
          return true;
        }).toList();
        switch (f.sort) {
          case FeedSort.newest:
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          case FeedSort.popular:
            list.sort((a, b) => (b.likeCount * 2 + b.commentCount)
                .compareTo(a.likeCount * 2 + a.commentCount));
          case FeedSort.topRated:
            list.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        }
        return list;
      });

  @override
  Future<HousePost?> post(String id) => _read(() {
        final p = posts[id];
        return p == null || !_postVisible(p) ? null : p;
      });

  @override
  Future<List<HousePost>> myPosts() =>
      _read(() => posts.values.where((p) => p.ownerId == _me).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<List<HousePost>> postsBy(String accountId) => _read(() => posts.values
      .where((p) => p.ownerId == accountId && _postVisible(p))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<HousePost> publishPost(HousePost d) => _io(() {
        final me = _me;
        _requireActive();
        final snap = snapshots[d.snapshotId];
        if (snap == null || snap.ownerId != me)
          throw const ApiFailure(ApiCodes.forbidden, 'snapshot');
        if (d.title.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput, 'title');
        final word = bannedWordIn('${d.title} ${d.story}');
        if (word != null)
          throw ApiFailure(ApiCodes.invalidInput, 'banned:$word');
        final id = newId('post');
        return posts[id] = HousePost(
            id: id,
            ownerId: me,
            projectId: d.projectId,
            snapshotId: d.snapshotId,
            title: d.title.trim(),
            story: d.story.trim(),
            region: d.region,
            createdAt: now,
            updatedAt: now,
            area: d.area,
            floors: d.floors,
            rooms: d.rooms,
            estimatedCost: d.estimatedCost,
            tags: d.tags,
            openForBuilders: d.openForBuilders,
            preview: d.preview ?? snap.preview);
      });

  @override
  Future<HousePost> updatePost(HousePost p) => _io(() {
        final old = posts[p.id];
        if (old == null) throw const ApiFailure(ApiCodes.notFound);
        if (old.ownerId != _me) throw const ApiFailure(ApiCodes.forbidden);
        final word = bannedWordIn('${p.title} ${p.story}');
        if (word != null)
          throw ApiFailure(ApiCodes.invalidInput, 'banned:$word');
        return posts[p.id] = old.copyWith(
            title: p.title.trim(),
            story: p.story.trim(),
            region: p.region,
            tags: p.tags,
            openForBuilders: p.openForBuilders,
            updatedAt: now);
      });

  @override
  Future<void> hidePost(String id) => _io(() {
        final p = posts[id];
        if (p == null) throw const ApiFailure(ApiCodes.notFound);
        if (p.ownerId != _me && !_meAccount.isAdmin)
          throw const ApiFailure(ApiCodes.forbidden);
        posts[id] = p.copyWith(status: PostStatus.hidden, updatedAt: now);
      });

  @override
  Future<String?> reusePost(String postId) => _io(() {
        final p = posts[postId];
        if (p == null || !_postVisible(p))
          throw const ApiFailure(ApiCodes.notFound);
        final plan = snapshots[p.snapshotId]?.planJson;
        if (plan == null) throw const ApiFailure(ApiCodes.notFound, 'plan');
        posts[postId] = p.copyWith(reuseCount: p.reuseCount + 1);
        if (p.ownerId != currentId)
          notice(p.ownerId, NoticeKind.postReused, RefType.post, postId,
              title: p.title);
        return plan;
      });

  @override
  Future<bool> toggleLike(String postId) => _io(() {
        final me = _me;
        final p = posts[postId];
        if (p == null || !_postVisible(p))
          throw const ApiFailure(ApiCodes.notFound);
        final set = likes.putIfAbsent(postId, () => {});
        final on = !set.remove(me);
        if (on) set.add(me);
        posts[postId] = p.copyWith(likeCount: set.length);
        if (on && p.ownerId != me)
          notice(p.ownerId, NoticeKind.postLiked, RefType.post, postId,
              title: p.title);
        return on;
      });

  @override
  Future<bool> liked(String postId) => _read(
      () => currentId != null && (likes[postId]?.contains(currentId) ?? false));

  @override
  Future<List<String>> likedPosts() => _read(() => [
        for (final e in likes.entries)
          if (currentId != null && e.value.contains(currentId)) e.key
      ]);

  @override
  Future<List<PostComment>> comments(String postId) => _read(() {
        final p = posts[postId];
        if (p == null || !_postVisible(p)) return const [];
        return commentsById.values
            .where((c) =>
                c.postId == postId &&
                !(accounts[c.authorId]?.deleted ?? true) &&
                (currentId == null || !_isBlocked(currentId!, c.authorId)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

  @override
  Future<PostComment> comment(String postId, String text, {int? rating}) =>
      _io(() {
        final me = _me;
        _requireActive();
        final p = posts[postId];
        if (p == null || !_postVisible(p))
          throw const ApiFailure(ApiCodes.notFound);
        if (text.trim().isEmpty && rating == null)
          throw const ApiFailure(ApiCodes.invalidInput, 'empty');
        if (rating != null && (rating < 1 || rating > 5))
          throw const ApiFailure(ApiCodes.invalidInput, 'rating');
        if (rating != null && p.ownerId == me)
          throw const ApiFailure(ApiCodes.invalidState, 'own');
        final word = bannedWordIn(text);
        if (word != null)
          throw ApiFailure(ApiCodes.invalidInput, 'banned:$word');
        final times = _commentTimes.putIfAbsent(me, () => [])
          ..removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
        if (times.length >= 10) throw const ApiFailure(ApiCodes.rateLimited);
        times.add(now);
        // One rating per person: a new rating replaces the old one.
        var sum = p.ratingSum, count = p.ratingCount;
        if (rating != null) {
          final prev = commentsById.values
              .where((c) =>
                  c.postId == postId && c.authorId == me && c.rating != null)
              .toList();
          for (final c in prev) {
            sum -= c.rating!;
            count--;
            commentsById.remove(c.id);
          }
          sum += rating;
          count++;
        }
        final id = newId('cmt');
        final c = commentsById[id] = PostComment(
            id: id,
            postId: postId,
            authorId: me,
            text: text.trim(),
            rating: rating,
            createdAt: now);
        posts[postId] = p.copyWith(
            commentCount:
                commentsById.values.where((c) => c.postId == postId).length,
            ratingSum: sum,
            ratingCount: count);
        if (p.ownerId != me)
          notice(p.ownerId, NoticeKind.postCommented, RefType.post, postId,
              title: p.title);
        return c;
      });

  @override
  Future<void> deleteComment(String id) => _io(() {
        final c = commentsById[id];
        if (c == null) throw const ApiFailure(ApiCodes.notFound);
        final p = posts[c.postId]!;
        if (c.authorId != _me && p.ownerId != _me && !_meAccount.isAdmin)
          throw const ApiFailure(ApiCodes.forbidden);
        commentsById.remove(id);
        posts[p.id] = p.copyWith(
            commentCount:
                commentsById.values.where((x) => x.postId == p.id).length,
            ratingSum: c.rating == null ? null : p.ratingSum - c.rating!,
            ratingCount: c.rating == null ? null : p.ratingCount - 1);
      });

  @override
  Future<List<Demand>> demandsForPost(String postId) => _read(() {
        final p = posts[postId];
        if (p == null || !_postVisible(p)) return const [];
        return demands.values
            .where((d) =>
                d.ownerId == p.ownerId &&
                (d.current.snapshotId == p.snapshotId ||
                    d.designProjectId == p.projectId) &&
                _demandVisible(d) &&
                d.status != DemandStatus.draft &&
                d.status != DemandStatus.rejected)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

  // ─────────────────────────── moderation ───────────────────────────

  @override
  Future<void> report(ReportTarget target, String targetId, String reason) =>
      _io(() {
        final me = _me;
        if (reason.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput);
        final dup = reportsById.values.any((r) =>
            r.reporterId == me &&
            r.targetId == targetId &&
            r.status == ReportStatus.open);
        if (dup) return;
        final id = newId('rep');
        reportsById[id] = Report(
            id: id,
            reporterId: me,
            target: target,
            targetId: targetId,
            reason: reason.trim(),
            createdAt: now);
      });

  @override
  Future<List<Demand>> reviewQueue() => _read(() {
        _requireAdmin();
        return demands.values
            .where((d) => d.status == DemandStatus.pendingReview)
            .toList();
      });

  @override
  Future<void> approve(String demandId) => _io(() {
        _requireAdmin();
        final d = demands[demandId];
        if (d == null || d.status != DemandStatus.pendingReview)
          throw const ApiFailure(ApiCodes.invalidState);
        _decide(d, true, _me, 'manual');
      });

  @override
  Future<void> reject(String demandId, String reason) => _io(() {
        _requireAdmin();
        final d = demands[demandId];
        if (d == null ||
            (d.status != DemandStatus.pendingReview &&
                d.status != DemandStatus.open &&
                d.status != DemandStatus.paused))
          throw const ApiFailure(ApiCodes.invalidState);
        if (reason.trim().isEmpty)
          throw const ApiFailure(ApiCodes.invalidInput);
        _decide(d, false, _me, reason.trim());
      });

  @override
  Future<List<Report>> reports() => _read(() {
        _requireAdmin();
        return reportsById.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

  @override
  Future<void> resolveReport(String reportId, bool upheld, String note) =>
      _io(() {
        _requireAdmin();
        final me = _me;
        final r = reportsById[reportId];
        if (r == null || r.status != ReportStatus.open)
          throw const ApiFailure(ApiCodes.invalidState);
        if (note.trim().isEmpty) throw const ApiFailure(ApiCodes.invalidInput);
        reportsById[r.id] = r.handle(
            upheld ? ReportStatus.upheld : ReportStatus.dismissed,
            me,
            now,
            note.trim());
        if (upheld) {
          switch (r.target) {
            case ReportTarget.demand:
              final d = demands[r.targetId];
              if (d != null && canMoveDemand(d.status, DemandStatus.rejected))
                _decide(d, false, me, note.trim());
            case ReportTarget.profile:
              final p = profiles[r.targetId];
              if (p != null)
                profiles[p.id] = p.copyWith(status: ProfileStatus.hidden);
            case ReportTarget.account:
              final a = accounts[r.targetId];
              if (a != null) accounts[a.id] = a.copyWith(restricted: true);
            case ReportTarget.message:
              break;
          }
        }
        auditLog.add(AuditEntry(
            by: me,
            at: now,
            action: upheld ? 'uphold' : 'dismiss',
            targetId: r.targetId,
            reason: note.trim()));
      });

  @override
  Future<List<AuditEntry>> audit() => _read(() {
        _requireAdmin();
        return auditLog.reversed.toList();
      });
}
