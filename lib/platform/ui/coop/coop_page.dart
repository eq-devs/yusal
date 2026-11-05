import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../chat/chat_page.dart';
import '../demand/demand_detail_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import '../houses/site_tab.dart';
import 'milestone_editor.dart';
import 'agreement_form.dart';
import 'review_page.dart';

class _CoopData {
  _CoopData(this.coop, this.demand, this.owner, this.provider, this.profile,
      this.reviews);
  final Cooperation? coop;
  final Demand? demand;
  final Account? owner, provider;
  final ServiceProfile? profile;
  final List<Review> reviews;
}

/// Cooperation detail: agreement and its versions, two-sided confirmation,
/// changes, progress notes, ending and optional reviews.
class CooperationPage extends StatelessWidget {
  const CooperationPage({super.key, required this.cooperationId});
  final String cooperationId;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return Live<_CoopData>(
        load: (r) async {
          final c = await r.cooperation(cooperationId);
          if (c == null)
            return _CoopData(null, null, null, null, null, const []);
          return _CoopData(
              c,
              await r.demand(c.demandId),
              await r.account(c.ownerId),
              await r.account(c.providerId),
              await r.profile(c.profileId),
              await r.reviewsFor(c.id));
        },
        loading:
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        builder: (context, data) => data.coop == null
            ? PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.lock_outline,
                    title: tr3('无权查看或合作不存在', 'Қолжетімсіз', 'Нет доступа')))
            : _CoopView(data: data));
  }
}

class _CoopView extends StatelessWidget {
  const _CoopView({required this.data});
  final _CoopData data;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = data.coop!;
    final repos = context.repos;
    final me = repos.currentAccount?.id ?? '';
    final iAmOwner = me == c.ownerId;
    final g = c.agreement;
    final change = c.pendingChange;
    final title = data.demand?.current.title ?? '';
    final ownerName = deletedName(data.owner),
        providerName = data.profile?.name ?? deletedName(data.provider);
    String nameOf(String id) => id == c.ownerId ? ownerName : providerName;
    final myReview = data.reviews.where((r) => r.authorId == me).firstOrNull;
    final otherReview = data.reviews.where((r) => r.authorId != me).firstOrNull;

    Future<void> run(Future<Object?> Function() f, String done) =>
        attempt(context, f, success: done);

