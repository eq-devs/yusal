import 'package:flutter/material.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/houses/model/my_house.dart';
import 'package:yusal/features/shared/ui/photos.dart';
import 'package:yusal/features/shared/motion/motion.dart';

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
    if (active.isEmpty) {
      return EmptyState(
          icon: Icons.foundation_outlined,
          title: tr3('还没开工', 'Құрылыс басталмады', 'Стройка не начата', "Construction hasn't started"),
          body: tr3(
              '合作确认后，节点验收和每天的记工会出现在这里。',
              'Келісімнен кейін осында болады.',
              'После соглашения здесь будут этапы и рабочие дни.',
              'After the agreement, stages and work days show here.'));
    }
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
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: YFont.body)),
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
    final me = context.session.currentAccount?.id;
    final owner = me == c.ownerId;
    final pro = me == c.providerId;
    final live = c.status == CooperationStatus.confirmed;
    final amount = c.agreement.amount;
    // Inspections go in order: only the first open point can be requested.
    final current =
        c.milestones.indexWhere((m) => m.status != MilestoneStatus.accepted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.milestones.isNotEmpty) ...[
        Text(
            amount == null
                ? tr3(
                    '已验收 ${c.acceptedPercent}%',
                    '${c.acceptedPercent}% қабылданды',
                    'Принято ${c.acceptedPercent}%',
                    '${c.acceptedPercent}% accepted')
                : tr3(
                    '已验收 ${money(amount * c.acceptedPercent ~/ 100)} / 约定 ${money(amount)}',
                    '${money(amount * c.acceptedPercent ~/ 100)} / ${money(amount)}',
                    'Принято ${money(amount * c.acceptedPercent ~/ 100)} из ${money(amount)}',
                    'Accepted ${money(amount * c.acceptedPercent ~/ 100)} of ${money(amount)}'),
            style: TextStyle(color: t.muted)),
        const SizedBox(height: 8),
        for (var i = 0; i < c.milestones.length; i++)
          _MilestoneTile(
              key: Key('milestone-$i'),
              milestone: c.milestones[i],
              amount: amount,
              current: live && i == current,
              // The same moves voice is offered.
              onRequest:
                  milestoneMoves(c, me, i).contains(MilestoneEvent.request)
                      ? () => _request(context, i)
                      : null,
              onAccept: milestoneMoves(c, me, i).contains(MilestoneEvent.accept)
                  ? () => attempt(
                      context,
                      () => context
                          .read(cooperationRepositoryProvider)
                          .answerMilestone(c.id, i, true),
                      success: tr3('已记录验收', 'Қабылданды', 'Приёмка записана', 'Acceptance recorded'))
                  : null,
              onDispute:
                  milestoneMoves(c, me, i).contains(MilestoneEvent.dispute)
                      ? () => _dispute(context, i)
                      : null),
        Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
                tr3(
                    'Yusal 目前只记录验收，不代收代付。',
                    'Yusal тек қабылдауды жазады, ақша ұстамайды.',
                    'Yusal только записывает приёмку и не принимает платежи.',
                    "Yusal only records acceptance and doesn't take payments."),
                style: TextStyle(color: t.muted, fontSize: YFont.caption))),
      ],
      Row(children: [
        Expanded(
            child: Text(tr3('施工日志', 'Жұмыс күнделігі', 'Журнал работ', 'Work log'),
                style: const TextStyle(fontWeight: FontWeight.w700))),
        if (pro && live)
          FilledButton.tonalIcon(
              key: const Key('log-work'),
              onPressed: onLogToday(context, c),
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text(logTodayLabel(c))),
      ]),
      const SizedBox(height: 6),
      if (c.workLogs.isEmpty)
        Text(tr3('还没有记工。', 'Әлі жазба жоқ.', 'Записей пока нет.', 'No entries yet.'),
            style: TextStyle(color: t.muted)),
      for (final w in c.workLogs)
        ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
                w.confirmed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: w.confirmed ? t.ok : t.faint),
            title: Text(
                '${fmtDay(w.day)} · ${tr3('到场 ${w.headcount} 人', '${w.headcount} адам', '${w.headcount} чел.', '${w.headcount} people')}${w.photoCount > 0 ? ' · 📷${w.photoCount}' : ''}'),
            subtitle: w.note.isEmpty && w.photos.isEmpty
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        if (w.note.isNotEmpty) Text(w.note),
                        if (w.photos.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: PhotoStrip(photos: w.photos, size: 52)),
                      ]),
            trailing: owner && !w.confirmed
                ? TextButton(
                    onPressed: () => attempt(
                        context,
                        () => context
                            .read(cooperationRepositoryProvider)
                            .confirmWork(c.id, w.id)),
                    child: Text(tr3('确认', 'Растау', 'Подтвердить', 'Confirm')))
                : null),
    ]);
  }

  Future<void> _request(BuildContext context, int i) async {
    final r = await composeSiteEntry(context,
        title: tr3('申请「${milestoneName(cooperation.milestones[i].key)}」验收',
            'Қабылдауды сұрау', 'Попросить принять этап', 'Ask to accept the stage'),
        hint: tr3('做了什么，按验收标准拍几张照片', 'Не істелді, фото қосыңыз',
            'Что сделано; добавьте фото по критериям',
            "What's done; add photos for the criteria"));
    if (r == null || !context.mounted) return;
    await attempt(
        context,
        () => context.read(cooperationRepositoryProvider).requestMilestone(
            cooperation.id, i,
            note: r.note, photos: r.photos),
        success: tr3('已通知房主来验收', 'Иесіне хабарланды', 'Владелец уведомлён', 'The owner was notified'));
  }

  Future<void> _dispute(BuildContext context, int i) async {
    final note = await askText(
        context, tr3('哪里有问题？', 'Қандай ескерту?', 'Какие замечания?', 'What are the issues?'));
    if (note == null || !context.mounted) return;
    await attempt(
        context,
        () => context
            .read(cooperationRepositoryProvider)
            .answerMilestone(cooperation.id, i, false, note: note));
  }
}

