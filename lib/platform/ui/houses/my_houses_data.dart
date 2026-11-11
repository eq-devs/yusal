import '../../../app/settings.dart';
import '../../../storage/project_store.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../house_progress.dart';

/// One of my houses as the platform sees it: a local design (if any) plus
/// every demand, quote and cooperation hanging off it. A demand published
/// without a design becomes its own light house.
class MyHouse {
  MyHouse(
      {required this.key,
      required this.name,
      this.projectId,
      this.preview,
      this.postId,
      this.comments = 0,
      this.sharedAt,
      List<Demand>? demands})
      : demands = demands ?? [];
  final String key, name;
  final String? projectId;
  final List<int>? preview;

  /// My public house page, if I published one, with its critiques.
  final String? postId;
  int comments;
  DateTime? sharedAt;

  /// Shared only to hear opinions: nothing to manage but the house page.
  bool get shareOnly => demands.isEmpty && postId != null;
  final List<Demand> demands;
  final cooperations = <Cooperation>[];
  final quotes = <String, ({int total, int unread})>{};

  bool get hasDesign => !key.startsWith('demand:');
  int get quoteCount => quotes.values.fold(0, (s, c) => s + c.total);
  int get newQuotes => quotes.values.fold(0, (s, c) => s + c.unread);

  HouseStage get stage {
    if (cooperations.isNotEmpty &&
        cooperations.every((c) => c.status == CooperationStatus.ended))
      return HouseStage.done;
    if (cooperations.any((c) => c.status == CooperationStatus.confirmed))
      return HouseStage.building;
    final s = stageFromDemands(demands);
    return s == HouseStage.design && demands.isNotEmpty
        ? HouseStage.finding
        : s;
  }

  /// Agreements waiting for my confirmation.
  int pendingConfirm(String me) => cooperations
      .where((c) =>
          (c.status == CooperationStatus.pending &&
              !c.agreement.confirmedBy.contains(me)) ||
          (c.pendingChange != null &&
              !c.pendingChange!.confirmedBy.contains(me)))
      .length;

  /// The other side asked to end and waits for my answer.
  int endAsks(String me) => cooperations
      .where((c) =>
          c.status == CooperationStatus.confirmed &&
          c.endRequest != null &&
          c.endRequest!.by != me &&
          c.endRequest!.dispute == null)
      .length;

  /// Whether the next step is mine to take now.
  bool needsMe(String me) =>
      pendingConfirm(me) > 0 ||
      endAsks(me) > 0 ||
      newQuotes > 0 ||
      cooperations.any((c) =>
          c.milestones.any((m) => m.status == MilestoneStatus.requested) ||
          c.workLogs.any((w) => !w.confirmed));

  /// The single most useful next step, in plain words.
  String nextStep(String me) {
    if (pendingConfirm(me) > 0)
      return tr3('有合作约定待你确认', 'Келісімді растаңыз', 'Подтвердите соглашение');
    if (endAsks(me) > 0)
      return tr3(
          '对方请求结束合作，等你确认', 'Аяқтауды растаңыз', 'Подтвердите завершение');
    final inspections = cooperations
        .expand((c) => c.milestones)
        .where((m) => m.status == MilestoneStatus.requested)
        .length;
    if (inspections > 0)
      return tr3('$inspections 个节点等你验收', 'Кезеңді қабылдаңыз',
          'Этапов к приёмке: $inspections');
    final days = cooperations
        .expand((c) => c.workLogs)
        .where((w) => !w.confirmed)
        .length;
    if (days > 0)
      return tr3('$days 天记工等你确认', '$days күн расталмады',
          'Дней к подтверждению: $days');
    if (newQuotes > 0)
      return tr3('$newQuotes 个新报价，去比较', '$newQuotes жаңа ұсыныс',
          'Новых предложений: $newQuotes');
    if (shareOnly)
      return comments == 0
          ? tr3('已分享，等大家点评', 'Пікір күтілуде', 'Ждём отзывов')
          : tr3('$comments 条点评，去看看', '$comments пікір', 'Отзывов: $comments');
    return switch (stage) {
      HouseStage.design => hasDesign
          ? tr3('设计好了就为它找人', 'Дайын болса, адам іздеңіз',
              'Когда проект готов, найдите мастеров')
          : tr3('补一张设计，报价会更准', 'Жоба қосыңыз', 'Добавьте проект'),
      HouseStage.finding => quoteCount == 0
          ? tr3('等师傅报名 / 报价', 'Өтінімдерді күтіңіз', 'Ждём откликов')
          : tr3('$quoteCount 个报名 / 报价', '$quoteCount өтінім',
              'Откликов: $quoteCount'),
      HouseStage.building =>
        tr3('施工中，记得验收节点', 'Құрылыс жүріп жатыр', 'Идёт стройка'),
      HouseStage.done => tr3('已完工，可以评价', 'Аяқталды', 'Готово, оставьте отзыв'),
    };
  }
}

/// Builds my houses from local designs and my demands. Designs without any
/// platform activity are left to the design list.
Future<List<MyHouse>> loadMyHouses(
    PlatformRepositories r, ProjectStore store) async {
  if (r.currentAccount == null) return const [];
  // Independent reads go out together instead of one after another.
  final postsF = _quiet(r.myPosts);
  final projectsF = store.listProjects();
  final demandsF = r.myDemands();
  final countsF = r.myQuoteCounts();
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
      snaps[sid] ??= _quiet(() => r.snapshot(sid, demandId: d.id));
    }
  }
  final coopsF = Future.wait([for (final d in demands) r.cooperationsFor(d.id)]);
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
          design == null ? await _quiet(() => r.postForDemand(d.id)) : null;
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
    final h = existing ??
        (byKey[p.projectId] = MyHouse(
            key: p.projectId,
            name: designs[p.projectId]?.document.meta.name ?? p.title,
            projectId: designs.containsKey(p.projectId) ? p.projectId : null,
            preview: designs[p.projectId]?.preview ?? p.preview,
            postId: p.id));
    h.comments = p.commentCount;
    h.sharedAt = p.updatedAt;
  }
  final coopLists = await coopsF;
  final coops = {
    for (var i = 0; i < demands.length; i++) demands[i].id: coopLists[i]
  };
  for (final h in byKey.values)
    for (final d in h.demands) h.cooperations.addAll(coops[d.id]!);
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
