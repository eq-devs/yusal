import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/shared/state/session.dart';

/// What the demand page shows. [demand] is null when it is gone or hidden.
class DemandDetailData {
  DemandDetailData(this.demand, this.owner, this.snapshot, this.myApps,
      this.coops, this.applicationCount);
  final Demand? demand;
  final Account? owner;
  final DesignSnapshot? snapshot;

  /// The caller's own quotes on it (none for its owner).
  final List<Application> myApps;
  final List<Cooperation> coops;

  /// Quotes received, for its owner.
  final int applicationCount;
}

/// One demand with its owner, design and the caller's part in it, by id.
final demandDetailProvider = FutureProvider.autoDispose
    .family<DemandDetailData, String>((ref, demandId) async {
  final demands = ref.watch(demandRepositoryProvider);
  final apps = ref.watch(applicationRepositoryProvider);
  final d = await demands.demand(demandId);
  if (d == null) {
    return DemandDetailData(null, null, null, const [], const [], 0);
  }
  final me = ref.watch(sessionProvider).currentAccount?.id;
  final mine = me == d.ownerId;
  final (owner, snapshot, applications, cooperations, received) = await (
    ref.watch(authRepositoryProvider).account(d.ownerId),
    d.current.snapshotId == null
        ? Future<DesignSnapshot?>.value()
        : ref
            .watch(snapshotRepositoryProvider)
            .snapshot(d.current.snapshotId!, demandId: d.id),
    me == null || mine
        ? Future.value(const <Application>[])
        : apps
            .myApplications()
            .then((all) => all.where((a) => a.demandId == d.id).toList()),
    me == null
        ? Future.value(const <Cooperation>[])
        : ref.watch(cooperationRepositoryProvider).cooperationsFor(d.id),
    mine
        ? apps.applicationsFor(d.id).then((all) => all.length)
        : Future.value(0)
  ).wait;
  return DemandDetailData(
      d, owner, snapshot, applications, cooperations, received);
});

/// The public house a demand belongs to, if its owner published one.
final postForDemandProvider = FutureProvider.autoDispose
    .family<HousePost?, String>((ref, demandId) =>
        ref.watch(postRepositoryProvider).postForDemand(demandId));

/// What the publisher's quote list shows.
class ApplicationsData {
  ApplicationsData(this.demand, this.apps, this.profiles, this.coops);
  final Demand demand;
  final List<Application> apps;

  /// Each quote's profile, by profile id.
  final Map<String, ServiceProfile?> profiles;
  final List<Cooperation> coops;
}

/// A demand's quotes, their profiles and its cooperations, by demand id.
final applicationsProvider = FutureProvider.autoDispose
    .family<ApplicationsData, String>((ref, demandId) async {
  final profiles = ref.watch(profileRepositoryProvider);
  final d = (await ref.watch(demandRepositoryProvider).demand(demandId))!;
  final (apps, coops) = await (
    ref.watch(applicationRepositoryProvider).applicationsFor(d.id),
    ref.watch(cooperationRepositoryProvider).cooperationsFor(d.id)
  ).wait;
  final found =
      await Future.wait([for (final a in apps) profiles.profile(a.profileId)]);
  return ApplicationsData(d, apps,
      {for (final (i, a) in apps.indexed) a.profileId: found[i]}, coops);
});

/// The caller's demands published from one local design, by project id.
final linkedDemandsProvider = FutureProvider.autoDispose
    .family<List<Demand>, String>((ref, projectId) async {
  if (ref.watch(sessionProvider).currentAccount == null) return const [];
  return (await ref.watch(demandRepositoryProvider).myDemands())
      .where((d) => d.designProjectId == projectId)
      .toList();
});

/// What an outside visitor sees of a shared demand, and the demand itself.
/// Keyed by (demand id, share token).
final sharePreviewProvider = FutureProvider.autoDispose
    .family<(PublicDemandView?, Demand?), (String, String)>((ref, key) async {
  final (id, token) = key;
  final demands = ref.watch(demandRepositoryProvider);
  return (await demands.publicView(token), await demands.demand(id));
});
