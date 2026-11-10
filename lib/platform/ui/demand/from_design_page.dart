import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../../render2d/planning_names.dart';
import '../../../storage/project_store.dart';
import '../../domain/models.dart';
import '../../snapshot/design_snapshot.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'demand_detail_page.dart';
import 'publish_page.dart';

/// "Find builders" from a design: pick the whole house or stages, check the
/// quantities measured from the design, then continue in the publish
/// wizard with a frozen snapshot.
class FromDesignPage extends StatefulWidget {
  const FromDesignPage({super.key, required this.entry});
  final ProjectEntry entry;
  @override
  State<FromDesignPage> createState() => _FromDesignPageState();
}

class _FromDesignPageState extends State<FromDesignPage> {
  final stages = <String>{'walls'};
  final removed = <int>{};
  DesignExtract? extract;
  String? failure;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    try {
      extract = extractDesign(widget.entry.document, stages.toList(),
          nameOf: costLineName);
      failure = null;
    } catch (_) {
      extract = null;
      failure = tr3(
          '无法从这个设计提取工程量，可以在下一步手填。',
          'Көлемді алу мүмкін болмады, қолмен толтырыңыз.',
          'Не удалось посчитать объёмы — заполните вручную.');
    }
    removed.clear();
  }

  Future<void> next() async {
    final doc = widget.entry.document;
    final e = extract;
    final lines = [
      if (e != null)
        for (final (i, l) in e.lines.indexed)
          if (!removed.contains(i)) l
    ];
    String m(int mm) => (mm / 1000).toStringAsFixed(1);
    final summary = e == null
        ? doc.meta.name
        : tr3(
            '${m(e.width)} × ${m(e.depth)} 米 · ${e.floors} 层 · 建筑面积 ${e.buildingArea.toStringAsFixed(0)} ㎡',
            '${m(e.width)} × ${m(e.depth)} м · ${e.floors} қабат · ${e.buildingArea.toStringAsFixed(0)} м²',
            '${m(e.width)} × ${m(e.depth)} м · этажей: ${e.floors} · ${e.buildingArea.toStringAsFixed(0)} м²');
    final snapshot = buildSnapshot(
        projectId: widget.entry.id,
        doc: doc,
        stages: stages.toList(),
        lines: lines,
        summary: summary,
        preview: widget.entry.preview);
    if (!await requireLogin(context) || !mounted) return;
    await Navigator.of(context).pushReplacement(platformRoute((_) =>
        PublishPage(snapshot: snapshot, designProjectId: widget.entry.id)));
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    final e = extract;
    final all = stages.length == snapshotStages.length;
    return PageScaffold(
        title: tr3(
            '从设计找施工方', 'Жобадан мердігер іздеу', 'Найти подрядчика по проекту'),
        bottom: FilledButton(
            onPressed: stages.isEmpty ? null : next,
            child: Text(tr3('下一步：补充信息', 'Келесі', 'Далее'))),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.entry.document.meta.name,
              style:
                  const TextStyle(fontSize: YFont.display, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              tr3(
                  '设计版本：${widget.entry.document.meta.updatedAt.substring(0, 10)}',
                  'Жоба нұсқасы: ${widget.entry.document.meta.updatedAt.substring(0, 10)}',
                  'Версия проекта: ${widget.entry.document.meta.updatedAt.substring(0, 10)}'),
              style: TextStyle(color: t.muted)),
          SectionTitle(tr3('选择范围', 'Көлемді таңдау', 'Что поручить')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilterPill(
                label: tr3('整栋', 'Толық үй', 'Весь дом'),
                selected: all,
                onTap: () => setState(() {
                      stages
                        ..clear()
                        ..addAll(all ? const ['walls'] : snapshotStages);
                      refresh();
                    })),
            for (final s in snapshotStages)
              FilterPill(
                  label: stageLabel(s),
                  selected: stages.contains(s),
                  onTap: () => setState(() {
                        if (!stages.remove(s)) stages.add(s);
                        refresh();
                      })),
          ]),
          SectionTitle(tr3('确认工程量', 'Көлемді растау', 'Проверьте объёмы')),
          Text(
              tr3(
                  '来自设计的工程量按当前设计计算；标“手填”的是估算值。去掉不需要的行，下一步还可以手动增删。',
                  'Жобадан есептелді; қажетсізін алып тастаңыз.',
                  'Объёмы посчитаны по проекту; уберите лишнее, дальше можно дополнить.'),
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 10),
          if (failure != null) Hint(failure!, warn: true),
          if (e != null && e.lines.isEmpty)
            Hint(tr3(
                '这些阶段没有可提取的工程量，可以在下一步手填并注明来源。',
                'Көлем жоқ, қолмен толтырыңыз.',
                'Нет объёмов для этих этапов — заполните вручную.')),
          if (e != null)
            for (final (i, l) in e.lines.indexed)
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: !removed.contains(i),
                  onChanged: (v) => setState(
                      () => v == true ? removed.remove(i) : removed.add(i)),
                  title: Text(l.name),
                  subtitle: Text(
                      '${stageLabel(l.stage ?? '')} · ${qtySourceName(l.source)}'),
                  secondary: Text(
                      '${numText(l.quantity ?? 0)} ${unitLabel(l.unit)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: YText.tabular))),
          const SizedBox(height: 12),
          Hint(tr3(
              '发布后附件固定为此刻的设计版本。设计检查结果不代表具备施工或审批资格。',
              'Тіркеме осы нұсқада бекітіледі.',
              'Вложение фиксируется на текущей версии проекта.')),
          if (e != null && e.lines.isNotEmpty) ...[
            const SizedBox(height: 16),
            QtyTable([
              for (final (i, l) in e.lines.indexed)
                if (!removed.contains(i)) l
            ]),
          ],
        ]));
  }
}

/// Demands published from one local design.
class LinkedDemands extends StatelessWidget {
  const LinkedDemands({super.key, required this.projectId});
  final String projectId;
  @override
  Widget build(BuildContext context) => Live<List<Demand>>(
      load: (r) async => r.currentAccount == null
          ? const <Demand>[]
          : (await r.myDemands())
              .where((d) => d.designProjectId == projectId)
              .toList(),
      builder: (context, list) => Column(children: [
            for (final d in list)
              ListTile(
                  title: Text(d.current.title),
                  subtitle: Text(demandStatusName(d.status)),
                  onTap: () => pushPage<void>(
                      context, (_) => DemandDetailPage(demandId: d.id))),
          ]));
}