    final actions = <Widget>[];
    if (c.status == CooperationStatus.pending) {
      if (!iAmOwner) {
        actions.addAll([
          BusyButton(
              label: tr3('确认合作', 'Келісімді растау', 'Подтвердить'),
              onPressed: () => run(
                  () => repos.confirm(c.id),
                  tr3('合作已双方确认', 'Келісім расталды',
                      'Сотрудничество подтверждено'))),
          const SizedBox(height: 8),
          BusyButton(
              outlined: true,
              label: tr3('拒绝', 'Бас тарту', 'Отказаться'),
              onPressed: () => run(() => repos.decline(c.id),
                  tr3('已拒绝，合作未成立', 'Бас тартылды', 'Отказ отправлен'))),
        ]);
      } else {
        actions.addAll([
          Hint(tr3(
              '已确认我方，等待对方确认。对方未确认前不算合作成立。',
              'Сіз растадыңыз, екінші жақты күтеміз.',
              'Вы подтвердили, ждём вторую сторону.')),
          const SizedBox(height: 8),
          BusyButton(
              outlined: true,
              label: tr3('撤回邀请', 'Шақыруды қайтару', 'Отозвать приглашение'),
              onPressed: () => run(() => repos.revoke(c.id),
                  tr3('已撤回', 'Қайтарылды', 'Отозвано'))),
        ]);
      }
    } else if (c.status == CooperationStatus.confirmed) {
      final r = c.endRequest;
      if (r != null && r.dispute == null && r.by != me) {
        actions.addAll([
          Hint(
              tr3(
                  '${nameOf(r.by)} 请求结束合作${r.note.isEmpty ? '' : '：${r.note}'}',
                  '${nameOf(r.by)} аяқтауды сұрады',
                  '${nameOf(r.by)} просит завершить'),
              warn: true),
          if (c.milestones
              .any((m) => m.status != MilestoneStatus.accepted)) ...[
            const SizedBox(height: 8),
            Hint(tr3(
                '还有 ${c.milestones.where((m) => m.status != MilestoneStatus.accepted).length} 个验收节点没确认（已验收 ${c.acceptedPercent}%）。确认结束后记录会定格在这里，先看看施工页再决定。',
                'Қабылданбаған кезеңдер бар (${c.acceptedPercent}%).',
                'Есть непринятые этапы (принято ${c.acceptedPercent}%).')),
          ],
          const SizedBox(height: 8),
          BusyButton(
              label: tr3('确认结束', 'Аяқтауды растау', 'Подтвердить завершение'),
              onPressed: () => run(() => repos.confirmEnd(c.id),
                  tr3('合作已结束', 'Аяқталды', 'Завершено'))),
          const SizedBox(height: 8),
          // Not a BusyButton: it would spin behind the dialog while the
          // reason is being typed.
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: () async {
                    final note = await askText(
                        context, tr3('异议说明', 'Қарсылық', 'Причина'));
                    if (note != null && context.mounted)
                      await run(() => repos.disputeEnd(c.id, note),
                          tr3('已提交异议', 'Жіберілді', 'Отправлено'));
                  },
                  child: Text(tr3('提出异议', 'Қарсылық', 'Оспорить')))),
        ]);
      } else if (r != null && r.dispute == null) {
        actions.add(Hint(tr3(
            '已请求结束，等待对方确认。对方 7 天未回应将记为“单方报告结束”，不显示为双方验收。',
            'Аяқтау сұралды. 7 күн жауап болмаса, бір жақты аяқталды деп белгіленеді.',
            'Запрос отправлен. Без ответа 7 дней — «завершено одной стороной».')));
      } else {
        if (r?.dispute != null)
          actions.addAll([
            Hint(
                tr3('结束有异议：${r!.dispute}', 'Қарсылық: ${r.dispute}',
                    'Спор: ${r.dispute}'),
                warn: true),
            const SizedBox(height: 8),
          ]);
        if (change != null) {
          actions.addAll([
            _AgreementCard(
                agreement: change,
                nameOf: nameOf,
                previous: g,
                title: tr3(
                    '变更提案（第 ${change.version} 版）',
                    'Өзгеріс (${change.version})',
                    'Изменение (версия ${change.version})')),
            const SizedBox(height: 8),
            if (change.proposedBy != me) ...[
              BusyButton(
                  label: tr3('接受变更', 'Қабылдау', 'Принять'),
                  onPressed: () => run(() => repos.answerChange(c.id, true),
                      tr3('新约定已生效', 'Күшіне енді', 'Действует новая версия'))),
              const SizedBox(height: 8),
              BusyButton(
                  outlined: true,
                  label: tr3('拒绝变更', 'Қабылдамау', 'Отклонить'),
                  onPressed: () => run(
                      () => repos.answerChange(c.id, false),
                      tr3('已拒绝，原约定继续有效', 'Бұрынғысы күшінде',
                          'Старая версия действует'))),
            ] else
              Hint(tr3('等待对方确认变更；原约定在此之前继续有效。', 'Екінші жақты күтеміз.',
                  'Ждём ответа; действует прежняя версия.')),
            const SizedBox(height: 8),
          ]);
        }
        actions.add(Wrap(spacing: 8, runSpacing: 8, children: [
          if (me == c.providerId)
            FilledButton.icon(
                key: const Key('coop-log-today'),
                onPressed: () => logToday(context, c),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(tr3('今天记工', 'Бүгінді жазу', 'Отметить день'))),
          if (change == null && data.demand != null)
            OutlinedButton(
                onPressed: () async {
                  final terms = await pushPage<Agreement>(context,
                      (_) => AgreementForm(demand: data.demand!, current: g));
                  if (terms != null && context.mounted)
                    await run(() => repos.proposeChange(c.id, terms),
                        tr3('变更已发送', 'Жіберілді', 'Отправлено'));
                },
                child: Text(tr3('提出变更', 'Өзгеріс ұсыну', 'Изменить условия'))),
          if (me != c.providerId)
            OutlinedButton(
                onPressed: () async {
                  final text = await askText(
                      context, tr3('记录施工进度（可选）', 'Барыс', 'Ход работ'));
                  if (text != null && context.mounted)
                    await run(() => repos.addUpdate(c.id, text),
                        tr3('已记录', 'Жазылды', 'Записано'));
                },
                child: Text(tr3('记录进度', 'Барысты жазу', 'Отметить ход работ'))),
          TextButton(
              onPressed: () async {
                final note = await askText(context,
                    tr3('请求结束合作', 'Аяқтауды сұрау', 'Завершить сотрудничество'),
                    required: false,
                    hint: tr3(
                        '例如：已完工', 'Мысалы: бітті', 'Напр.: работы выполнены'));
                if (note != null && context.mounted)
                  await run(() => repos.requestEnd(c.id, note),
                      tr3('已发送，等待对方确认', 'Жіберілді', 'Отправлено'));
              },
              child: Text(tr3('请求结束', 'Аяқтау', 'Завершить'))),
        ]));
      }
    } else if (c.status == CooperationStatus.ended) {
      final open = reviewsOpen(c, context.now);
      actions.add(Hint(switch (c.endKind) {
        EndKind.mutual => tr3(
            '双方已确认结束。评价可选，双方都提交或 14 天后公开。',
            'Екі жақ аяқтады. Пікір міндетті емес.',
            'Обе стороны подтвердили. Отзыв по желанию.'),
        EndKind.unilateral => tr3(
            '一方报告结束，对方未回应。这不代表双方验收，不开放已验证评价。',
            'Бір жақ аяқтады. Бұл екі жақты қабылдау емес.',
            'Завершено одной стороной; это не совместная приёмка.'),
        _ => tr3('合作已结束。', 'Аяқталды.', 'Завершено.'),
      }));
      if (open && myReview == null) {
        actions.addAll([
          const SizedBox(height: 10),
          BusyButton(
              label: tr3('评价对方（可跳过）', 'Пікір қалдыру', 'Оставить отзыв'),
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
        title: tr3('合作详情', 'Келісім', 'Сотрудничество'),
        actions: [
          IconButton(
              tooltip: tr3('联系对方', 'Жазу', 'Написать'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () async {
                final conv = await attempt(
                    context,
                    () => repos.openConversation(c.otherSide(me),
                        demandId: c.demandId));
                if (conv != null && context.mounted)
                  await pushPage<void>(
                      context, (_) => ChatPage(conversationId: conv.id));
              }),
        ],
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
              onTap: () => pushPage<void>(
                  context, (_) => DemandDetailPage(demandId: c.demandId)),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700))),
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
                      'Соглашение на подтверждение')
                  : tr3('当前约定（第 ${g.version} 版）', 'Келісім (${g.version})',
                      'Соглашение (версия ${g.version})')),
          const SizedBox(height: 16),
          ...actions,
          if (c.milestones.isNotEmpty &&
              c.status == CooperationStatus.pending) ...[
            SectionTitle(tr3('验收节点', 'Қабылдау кезеңдері', 'Этапы приёмки'),
                trailing: TextButton.icon(
                    key: const Key('edit-milestones'),
                    onPressed: () => pushPage<void>(
                        context, (_) => MilestoneEditorPage(cooperation: c)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr3('修改', 'Өзгерту', 'Изменить')))),
            for (final m in c.milestones)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      '· ${milestoneName(m.key)} ${m.percent}%${c.agreement.amount == null ? '' : ' (${money(c.agreement.amount! * m.percent ~/ 100)})'}${m.due == null ? '' : ' · ${fmtDay(m.due)}'} — ${m.criteria.isEmpty ? milestoneCriteria(m.key) : m.criteria}')),
          ],
          if (c.status == CooperationStatus.confirmed ||
              c.status == CooperationStatus.ended) ...[
            SectionTitle(
                tr3('施工与验收', 'Құрылыс және қабылдау', 'Стройка и приёмка')),
            SiteSection(cooperation: c),
          ],
          if (c.updates.isNotEmpty) ...[
            SectionTitle(tr3('施工进度', 'Жұмыс барысы', 'Ход работ')),
            for (final u in c.updates.reversed)
              ListTile(
                  leading: Avatar(nameOf(u.by), size: 32),
                  title: Text(u.text),
                  subtitle: Text('${nameOf(u.by)} · ${fmtDay(u.at)}')),
          ],
          if (data.reviews.isNotEmpty) ...[
            SectionTitle(tr3('评价', 'Пікірлер', 'Отзывы')),
            if (myReview != null)
              _ReviewTile(
                  review: myReview,
                  author: tr3('我的评价', 'Менің пікірім', 'Мой отзыв')),
            if (otherReview != null)
              _ReviewTile(
                  review: otherReview, author: nameOf(otherReview.authorId)),
            if (myReview != null && otherReview == null)
              Text(
                  tr3('对方提交或评价期结束后，双方评价同时公开。', 'Екі жақ жазғанда ашылады.',
                      'Отзывы откроются, когда оба оставят их.'),
                  style: TextStyle(color: t.muted, fontSize: 12)),
          ],
          if (c.agreements.length > 1) ...[
            SectionTitle(tr3('约定历史', 'Нұсқалар', 'История версий')),
            for (final a in c.agreements.reversed)
              ListTile(
                  title: Text(
                      '${tr3('第 ${a.version} 版', '${a.version}-нұсқа', 'Версия ${a.version}')} · ${switch (a.status) {
                    AgreementStatus.active =>
                      tr3('生效中', 'Күшінде', 'Действует'),
                    AgreementStatus.superseded =>
                      tr3('已被替代', 'Ауыстырылды', 'Заменена'),
                    AgreementStatus.rejected =>
                      tr3('未接受', 'Қабылданбады', 'Отклонена'),
                    AgreementStatus.proposed => tr3('待确认', 'Күтуде', 'Ожидает'),
                  }}'),
                  subtitle: Text(
                      '${a.amount == null ? '—' : money(a.amount, unit: a.amountUnit)} · ${tr3('提出', 'ұсынған', 'предложил')} ${nameOf(a.proposedBy)} · ${fmtDay(a.createdAt)}')),
          ],
          const SizedBox(height: 16),
          Text(
              tr3('聊天内容不能代替确认操作；只有点击确认才算同意。', 'Чат растауды алмастырмайды.',
                  'Сообщения в чате не заменяют подтверждение.'),
              style: TextStyle(color: t.muted, fontSize: 12)),
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
  final String? ownerId, providerId, exactAddress;
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
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          InfoRow(tr3('范围', 'Көлемі', 'Объём') + mark(g.scope, previous?.scope),
              g.scope),
          if (g.headcount != null)
            InfoRow(tr3('人数', 'Адам', 'Человек'), '${g.headcount}'),
          InfoRow(
              tr3('金额', 'Сома', 'Сумма') +
                  mark('${g.amount}${g.amountUnit}',
                      '${previous?.amount}${previous?.amountUnit}'),
              '${g.amount == null ? tr3('待定', 'Келісіледі', 'Не указана') : money(g.amount, unit: g.amountUnit)} · ${pricingName(g.pricing)}'),
          InfoRow(
              tr3('时间', 'Уақыты', 'Сроки') +
                  mark(fmtDay(g.startDate) + fmtDay(g.endDate),
                      fmtDay(previous?.startDate) + fmtDay(previous?.endDate)),
              '${fmtDay(g.startDate)} → ${fmtDay(g.endDate)}'),
          if (g.paymentTerms.isNotEmpty)
            InfoRow(
                tr3('付款约定', 'Төлем', 'Оплата') +
                    mark(g.paymentTerms, previous?.paymentTerms),
                g.paymentTerms),
          if (g.materialsResponsibility.isNotEmpty)
            InfoRow(tr3('材料工具', 'Материал', 'Материалы'),
                g.materialsResponsibility),
          if (g.openItems.isNotEmpty)
            InfoRow(tr3('待确认事项', 'Ашық мәселелер', 'Открыто'), g.openItems),
          InfoRow(tr3('依据需求版本', 'Тапсырыс нұсқасы', 'Версия заявки'),
              '${g.demandVersionNo}'),
          if (exactAddress != null && exactAddress!.isNotEmpty)
            InfoRow(tr3('具体地址', 'Мекенжай', 'Адрес'), exactAddress!,
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
                    '${nameOf(id)} ${g.confirmedBy.contains(id) ? tr3('已确认', 'растады', 'подтвердил') : tr3('未确认', 'растамады', 'не подтвердил')}'),
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
                  style: TextStyle(color: t.muted, fontSize: 13)),
          ]),
          if (review.text.isNotEmpty) Text(review.text),
        ]));
  }
}
