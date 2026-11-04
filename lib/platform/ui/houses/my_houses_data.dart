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
      List<Demand>? demands})
      : demands = demands ?? [];
  final String key, name;
  final String? projectId;
  final List<int>? preview;
  final List<Demand> demands;
  final cooperations = <Cooperation>[];
  final quotes = <String, ({int total, int unread})>{};

  bool get hasDesign => projectId != null;
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

  /// The single most useful next step, in plain words.
  String nextStep(String me) {
    if (pendingConfirm(me) > 0)
      return tr3('有合作约定待你确认', 'Келісімді растаңыз', 'Подтвердите соглашение');
    if (newQuotes > 0)
      return tr3('$newQuotes 个新报价，去比较', '$newQuotes жаңа ұсыныс',
          'Новых предложений: $newQuotes');
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
  final designs = {for (final e in await store.listProjects()) e.id: e};
  final demands = (await r.myDemands())
      .where((d) =>
          d.status != DemandStatus.draft && d.status != DemandStatus.rejected)
      .toList();
  final counts = await r.myQuoteCounts();
  final byKey = <String, MyHouse>{};
  for (final d in demands) {
    final pid = d.designProjectId;
    final design = pid == null ? null : designs[pid];
    final key = pid ?? 'demand:${d.id}';
    final h = byKey.putIfAbsent(
        key,
        () => MyHouse(
            key: key,
            name: design?.document.meta.name ?? d.current.title,
            projectId: pid,
            preview: design?.preview));
    h.demands.add(d);
    final c = counts[d.id];
    if (c != null) h.quotes[d.id] = c;
  }
  for (final h in byKey.values)
    for (final d in h.demands)
      h.cooperations.addAll(await r.cooperationsFor(d.id));
  final list = byKey.values.toList()
    ..sort((a, b) => _latest(b).compareTo(_latest(a)));
  return list;
}

DateTime _latest(MyHouse h) => h.demands
    .map((d) => d.current.createdAt)
    .fold(DateTime(2000), (a, b) => a.isAfter(b) ? a : b);
