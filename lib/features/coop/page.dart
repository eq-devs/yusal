import 'package:flutter/material.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/coop/state/cooperation.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';
import 'package:yusal/features/chat/page.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/houses/widgets/site_tab.dart';
import 'package:yusal/features/coop/pages/milestone_editor.dart';
import 'package:yusal/features/coop/widgets/agreement_form.dart';
import 'package:yusal/features/coop/pages/review.dart';
import 'package:yusal/features/voice/actions/coop.dart';
import 'package:yusal/features/voice/state/screen.dart';

/// Cooperation detail: agreement and its versions, two-sided confirmation,
/// changes, progress notes, ending and optional reviews.
class CooperationPage extends StatelessWidget {
  const CooperationPage({super.key, required this.cooperationId});
  final String cooperationId;

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Live<CoopData>(
        provider: coopDataProvider(cooperationId),
        loading: const SkeletonPage(avatar: true),
        builder: (context, data) => data.coop == null
            ? PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.lock_outline,
                    title: tr3('无权查看或合作不存在', 'Қолжетімсіз', 'Нет доступа', 'No access')))
            : _CoopView(data: data));
  }
}

class _CoopView extends StatefulWidget {
  const _CoopView({required this.data});
  final CoopData data;

  @override
  State<_CoopView> createState() => _CoopViewState();
}