/// Today's work log, by the Kazakhstan calendar day (UTC+5) the server uses.
WorkLog? todayLog(Cooperation c) {
  final kz = DateTime.now().toUtc().add(const Duration(hours: 5));
  return c.workLogs.where((w) {
    final d = w.day.toUtc();
    return d.year == kz.year && d.month == kz.month && d.day == kz.day;
  }).firstOrNull;
}

/// The "log today" button's label: log, edit today's, or already confirmed.
String logTodayLabel(Cooperation c) => switch (todayLog(c)) {
      null => tr3('今天记工', 'Бүгінді жазу', 'Отметить день', 'Log a day'),
      WorkLog(confirmed: true) =>
        tr3('今天已确认', 'Бүгін расталды', 'Сегодня подтверждено', 'Today is confirmed'),
      _ => tr3('修改今天记工', 'Бүгінгіні түзету', 'Изменить сегодня', 'Edit today'),
    };

/// Null (disabled) once the owner confirmed today's log: it is locked.
VoidCallback? onLogToday(BuildContext context, Cooperation c) =>
    todayLog(c)?.confirmed == true ? null : () => logToday(context, c);

/// "今天记工": crew on site today, with photos and an optional note. A second
/// log the same day replaces today's unconfirmed one.
Future<void> logToday(BuildContext context, Cooperation c) async {
  final r = await composeSiteEntry(context,
      title: tr3('今天记工', 'Бүгінгі жұмыс', 'Рабочий день', 'Work day'),
      hint: tr3('今天干了什么（可以用键盘上的麦克风说）', 'Бүгін не істелді',
          'Что сделано сегодня (можно надиктовать)',
          'What was done today (you can dictate)'),
      headcount: c.workLogs.firstOrNull?.headcount ??
          (c.agreement.headcount ?? 0).clamp(1, 99));
  if (r == null || !context.mounted) return;
  await attempt(
      context,
      () => context
          .read(cooperationRepositoryProvider)
          .logWork(c.id, r.headcount!, note: r.note, photos: r.photos),
      success: tr3('已记工，房主会收到确认提醒', 'Жазылды', 'Записано', 'Recorded'));
}

typedef SiteEntry = ({String note, List<List<int>> photos, int? headcount});

/// Bottom sheet for a site entry: optional crew count, note and photos.
Future<SiteEntry?> composeSiteEntry(BuildContext context,
        {required String title, required String hint, int? headcount}) =>
    showMotionSheet<SiteEntry>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => PlatformTheme(
            child: _SiteEntrySheet(
                title: title, hint: hint, headcount: headcount)));

class _SiteEntrySheet extends StatefulWidget {
  const _SiteEntrySheet(
      {required this.title, required this.hint, this.headcount});
  final String title;
  final String hint;
  final int? headcount;
  @override
  State<_SiteEntrySheet> createState() => _SiteEntrySheetState();
}

