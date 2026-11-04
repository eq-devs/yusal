import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'my_houses_data.dart';

/// The building-site tab of a house: each confirmed cooperation with its
/// inspection points and daily work log.
class SiteTab extends StatelessWidget {
  const SiteTab({super.key, required this.house});
  final MyHouse house;
  @override
  Widget build(BuildContext context) {
    final active = house.cooperations
        .where((c) =>
            c.status == CooperationStatus.confirmed ||
            c.status == CooperationStatus.ended)
        .toList();
    if (active.isEmpty)
      return EmptyState(
          icon: Icons.foundation_outlined,
          title: tr3('还没开工', 'Құрылыс басталмады', 'Стройка не начата'),
          body: tr3(
              '合作确认后，节点验收和每天的记工会出现在这里。',
              'Келісімнен кейін осында болады.',
              'После соглашения здесь будут этапы и рабочие дни.'));
    String title(String demandId) =>
        house.demands
            .where((d) => d.id == demandId)
            .firstOrNull
            ?.current
            .title ??
        '';
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          for (final c in active) ...[
            Text(title(c.demandId),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            SiteSection(cooperation: c),
            const SizedBox(height: 28),
          ],
        ]);
  }
}

/// Milestones and work log of one cooperation, with the actions of whoever
/// is looking: the pro logs a day and asks for inspection, the owner
/// confirms days and accepts or questions a milestone.
class SiteSection extends StatelessWidget {
  const SiteSection({super.key, required this.cooperation});
  final Cooperation cooperation;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = cooperation;
    final me = context.repos.currentAccount?.id;
    final owner = me == c.ownerId, pro = me == c.providerId;
    final live = c.status == CooperationStatus.confirmed;
    final amount = c.agreement.amount;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.milestones.isNotEmpty) ...[
        Text(
            amount == null
                ? tr3(
                    '已验收 ${c.acceptedPercent}%',
                    '${c.acceptedPercent}% қабылданды',
                    'Принято ${c.acceptedPercent}%')
                : tr3(
                    '已验收 ${money(amount * c.acceptedPercent ~/ 100)} / 约定 ${money(amount)}',
                    '${money(amount * c.acceptedPercent ~/ 100)} / ${money(amount)}',
                    'Принято ${money(amount * c.acceptedPercent ~/ 100)} из ${money(amount)}'),
            style: TextStyle(color: t.muted)),
        const SizedBox(height: 8),
        for (var i = 0; i < c.milestones.length; i++)
          _MilestoneTile(
              key: Key('milestone-$i'),
              milestone: c.milestones[i],
              amount: amount,
              onRequest: pro &&
                      live &&
                      c.milestones[i].status != MilestoneStatus.accepted &&
                      c.milestones[i].status != MilestoneStatus.requested
                  ? () => _request(context, i)
                  : null,
              onAccept: owner &&
                      c.milestones[i].status == MilestoneStatus.requested
                  ? () => attempt(context,
                      () => context.repos.answerMilestone(c.id, i, true),
                      success: tr3('已记录验收', 'Қабылданды', 'Приёмка записана'))
                  : null,
              onDispute:
                  owner && c.milestones[i].status == MilestoneStatus.requested
                      ? () => _dispute(context, i)
                      : null),
        Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
                tr3(
                    'Yusal 目前只记录验收，不代收代付。',
                    'Yusal тек қабылдауды жазады, ақша ұстамайды.',
                    'Yusal только записывает приёмку и не принимает платежи.'),
                style: TextStyle(color: t.faint, fontSize: 12))),
      ],
      Row(children: [
        Expanded(
            child: Text(tr3('施工日志', 'Жұмыс күнделігі', 'Журнал работ'),
                style: const TextStyle(fontWeight: FontWeight.w700))),
        if (pro && live)
          FilledButton.tonalIcon(
              key: const Key('log-work'),
              onPressed: () => logToday(context, c),
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text(tr3('今天记工', 'Бүгінді жазу', 'Отметить день'))),
      ]),
      const SizedBox(height: 6),
      if (c.workLogs.isEmpty)
        Text(tr3('还没有记工。', 'Әлі жазба жоқ.', 'Записей пока нет.'),
            style: TextStyle(color: t.muted)),
      for (final w in c.workLogs)
        ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
                w.confirmed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: w.confirmed ? t.ok : t.faint),
            title: Text(
                '${fmtDay(w.day)} · ${tr3('到场 ${w.headcount} 人', '${w.headcount} адам', '${w.headcount} чел.')}${w.photoCount > 0 ? ' · 📷${w.photoCount}' : ''}'),
            subtitle: w.note.isEmpty ? null : Text(w.note),
            trailing: owner && !w.confirmed
                ? TextButton(
                    onPressed: () => attempt(
                        context, () => context.repos.confirmWork(c.id, w.id)),
                    child: Text(tr3('确认', 'Растау', 'Подтвердить')))
                : null),
    ]);
  }

  Future<void> _request(BuildContext context, int i) async {
    final note = await askText(
        context,
        tr3('申请「${milestoneName(cooperation.milestones[i].key)}」验收',
            'Қабылдауды сұрау', 'Попросить принять этап'),
        hint: tr3('做了什么、照片在哪里（可选）', 'Не істелді', 'Что сделано'),
        required: false);
    if (note == null || !context.mounted) return;
    await attempt(context,
        () => context.repos.requestMilestone(cooperation.id, i, note: note),
        success: tr3('已通知房主来验收', 'Иесіне хабарланды', 'Владелец уведомлён'));
  }

  Future<void> _dispute(BuildContext context, int i) async {
    final note = await askText(
        context, tr3('哪里有问题？', 'Қандай ескерту?', 'Какие замечания?'));
    if (note == null || !context.mounted) return;
    await attempt(
        context,
        () => context.repos
            .answerMilestone(cooperation.id, i, false, note: note));
  }
}