class _CoopViewState extends State<_CoopView>
    with VoiceScreen
    implements CoopHost {
  CoopData get data => widget.data;

  @override
  String get screenId => 'coop.detail';

  @override
  Cooperation get coop => data.coop!;

  /// Where it stands, so the assistant can say it; what can be done is
  /// the offered coop.* actions.
  @override
  String get summary =>
      'cooperation ${coop.status.name}, ending ${coop.endPhase.name}'
      '${coop.pendingChange != null ? ', change proposed' : ''}'
      '${_milestoneNote()}: '
      '${data.demand?.current.title ?? ''}';

  /// The inspection point voice acts on, and where it stands.
  String _milestoneNote() {
    final i = currentMilestone(coop);
    if (i == null) return '';
    final m = coop.milestones[i];
    return ', milestone ${m.key} ${m.status.name}';
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = data.coop!;
    final me = context.session.currentAccount?.id ?? '';
    final iAmOwner = me == c.ownerId;
    final g = c.agreement;
    final change = c.pendingChange;
    final title = data.demand?.current.title ?? '';
    final ownerName = deletedName(data.owner);
    final providerName = data.profile?.name ?? deletedName(data.provider);
    String nameOf(String id) => id == c.ownerId ? ownerName : providerName;
    final myReview = data.reviews.where((r) => r.authorId == me).firstOrNull;
    final otherReview = data.reviews.where((r) => r.authorId != me).firstOrNull;

    Future<void> run(Future<Object?> Function() f, String done) =>
        attempt(context, f, success: done);
    // The same moves voice is offered.
    final moves = coopMoves(c, me);

    final actions = <Widget>[];
    if (c.status == CooperationStatus.pending) {
      if (moves.contains(CoopMove.confirm)) {
        actions.addAll([
          BusyButton(
              label: tr3('确认合作', 'Келісімді растау', 'Подтвердить', 'Confirm'),
              onPressed: () => run(
                  () =>
                      context.read(cooperationRepositoryProvider).confirm(c.id),
                  tr3('合作已双方确认', 'Келісім расталды',
                      'Сотрудничество подтверждено',
                      'Cooperation confirmed'))),
          const SizedBox(height: 8),
          BusyButton(
              outlined: true,
              label: tr3('拒绝', 'Бас тарту', 'Отказаться', 'Decline'),
              onPressed: () => run(
                  () =>
                      context.read(cooperationRepositoryProvider).decline(c.id),
                  tr3('已拒绝，合作未成立', 'Бас тартылды', 'Отказ отправлен', 'Declined'))),
        ]);
      } else {
        actions.addAll([
          Hint(tr3(
              '已确认我方，等待对方确认。对方未确认前不算合作成立。',
              'Сіз растадыңыз, екінші жақты күтеміз.',
              'Вы подтвердили, ждём вторую сторону.',
              'You confirmed; waiting for the other side.')),
          const SizedBox(height: 8),
          BusyButton(
              outlined: true,
              label: tr3('撤回邀请', 'Шақыруды қайтару', 'Отозвать приглашение', 'Withdraw the invitation'),
              onPressed: () => run(
                  () =>
                      context.read(cooperationRepositoryProvider).revoke(c.id),
                  tr3('已撤回', 'Қайтарылды', 'Отозвано', 'Withdrawn'))),
        ]);
      }
    } else if (c.status == CooperationStatus.confirmed) {
      final r = c.endRequest;
      if (moves.contains(CoopMove.confirmEnd)) {
        actions.addAll([
          Hint(
              tr3(
                  '${nameOf(r!.by)} 请求结束合作${r.note.isEmpty ? '' : '：${r.note}'}',
                  '${nameOf(r.by)} аяқтауды сұрады',
                  '${nameOf(r.by)} просит завершить',
                  '${nameOf(r.by)} asks to finish'),
              warn: true),
          if (c.milestones
              .any((m) => m.status != MilestoneStatus.accepted)) ...[
            const SizedBox(height: 8),
            Hint(tr3(
                '还有 ${c.milestones.where((m) => m.status != MilestoneStatus.accepted).length} 个验收节点没确认（已验收 ${c.acceptedPercent}%）。确认结束后记录会定格在这里，先看看施工页再决定。',
                'Қабылданбаған кезеңдер бар (${c.acceptedPercent}%).',
                'Есть непринятые этапы (принято ${c.acceptedPercent}%).',
                "Some stages aren't accepted (${c.acceptedPercent}% accepted).")),
          ],
          const SizedBox(height: 8),
          BusyButton(
              label: tr3('确认结束', 'Аяқтауды растау', 'Подтвердить завершение', 'Confirm completion'),
              onPressed: () => run(
                  () => context
                      .read(cooperationRepositoryProvider)
                      .confirmEnd(c.id),
                  tr3('合作已结束', 'Аяқталды', 'Завершено', 'Finished'))),
          const SizedBox(height: 8),
          // Not a BusyButton: it would spin behind the dialog while the
          // reason is being typed.
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: () async {
                    final note = await askText(
                        context, tr3('异议说明', 'Қарсылық', 'Причина', 'Reason'));
                    if (note != null && context.mounted) {
                      await run(
                          () => context
                              .read(cooperationRepositoryProvider)
                              .disputeEnd(c.id, note),
                          tr3('已提交异议', 'Жіберілді', 'Отправлено', 'Sent'));
                    }
                  },
                  child: Text(tr3('提出异议', 'Қарсылық', 'Оспорить', 'Dispute')))),
        ]);
      } else if (c.endPhase == EndPhase.asked) {
        actions.add(Hint(tr3(
            '已请求结束，等待对方确认。对方 7 天未回应将记为“单方报告结束”，不显示为双方验收。',
            'Аяқтау сұралды. 7 күн жауап болмаса, бір жақты аяқталды деп белгіленеді.',
            'Запрос отправлен. Без ответа 7 дней — «завершено одной стороной».',
            'Request sent. With no reply in 7 days it becomes “finished by one side”.')));
      } else {
        if (c.endPhase == EndPhase.disputed) {
          actions.addAll([
            Hint(
                tr3('结束有异议：${r!.dispute}', 'Қарсылық: ${r.dispute}',
                    'Спор: ${r.dispute}',
                    'Dispute: ${r.dispute}'),
                warn: true),
            const SizedBox(height: 8),
          ]);
        }
        if (change != null) {
          actions.addAll([
            _AgreementCard(
                agreement: change,
                nameOf: nameOf,
                previous: g,
                title: tr3(
                    '变更提案（第 ${change.version} 版）',
                    'Өзгеріс (${change.version})',
                    'Изменение (версия ${change.version})',
                    'Change (version ${change.version})')),
            const SizedBox(height: 8),
            if (moves.contains(CoopMove.answerChange)) ...[
              BusyButton(
                  label: tr3('接受变更', 'Қабылдау', 'Принять', 'Accept'),
                  onPressed: () => run(
                      () => context
                          .read(cooperationRepositoryProvider)
                          .answerChange(c.id, true),
                      tr3('新约定已生效', 'Күшіне енді', 'Действует новая версия', 'The new version is in effect'))),
              const SizedBox(height: 8),
              BusyButton(
                  outlined: true,
                  label: tr3('拒绝变更', 'Қабылдамау', 'Отклонить', 'Decline'),
                  onPressed: () => run(
                      () => context
                          .read(cooperationRepositoryProvider)
                          .answerChange(c.id, false),
                      tr3('已拒绝，原约定继续有效', 'Бұрынғысы күшінде',
                          'Старая версия действует',
                          'The old version stays in effect'))),
            ] else
              Hint(tr3('等待对方确认变更；原约定在此之前继续有效。', 'Екінші жақты күтеміз.',
                  'Ждём ответа; действует прежняя версия.',
                  'Waiting for a reply; the previous version is in effect.')),
            const SizedBox(height: 8),
          ]);
        }
        actions.add(Wrap(spacing: 8, runSpacing: 8, children: [
          if (me == c.providerId)
            FilledButton.icon(
                key: const Key('coop-log-today'),
                onPressed: onLogToday(context, c),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(logTodayLabel(c))),
          if (change == null && data.demand != null)
            OutlinedButton(
                onPressed: () async {
                  final terms = await pushPage<Agreement>(context,
                      (_) => AgreementForm(demand: data.demand!, current: g));
                  if (terms != null && context.mounted) {
                    await run(
                        () => context
                            .read(cooperationRepositoryProvider)
                            .proposeChange(c.id, terms),
                        tr3('变更已发送', 'Жіберілді', 'Отправлено', 'Sent'));
                  }
                },
                child: Text(tr3('提出变更', 'Өзгеріс ұсыну', 'Изменить условия', 'Change the terms'))),
          if (me != c.providerId)
            OutlinedButton(
                onPressed: () async {
                  final text = await askText(
                      context, tr3('记录施工进度（可选）', 'Барыс', 'Ход работ', 'Progress'));
                  if (text != null && context.mounted) {
                    await run(
                        () => context
                            .read(cooperationRepositoryProvider)
                            .addUpdate(c.id, text),
                        tr3('已记录', 'Жазылды', 'Записано', 'Recorded'));
                  }
                },
                child: Text(tr3('记录进度', 'Барысты жазу', 'Отметить ход работ', 'Log progress'))),
          TextButton(
              onPressed: () async {
                final note = await askText(context,
                    tr3('请求结束合作', 'Аяқтауды сұрау', 'Завершить сотрудничество', 'End the cooperation'),
                    required: false,
                    hint: tr3(
                        '例如：已完工', 'Мысалы: бітті', 'Напр.: работы выполнены', 'E.g. the work is done'));
                if (note != null && context.mounted) {
                  await run(
                      () => context
                          .read(cooperationRepositoryProvider)
                          .requestEnd(c.id, note),
                      tr3('已发送，等待对方确认', 'Жіберілді', 'Отправлено', 'Sent'));
                }
              },
              child: Text(tr3('请求结束', 'Аяқтау', 'Завершить', 'Finish'))),
        ]));
      }
    } else if (c.status == CooperationStatus.ended) {
      final open = reviewsOpen(c, context.now);
      actions.add(Hint(switch (c.endKind) {
        EndKind.mutual => tr3(
            '双方已确认结束。评价可选，双方都提交或 14 天后公开。',
            'Екі жақ аяқтады. Пікір міндетті емес.',
            'Обе стороны подтвердили. Отзыв по желанию.',
            'Both sides confirmed. A review is optional.'),
        EndKind.unilateral => tr3(
            '一方报告结束，对方未回应。这不代表双方验收，不开放已验证评价。',
            'Бір жақ аяқтады. Бұл екі жақты қабылдау емес.',
            'Завершено одной стороной; это не совместная приёмка.',
            "Finished by one side; this isn't a joint acceptance."),
        _ => tr3('合作已结束。', 'Аяқталды.', 'Завершено.', 'Finished.'),
      }));
      if (open && myReview == null) {
        actions.addAll([
          const SizedBox(height: 10),
          BusyButton(
              label: tr3('评价对方（可跳过）', 'Пікір қалдыру', 'Оставить отзыв', 'Leave a review'),
              onPressed: () => pushPage<void>(
                  context,
                  (_) => ReviewPage(
                      cooperationId: c.id,
                      otherName: nameOf(c.otherSide(me)),
                      ratingPro: iAmOwner))),
        ]);
      }
    }

    return PageScaffold(
        title: tr3('合作详情', 'Келісім', 'Сотрудничество', 'Cooperation'),
        actions: [
          IconButton(
              tooltip: tr3('联系对方', 'Жазу', 'Написать', 'Message'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () async {
                final conv = await attempt(
                    context,
                    () => context.read(chatRepositoryProvider).openConversation(
                        c.otherSide(me),
                        demandId: c.demandId));
                if (conv != null && context.mounted) {
                  await pushPage<void>(
                      context, (_) => ChatPage(conversationId: conv.id));
                }
              }),
        ],
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
              onTap: () => pushPage<void>(
                  context, (_) => DemandDetailPage(demandId: c.demandId)),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: YFont.display, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          Row(children: [
            StatusPill(cooperationStatusName(c),
                color: c.status == CooperationStatus.confirmed ? t.ok : null),
            const SizedBox(width: 8),
            Expanded(
                child: Text('$ownerName ⇄ $providerName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted))),
          ]),
          const SizedBox(height: 18),
          _AgreementCard(
              agreement: g,
              nameOf: nameOf,
              ownerId: c.ownerId,
              providerId: c.providerId,
              exactAddress: !iAmOwner &&
                      g.shareExactAddress &&
                      c.status != CooperationStatus.pending
                  ? data.demand?.current.exactAddress
                  : null,
              title: c.status == CooperationStatus.pending
                  ? tr3('待确认约定', 'Расталатын келісім',
                      'Соглашение на подтверждение',
                      'Agreement to confirm')
                  : tr3('当前约定（第 ${g.version} 版）', 'Келісім (${g.version})',
                      'Соглашение (версия ${g.version})',
                      'Agreement (version ${g.version})')),
          const SizedBox(height: 16),
          ...actions,
          if (c.milestones.isNotEmpty &&
              c.status == CooperationStatus.pending) ...[
            SectionTitle(tr3('验收节点', 'Қабылдау кезеңдері', 'Этапы приёмки', 'Acceptance stages'),
                trailing: TextButton.icon(
                    key: const Key('edit-milestones'),
                    onPressed: () => pushPage<void>(
                        context, (_) => MilestoneEditorPage(cooperation: c)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr3('修改', 'Өзгерту', 'Изменить', 'Edit')))),
            for (final m in c.milestones)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      '· ${milestoneName(m.key)} ${m.percent}%${c.agreement.amount == null ? '' : ' (${money(c.agreement.amount! * m.percent ~/ 100)})'}${m.due == null ? '' : ' · ${fmtDay(m.due)}'} — ${m.criteria.isEmpty ? milestoneCriteria(m.key) : m.criteria}')),
          ],
          if (c.status == CooperationStatus.confirmed ||
              c.status == CooperationStatus.ended) ...[
            SectionTitle(
                tr3('施工与验收', 'Құрылыс және қабылдау', 'Стройка и приёмка', 'Build and acceptance')),
            SiteSection(cooperation: c),
          ],
          if (c.updates.isNotEmpty) ...[
            SectionTitle(tr3('施工进度', 'Жұмыс барысы', 'Ход работ', 'Progress')),
            for (final u in c.updates.reversed)
              ListTile(
                  leading: Avatar(nameOf(u.by), size: 32),
                  title: Text(u.text),
                  subtitle: Text('${nameOf(u.by)} · ${fmtDay(u.at)}')),
          ],
          if (data.reviews.isNotEmpty) ...[
            SectionTitle(tr3('评价', 'Пікірлер', 'Отзывы', 'Reviews')),
            if (myReview != null)
              _ReviewTile(
                  review: myReview,
                  author: tr3('我的评价', 'Менің пікірім', 'Мой отзыв', 'My review')),
            if (otherReview != null)
              _ReviewTile(
                  review: otherReview, author: nameOf(otherReview.authorId)),
            if (myReview != null && otherReview == null)
              Text(
                  tr3('对方提交或评价期结束后，双方评价同时公开。', 'Екі жақ жазғанда ашылады.',
                      'Отзывы откроются, когда оба оставят их.',
                      'Reviews open once both of you have left one.'),
                  style: TextStyle(color: t.muted, fontSize: YFont.caption)),
          ],
          if (c.agreements.length > 1) ...[
            SectionTitle(tr3('约定历史', 'Нұсқалар', 'История версий', 'Version history')),
            for (final a in c.agreements.reversed)
              ListTile(
                  title: Text(
                      '${tr3('第 ${a.version} 版', '${a.version}-нұсқа', 'Версия ${a.version}', 'Version ${a.version}')} · ${switch (a.status) {
                    AgreementStatus.active =>
                      tr3('生效中', 'Күшінде', 'Действует', 'In effect'),
                    AgreementStatus.superseded =>
                      tr3('已被替代', 'Ауыстырылды', 'Заменена', 'Replaced'),
                    AgreementStatus.rejected =>
                      tr3('未接受', 'Қабылданбады', 'Отклонена', 'Declined'),
                    AgreementStatus.proposed => tr3('待确认', 'Күтуде', 'Ожидает', 'Pending'),
                  }}'),
                  subtitle: Text(
                      '${a.amount == null ? '—' : money(a.amount, unit: a.amountUnit)} · ${tr3('提出', 'ұсынған', 'предложил', 'proposed')} ${nameOf(a.proposedBy)} · ${fmtDay(a.createdAt)}')),
          ],
          const SizedBox(height: 16),
          Text(
              tr3('聊天内容不能代替确认操作；只有点击确认才算同意。', 'Чат растауды алмастырмайды.',
                  'Сообщения в чате не заменяют подтверждение.',
                  "Chat messages don't replace confirmation."),
              style: TextStyle(color: t.muted, fontSize: YFont.caption)),
        ]));
  }
}