class _SiteEntrySheetState extends State<_SiteEntrySheet> {
  late int? people = widget.headcount;
  final note = TextEditingController();
  final photos = <List<int>>[];
  bool picking = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> addPhotos() async {
    setState(() => picking = true);
    final more = await pickPhotos(context, max: maxSitePhotos - photos.length);
    if (!mounted) return;
    setState(() {
      photos.addAll(more);
      picking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text(widget.title, style: display(size: 20)),
              if (people != null) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: Text(
                          tr3('今天到场', 'Бүгін келді', 'Сегодня на объекте', 'On site today'),
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  IconButton.outlined(
                      key: const Key('people-minus'),
                      onPressed: people! > 1
                          ? () => setState(() => people = people! - 1)
                          : null,
                      icon: const Icon(Icons.remove)),
                  SizedBox(
                      width: 56,
                      child: Text(
                          tr3('$people 人', '$people адам', '$people чел.', '$people people'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: YFont.body))),
                  IconButton.outlined(
                      key: const Key('people-plus'),
                      onPressed: people! < 200
                          ? () => setState(() => people = people! + 1)
                          : null,
                      icon: const Icon(Icons.add)),
                ]),
              ],
              const SizedBox(height: 14),
              TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: widget.hint)),
              const SizedBox(height: 12),
              PhotoStrip(
                  photos: photos,
                  onRemove: (i) => setState(() => photos.removeAt(i))),
              if (photos.isNotEmpty) const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                    onPressed: picking || photos.length >= maxSitePhotos
                        ? null
                        : addPhotos,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(tr3(
                        '加照片 ${photos.length}/$maxSitePhotos',
                        'Фото ${photos.length}/$maxSitePhotos',
                        'Фото ${photos.length}/$maxSitePhotos',
                        'Photos ${photos.length}/$maxSitePhotos'))),
                const Spacer(),
                FilledButton(
                    key: const Key('site-entry-submit'),
                    onPressed: () => Navigator.pop(context, (
                          note: note.text.trim(),
                          photos: List<List<int>>.of(photos),
                          headcount: people
                        )),
                    child: Text(tr3('提交', 'Жіберу', 'Отправить', 'Send'))),
              ]),
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      tr3('照片只给合作双方看。', 'Фотоны тек екі жақ көреді.',
                          'Фото видят только стороны соглашения.',
                          'Only the sides of the agreement see the photos.'),
                      style:
                          TextStyle(color: t.muted, fontSize: YFont.caption))),
            ])));
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile(
      {super.key,
      required this.milestone,
      required this.amount,
      this.current = false,
      this.onRequest,
      this.onAccept,
      this.onDispute});
  final Milestone milestone;
  final int? amount;

  /// The point the crew is working towards now.
  final bool current;
  final VoidCallback? onRequest;
  final VoidCallback? onAccept;
  final VoidCallback? onDispute;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final m = milestone;
    final color = switch (m.status) {
      MilestoneStatus.accepted => t.ok,
      MilestoneStatus.requested => t.accent,
      MilestoneStatus.disputed => t.warn,
      MilestoneStatus.planned => current ? t.accent : t.faint,
    };
    final label = current && m.status == MilestoneStatus.planned
        ? tr3('进行中', 'Жүріп жатыр', 'В работе', 'In progress')
        : milestoneStatusName(m.status);
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
                StatusPill(label, color: color),
              ]),
          const SizedBox(height: 2),
          Text(m.criteria.isEmpty ? milestoneCriteria(m.key) : m.criteria,
              style: TextStyle(color: t.muted, fontSize: YFont.small)),
          if (m.note.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.note,
                    style: const TextStyle(fontSize: YFont.small))),
          if (m.photos.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: PhotoStrip(photos: m.photos, size: 52)),
          if (m.due != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    tr3('预计 ${fmtDay(m.due)}', 'Мерзімі ${fmtDay(m.due)}',
                        'Срок ${fmtDay(m.due)}',
                        'Due ${fmtDay(m.due)}'),
                    style: TextStyle(color: t.muted, fontSize: YFont.caption))),
          if (onRequest != null || onAccept != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (onRequest != null)
                    OutlinedButton(
                        onPressed: onRequest,
                        child: Text(tr3(
                            '申请验收', 'Қабылдауды сұрау', 'Попросить приёмку', 'Ask for acceptance'))),
                  if (onAccept != null)
                    FilledButton(
                        onPressed: onAccept,
                        child: Text(tr3('确认验收', 'Қабылдау', 'Принять этап', 'Accept the stage'))),
                  if (onDispute != null)
                    OutlinedButton(
                        onPressed: onDispute,
                        child: Text(tr3('有问题', 'Ескерту', 'Замечания', 'Issues'))),
                ])),
        ]));
  }
}
