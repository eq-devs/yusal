import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Edits the inspection points of an agreement that is still waiting for
/// confirmation: name, share of the amount, what is checked and when.
/// Saving asks the other side to confirm again.
class MilestoneEditorPage extends StatefulWidget {
  const MilestoneEditorPage({super.key, required this.cooperation});
  final Cooperation cooperation;
  @override
  State<MilestoneEditorPage> createState() => _MilestoneEditorPageState();
}

class _Row {
  _Row(Milestone m)
      : key = m.key,
        name = TextEditingController(
            text: m.key.startsWith('c:')
                ? m.key.substring(2)
                : milestoneName(m.key)),
        percent = TextEditingController(text: '${m.percent}'),
        criteria = TextEditingController(
            text: m.criteria.isEmpty ? milestoneCriteria(m.key) : m.criteria),
        due = m.due;
  String key;
  final TextEditingController name, percent, criteria;
  DateTime? due;
  void dispose() {
    name.dispose();
    percent.dispose();
    criteria.dispose();
  }

  /// Built-in keys keep their translation unless the name was changed.
  Milestone toMilestone() {
    final n = name.text.trim();
    final k = !key.startsWith('c:') && n == milestoneName(key) ? key : 'c:$n';
    final c = criteria.text.trim();
    return Milestone(
        key: k,
        percent: int.tryParse(percent.text.trim()) ?? -1,
        criteria: !k.startsWith('c:') && c == milestoneCriteria(k) ? '' : c,
        due: due);
  }
}

class _MilestoneEditorPageState extends State<MilestoneEditorPage> {
  late final rows = [
    for (final m in widget.cooperation.milestones.isEmpty
        ? defaultMilestones
        : widget.cooperation.milestones)
      _Row(m)
  ];

  @override
  void dispose() {
    for (final r in rows) r.dispose();
    super.dispose();
  }

  int get total =>
      rows.fold(0, (s, r) => s + (int.tryParse(r.percent.text.trim()) ?? 0));

  Future<void> save() async {
    final plan = [for (final r in rows) r.toMilestone()];
    if (plan.any((m) => m.key == 'c:')) {
      toast(
          context,
          tr3('每个节点都要有名字', 'Әр кезеңнің атауы болсын',
              'У каждого этапа должно быть название'));
      return;
    }
    if (total != 100) {
      toast(
          context,
          tr3('比例加起来要等于 100%', 'Барлығы 100% болуы керек',
              'Сумма долей должна быть 100%'));
      return;
    }
    final ok = await attempt(
        context, () => context.repos.setMilestones(widget.cooperation.id, plan),
        success: tr3('已保存，等对方确认', 'Сақталды, екінші жақ растайды',
            'Сохранено, ждём подтверждения'));
    if (ok != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final amount = widget.cooperation.agreement.amount;
    return PageScaffold(
        title: tr3('验收节点', 'Қабылдау кезеңдері', 'Этапы приёмки'),
        bottom: Row(children: [
          Expanded(
              child: Text(tr3('合计 $total%', 'Барлығы $total%', 'Итого $total%'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: total == 100 ? t.ok : t.warn))),
          FilledButton(
              key: const Key('milestones-save'),
              onPressed: save,
              child: Text(tr3('保存并请对方确认', 'Сақтау', 'Сохранить'))),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Hint(tr3(
              '按施工节点分阶段验收。改完后双方都要重新确认约定。Yusal 只记录验收，不代收代付。',
              'Кезеңдерді өзгерткен соң екі жақ қайта растайды.',
              'После изменений обе стороны подтверждают заново. Yusal не принимает платежи.')),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++)
            Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: TextField(
                                key: Key('ms-name-$i'),
                                controller: rows[i].name,
                                decoration: InputDecoration(
                                    labelText: tr3('节点', 'Кезең', 'Этап')))),
                        const SizedBox(width: 10),
                        SizedBox(
                            width: 84,
                            child: TextField(
                                key: Key('ms-percent-$i'),
                                controller: rows[i].percent,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                    labelText: '%', suffixText: '%'))),
                        IconButton(
                            tooltip: tr3('删除', 'Жою', 'Удалить'),
                            onPressed: rows.length <= 1
                                ? null
                                : () =>
                                    setState(() => rows.removeAt(i).dispose()),
                            icon: const Icon(Icons.delete_outline)),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                          controller: rows[i].criteria,
                          maxLines: 2,
                          decoration: InputDecoration(
                              labelText: tr3(
                                  '验收标准', 'Қабылдау талабы', 'Что проверяем'))),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (amount != null)
                          Expanded(
                              child: Text(
                                  money(amount *
                                      (int.tryParse(rows[i].percent.text) ??
                                          0) ~/
                                      100),
                                  style: TextStyle(color: t.muted))),
                        TextButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                  context: context,
                                  initialDate: rows[i].due ?? context.now,
                                  firstDate: context.now
                                      .subtract(const Duration(days: 365)),
                                  lastDate: context.now
                                      .add(const Duration(days: 365 * 3)));
                              if (d != null) setState(() => rows[i].due = d);
                            },
                            icon: const Icon(Icons.event_outlined, size: 18),
                            label: Text(rows[i].due == null
                                ? tr3('预计日期', 'Мерзім', 'Срок')
                                : fmtDay(rows[i].due))),
                      ]),
                    ]))),
          if (rows.length < 8)
            OutlinedButton.icon(
                key: const Key('ms-add'),
                onPressed: () => setState(() => rows.add(_Row(Milestone(
                    key:
                        'c:${tr3('新节点', 'Жаңа кезең', 'Новый этап')} ${rows.length + 1}',
                    percent: 0)))),
                icon: const Icon(Icons.add),
                label: Text(tr3('加一个节点', 'Кезең қосу', 'Добавить этап'))),
        ]));
  }
}