/// "今天记工": crew on site today, with an optional note.
Future<void> logToday(BuildContext context, Cooperation c) async {
  final last = c.workLogs.firstOrNull?.headcount ?? 1;
  final text = await askText(
      context, tr3('今天到场几人？', 'Бүгін неше адам?', 'Сколько человек сегодня?'),
      initial: "$last", lines: 1);
  final n = int.tryParse(text?.trim() ?? '');
  if (n == null || !context.mounted) return;
  await attempt(context, () => context.repos.logWork(c.id, n),
      success: tr3('已记工，房主会收到确认提醒', 'Жазылды', 'Записано'));
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile(
      {super.key,
      required this.milestone,
      required this.amount,
      this.onRequest,
      this.onAccept,
      this.onDispute});
  final Milestone milestone;
  final int? amount;
  final VoidCallback? onRequest, onAccept, onDispute;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final m = milestone;
    final color = switch (m.status) {
      MilestoneStatus.accepted => t.ok,
      MilestoneStatus.requested => t.accent,
      MilestoneStatus.disputed => t.warn,
      MilestoneStatus.planned => t.faint,
    };
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(yRadius),
            border: Border(left: BorderSide(color: color, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(milestoneName(m.key),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    amount == null
                        ? '${m.percent}%'
                        : '${m.percent}% · ${money(amount! * m.percent ~/ 100)}',
                    style: TextStyle(color: t.muted)),
                StatusPill(milestoneStatusName(m.status), color: color),
              ]),
          const SizedBox(height: 2),
          Text(m.criteria.isEmpty ? milestoneCriteria(m.key) : m.criteria,
              style: TextStyle(color: t.muted, fontSize: 13)),
          if (m.note.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.note, style: const TextStyle(fontSize: 13))),
          if (onRequest != null || onAccept != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (onRequest != null)
                    OutlinedButton(
                        onPressed: onRequest,
                        child: Text(tr3(
                            '申请验收', 'Қабылдауды сұрау', 'Попросить приёмку'))),
                  if (onAccept != null)
                    FilledButton(
                        onPressed: onAccept,
                        child: Text(tr3('确认验收', 'Қабылдау', 'Принять этап'))),
                  if (onDispute != null)
                    OutlinedButton(
                        onPressed: onDispute,
                        child: Text(tr3('有问题', 'Ескерту', 'Замечания'))),
                ])),
        ]));
  }
}
