import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/houses/model/my_house.dart';
import 'package:yusal/services/storage/project_store.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/shared/state/session.dart';

/// My houses: the houses tab's list and each house's workspace.
final myHousesProvider = FutureProvider.autoDispose<List<MyHouse>>(_myHouses);

/// Builds my houses from local designs and my demands. Designs without any
/// platform activity are left to the design list.
Future<List<MyHouse>> _myHouses(Ref ref) async {
  final session = ref.watch(sessionProvider);
  final store = ref.watch(projectStoreProvider);
  final posts = ref.watch(postRepositoryProvider);
  final demandRepo = ref.watch(demandRepositoryProvider);
  final applications = ref.watch(applicationRepositoryProvider);
  final snapshots = ref.watch(snapshotRepositoryProvider);
  final cooperations = ref.watch(cooperationRepositoryProvider);
  if (session.currentAccount == null) return const [];
  // Independent reads go out together instead of one after another.
  final postsF = _quiet(posts.myPosts);
  final projectsF = store.listProjects();
  final demandsF = demandRepo.myDemands();
  final countsF = applications.myQuoteCounts();
  // Waits for all three, so a failure of one leaves none unhandled, and
  // rethrows the first failure as it is.
  await Future.wait<Object?>([projectsF, demandsF, countsF]);
  final designs = {for (final e in await projectsF) e.id: e};
  final counts = await countsF;
  final demands = (await demandsF)
      .where((d) =>
          d.status != DemandStatus.draft && d.status != DemandStatus.rejected)
      .toList();
  final byKey = <String, MyHouse>{};
  final snaps = <String, Future<DesignSnapshot?>>{};
  for (final d in demands) {
    final sid = d.current.snapshotId;
    if (sid != null) {
      snaps[sid] ??= _quiet(() => snapshots.snapshot(sid, demandId: d.id));
    }
  }
  final coopsF = Future.wait(
      [for (final d in demands) cooperations.cooperationsFor(d.id)]);
  for (final d in demands) {
    final sid = d.current.snapshotId;
    final snap = sid == null ? null : await snaps[sid];
    // One house per design: the linked project, else the design the
    // published extract came from, else the demand on its own.
    final pid = d.designProjectId ?? snap?.projectId;
    final design = pid == null ? null : designs[pid];
    final key = pid ?? 'demand:${d.id}';
    var h = byKey[key];
    if (h == null) {
      final post =
          design == null ? await _quiet(() => posts.postForDemand(d.id)) : null;
      h = byKey[key] = MyHouse(
          key: key,
          name: design?.document.meta.name ??
              post?.title ??
              (snap?.projectName.isNotEmpty == true
                  ? snap!.projectName
                  : null) ??
              d.current.title,
          projectId: design == null ? null : pid,
          preview: design?.preview ?? post?.preview ?? snap?.preview,
          postId: post?.id);
    }
    h.demands.add(d);
    final c = counts[d.id];
    if (c != null) h.quotes[d.id] = c;
  }
  // Houses I shared: attach critiques to the house they belong to, or
  // list a shared-only design as its own house.
  for (final p in await postsF ?? const <HousePost>[]) {
    if (p.status != PostStatus.published) continue;
    final existing = byKey[p.projectId] ??
        byKey.values.where((h) => h.postId == p.id).firstOrNull;
    (existing ??
        (byKey[p.projectId] = MyHouse(
            key: p.projectId,
            name: designs[p.projectId]?.document.meta.name ?? p.title,
            projectId: designs.containsKey(p.projectId) ? p.projectId : null,
            preview: designs[p.projectId]?.preview ?? p.preview,
            postId: p.id)))
      ..comments = p.commentCount
      ..sharedAt = p.updatedAt;
  }
  final coopLists = await coopsF;
  final coops = {
    for (var i = 0; i < demands.length; i++) demands[i].id: coopLists[i]
  };
  for (final h in byKey.values) {
    for (final d in h.demands) {
      h.cooperations.addAll(coops[d.id]!);
    }
  }
  final list = byKey.values.toList()
    ..sort((a, b) => _latest(b).compareTo(_latest(a)));
  return list;
}

Future<T?> _quiet<T>(Future<T?> Function() f) async {
  try {
    return await f();
  } catch (_) {
    return null;
  }
}

DateTime _latest(MyHouse h) => h.demands
    .map((d) => d.current.createdAt)
    .fold(h.sharedAt ?? DateTime(2000), (a, b) => a.isAfter(b) ? a : b);

/// One of [myHousesProvider]'s houses by its key, or null.
final myHouseProvider =
    FutureProvider.autoDispose.family<MyHouse?, String>((ref, key) async {
  // Loads on its own, so a reload of this house reloads the list it
  // comes from.
  for (final h in await _myHouses(ref)) {
    if (h.key == key) return h;
  }
  return null;
});