class _AgreementCard extends StatelessWidget {
  const _AgreementCard(
      {required this.agreement,
      required this.nameOf,
      required this.title,
      this.ownerId,
      this.providerId,
      this.previous,
      this.exactAddress});
  final Agreement agreement;
  final String Function(String id) nameOf;
  final String title;
  final String? ownerId;
  final String? providerId;
  final String? exactAddress;
  final Agreement? previous;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final g = agreement;
    String mark(String? a, String? b) => previous != null && a != b ? ' ●' : '';
    return YCard(
        shadow: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: YFont.heading, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          InfoRow(tr3('范围', 'Көлемі', 'Объём', 'Scope') + mark(g.scope, previous?.scope),
              g.scope),
          if (g.headcount != null)
            InfoRow(tr3('人数', 'Адам', 'Человек', 'People'), '${g.headcount}'),
          InfoRow(
              tr3('金额', 'Сома', 'Сумма', 'Amount') +
                  mark('${g.amount}${g.amountUnit}',
                      '${previous?.amount}${previous?.amountUnit}'),
              '${g.amount == null ? tr3('待定', 'Келісіледі', 'Не указана', 'Not set') : money(g.amount, unit: g.amountUnit)} · ${pricingName(g.pricing)}'),
          InfoRow(
              tr3('时间', 'Уақыты', 'Сроки', 'Dates') +
                  mark(fmtDay(g.startDate) + fmtDay(g.endDate),
                      fmtDay(previous?.startDate) + fmtDay(previous?.endDate)),
              '${fmtDay(g.startDate)} → ${fmtDay(g.endDate)}'),
          if (g.paymentTerms.isNotEmpty)
            InfoRow(
                tr3('付款约定', 'Төлем', 'Оплата', 'Payment') +
                    mark(g.paymentTerms, previous?.paymentTerms),
                g.paymentTerms),
          if (g.materialsResponsibility.isNotEmpty)
            InfoRow(tr3('材料工具', 'Материал', 'Материалы', 'Materials'),
                g.materialsResponsibility),
          if (g.openItems.isNotEmpty)
            InfoRow(tr3('待确认事项', 'Ашық мәселелер', 'Открыто', 'Open'), g.openItems),
          InfoRow(tr3('依据需求版本', 'Тапсырыс нұсқасы', 'Версия заявки', 'Request version'),
              '${g.demandVersionNo}'),
          if (exactAddress != null && exactAddress!.isNotEmpty)
            InfoRow(tr3('具体地址', 'Мекенжай', 'Адрес', 'Address'), exactAddress!,
                icon: Icons.place_outlined),
          if (ownerId != null) ...[
            const Divider(height: 20),
            for (final id in [ownerId!, providerId!])
              Row(children: [
                Icon(
                    g.confirmedBy.contains(id)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: g.confirmedBy.contains(id) ? t.ok : t.faint),
                const SizedBox(width: 8),
                Text(
                    '${nameOf(id)} ${g.confirmedBy.contains(id) ? tr3('已确认', 'растады', 'подтвердил', 'confirmed') : tr3('未确认', 'растамады', 'не подтвердил', 'not confirmed')}'),
              ]),
          ],
        ]));
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, required this.author});
  final Review review;
  final String author;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(author, style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 12, children: [
            for (final e in review.scores.entries)
              Text('${dimensionName(e.key)} ${e.value}/5',
                  style: TextStyle(color: t.muted, fontSize: YFont.small)),
          ]),
          if (review.text.isNotEmpty) Text(review.text),
        ]));
  }
}
