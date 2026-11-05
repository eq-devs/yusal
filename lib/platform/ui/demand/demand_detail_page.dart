import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../apply/apply_page.dart';
import '../cards.dart';
import '../chat/chat_page.dart';
import '../coop/coop_page.dart';
import '../l10n.dart';
import '../design/plan_viewer.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'applications_page.dart';
import 'publish_page.dart';
import 'share_page.dart';
import '../home/post_page.dart';
import '../../../motion/motion.dart';

class _DetailData {
  _DetailData(this.demand, this.owner, this.snapshot, this.myApps, this.coops,
      this.applicationCount);
  final Demand? demand;
  final Account? owner;
  final DesignSnapshot? snapshot;
  final List<Application> myApps;
  final List<Cooperation> coops;
  final int applicationCount;
}

class DemandDetailPage extends StatelessWidget {
  const DemandDetailPage({super.key, required this.demandId});
  final String demandId;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return Live<_DetailData>(
        load: (r) async {
          final d = await r.demand(demandId);
          if (d == null)
            return _DetailData(null, null, null, const [], const [], 0);
          final me = r.currentAccount?.id;
          final mine = me == d.ownerId;
          return _DetailData(
              d,
              await r.account(d.ownerId),
              d.current.snapshotId == null
                  ? null
                  : await r.snapshot(d.current.snapshotId!, demandId: d.id),
              me == null || mine
                  ? const []
                  : (await r.myApplications())
                      .where((a) => a.demandId == d.id)
                      .toList(),
              me == null ? const [] : await r.cooperationsFor(d.id),
              mine ? (await r.applicationsFor(d.id)).length : 0);
        },
        loading:
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        builder: (context, data) {
          final d = data.demand;
          if (d == null)
            return PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.visibility_off_outlined,
                    title: tr3('需求不存在、已下架或无权查看', 'Тапсырыс табылмады не жабық',
                        'Заявка не найдена или недоступна')));
          return _DemandDetail(data: data);
        });
  }
}

class _DemandDetail extends StatelessWidget {
  const _DemandDetail({required this.data});
  final _DetailData data;

  Demand get d => data.demand!;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final repos = context.repos;
    final me = repos.currentAccount?.id;
    final mine = me == d.ownerId;
    final v = d.current;
    final accepting = acceptsApplications(d, context.now);
    final myApp = data.myApps
        .where((a) => a.status != ApplicationStatus.withdrawn)
        .firstOrNull;

    Future<void> apply() async {
      if (!await requireLogin(context) || !context.mounted) return;
      await pushPage<void>(
          context, (_) => ApplyPage(demand: d, existing: myApp));
    }

    Future<void> contact() async {
      if (!await requireLogin(context) || !context.mounted) return;
      final conv = await attempt(context,
          () => context.repos.openConversation(d.ownerId, demandId: d.id));
      if (conv != null && context.mounted)
        await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
    }

    final body =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Cover(
          icon: demandIcon(d),
          seed: d.id,
          height: 190,
          image: data.snapshot?.preview == null
              ? null
              : MemoryImage(Uint8List.fromList(data.snapshot!.preview!)),
          child: data.snapshot?.preview == null && d.current.snapshotId != null
              ? PlanCover(snapshotId: d.current.snapshotId!, demandId: d.id)
              : null),
      Live<HousePost?>(
          reloadKey: ('post-for', d.id),
          load: (r) => r.postForDemand(d.id),
          loading: const SizedBox(height: 18),
          error: (_, __) => const SizedBox(height: 18),
          builder: (context, post) => post == null
              ? const SizedBox(height: 18)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: InkWell(
                      key: const Key('demand-house-link'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => pushPage<void>(
                          context, (_) => PostPage(postId: post.id)),
                      child: Row(children: [
                        Icon(Icons.home_outlined, size: 18, color: t.accent),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                tr3('属于：${post.title}', 'Үй: ${post.title}',
                                    'Дом: ${post.title}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: t.accent,
                                    fontWeight: FontWeight.w600))),
                        Icon(Icons.chevron_right, color: t.accent),
                      ])))),
      Wrap(spacing: 8, runSpacing: 6, children: [
        StatusPill(demandTypeName(d.type), color: t.accent),
        StatusPill(demandStatusName(d.status),
            color: demandStatusColor(t, d.status)),
        if (d.publisherRole == PublisherRole.contractor)
          StatusPill(tr3('分包需求', 'Қосалқы мердігерлік', 'Субподряд')),
      ]),
      const SizedBox(height: 10),
      Text(v.title,
          style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, height: 1.2)),
      const SizedBox(height: 6),
      Text(
          '${regionName(v.region)}${v.locality.isEmpty ? '' : ' · ${v.locality}'} · ${tr3('第 ${v.no} 版', '${v.no}-нұсқа', 'версия ${v.no}')} · ${ago(v.createdAt, context.now)}',
          style: TextStyle(color: t.muted)),
      if (mine &&
          d.status == DemandStatus.rejected &&
          d.rejectReason != null) ...[
        const SizedBox(height: 14),
        Hint(
            '${tr3('未通过原因', 'Себебі', 'Причина')}: ${d.rejectReason!.startsWith('banned:') ? tr3('包含不允许的内容（如收取押金）', 'Рұқсат етілмеген мазмұн (мысалы кепілақы)', 'Недопустимое содержание (например, залог)') : d.rejectReason}. ${tr3('修改后可重新提交审核。', 'Түзетіп, қайта жіберіңіз.', 'Исправьте и отправьте снова.')}',
            warn: true),
      ],
      const Divider(height: 36),
      Row(children: [
        Avatar(deletedName(data.owner), size: 48),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              tr3(
                  '发布者：${deletedName(data.owner)}',
                  'Жариялаған: ${deletedName(data.owner)}',
                  'Автор: ${deletedName(data.owner)}'),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(
              [
                if (data.owner?.phoneVerified == true)
                  tr3('手机号已验证', 'Телефон расталған', 'Телефон подтверждён'),
                if (d.publisherRole == PublisherRole.contractor)
                  tr3('施工方发布，非房屋所有人', 'Мердігер жариялаған',
                      'Размещено подрядчиком'),
              ].join(' · '),
              style: TextStyle(color: t.muted, fontSize: 13)),
        ])),
      ]),
      const Divider(height: 36),
      if (v.description.isNotEmpty) ...[
        Text(v.description, style: const TextStyle(fontSize: 15, height: 1.5)),
        const SizedBox(height: 12),
      ],
      InfoRow(tr3('工种', 'Мамандық', 'Специальность'),
          v.trades.map(tradeName).join('、'),
          icon: Icons.handyman_outlined),
      InfoRow(tr3('开工', 'Басталуы', 'Начало'), fmtDay(v.startDate),
          icon: Icons.event_outlined),
      if (v.durationDays != null)
        InfoRow(tr3('预计天数', 'Күн саны', 'Срок, дней'), '${v.durationDays}',
            icon: Icons.timelapse_outlined),
      InfoRow(tr3('预算', 'Бюджет', 'Бюджет'),
          '${budgetText(v.budget)} · ${materialName(v.budget.materials)}',
          icon: Icons.payments_outlined),
      if (v.photoCount > 0)
        InfoRow(tr3('现场照片', 'Фото', 'Фото'), '${v.photoCount}',
            icon: Icons.photo_library_outlined),
      if (v.siteNotes.isNotEmpty)
        InfoRow(tr3('现场限制', 'Орын шектеулері', 'Ограничения'), v.siteNotes,
            icon: Icons.warning_amber_outlined),
      if (mine && v.exactAddress.isNotEmpty)
        InfoRow(
            tr3('具体地址（仅自己可见）', 'Мекенжай (тек сізге)',
                'Адрес (видите только вы)'),
            v.exactAddress,
            icon: Icons.lock_outline),
      if (v.hire != null) ..._hire(context, v.hire!),
      if (v.contract != null) ..._contract(context, v.contract!),
      if (data.snapshot != null)
        ..._snapshot(context, data.snapshot!, v.visibility, mine),
      const SizedBox(height: 20),
      Hint(tr3(
          '平台不要求、也不建议工人缴纳任何招工押金。平台目前没有资金托管，付款请按合作约定自行完成。',
          'Платформа жұмысшыдан ешқандай кепілақы талап етпейді. Төлем кепілдігі жоқ.',
          'Платформа не требует залогов от рабочих. Гарантии оплаты нет — платите по соглашению.')),
      if (mine) ..._ownerPanel(context),
      if (!mine && data.coops.isNotEmpty) ...[
        const SectionTitle('我的合作 · Cooperation'),
        for (final c in data.coops)
          ListTile(
              title: Text(cooperationStatusName(c)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openCooperation(context, c.id)),
      ],
      const SizedBox(height: 24),
    ]);

    Widget? bottom;
    if (!mine) {
      final label = myApp != null
          ? tr3('查看我的${d.type == DemandType.hire ? '报名' : '报价'}',
              'Өтінімімді көру', 'Мой отклик')
          : d.type == DemandType.hire
              ? tr3('报名', 'Өтінім беру', 'Откликнуться')
              : tr3('报价', 'Баға ұсыну', 'Предложить цену');
      bottom = Row(children: [
        Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(budgetText(v.budget),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              Text(
                  accepting
                      ? (d.expiresAt == null
                          ? ''
                          : tr3(
                              '${fmtDay(d.expiresAt)} 截止',
                              '${fmtDay(d.expiresAt)} дейін',
                              'до ${fmtDay(d.expiresAt)}'))
                      : tr3('暂不接收新申请', 'Жаңа өтінім қабылданбайды',
                          'Отклики не принимаются'),
                  style: TextStyle(color: t.muted, fontSize: 12)),
            ])),
        IconButton(
            tooltip: tr3('联系发布者', 'Жариялаушыға жазу', 'Написать автору'),
            onPressed: contact,
            icon: const Icon(Icons.chat_bubble_outline)),
        const SizedBox(width: 6),
        StateSwitcher(
            child: KeyedSubtree(
                key: ValueKey(myApp != null),
                child: FilledButton(
                    onPressed: myApp != null || accepting ? apply : null,
                    child: Text(label)))),
      ]);
    }

    return Scaffold(
        appBar: AppBar(actions: [
          IconButton(
              tooltip: tr3('分享', 'Бөлісу', 'Поделиться'),
              icon: const Icon(Icons.ios_share),
              onPressed: () =>
                  pushPage<void>(context, (_) => SharePage(demand: d))),
          if (!mine)
            PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'report') {
                    final reason = await askText(
                        context, tr3('举报这个需求', 'Шағымдану', 'Пожаловаться'),
                        hint: tr3('说明原因，例如收押金、虚假信息', 'Себебін жазыңыз',
                            'Причина, например залог или ложные данные'));
                    if (reason != null && context.mounted)
                      await attempt(
                          context,
                          () => context.repos
                              .report(ReportTarget.demand, d.id, reason),
                          success: tr3(
                              '已提交，审核人员会处理', 'Жіберілді', 'Жалоба отправлена'));
                  }
                  if (value == 'block' && context.mounted) {
                    if (await requireLogin(context) && context.mounted)
                      await attempt(
                          context, () => context.repos.block(d.ownerId),
                          success: tr3('已拉黑，不再看到对方内容', 'Бұғатталды',
                              'Пользователь заблокирован'));
                  }
                },
                itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'report',
                          child: Text(tr3('举报', 'Шағым', 'Пожаловаться'))),
                      PopupMenuItem(
                          value: 'block',
                          child: Text(tr3(
                              '拉黑发布者', 'Бұғаттау', 'Заблокировать автора'))),
                    ]),
        ]),
        body: SafeArea(
            top: false,
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: body)))),
        bottomNavigationBar: bottom == null ? null : ActionBar(child: bottom));
  }

  List<Widget> _hire(BuildContext context, HireTerms h) => [
        SectionTitle(tr3('招工条件', 'Жалдау шарттары', 'Условия найма')),
        InfoRow(tr3('人数', 'Адам саны', 'Человек'), '${h.headcount}'),
        InfoRow(tr3('计酬方式', 'Төлем түрі', 'Оплата'), payModeName(h.payMode)),
        InfoRow(
            tr3('工资', 'Жалақы', 'Ставка'),
            h.wage == null
                ? tr3('面议', 'Келісіледі', 'Договорная')
                : money(h.wage, unit: h.wageUnit)),
        if (h.days != null) InfoRow(tr3('工作天数', 'Күн', 'Дней'), '${h.days}'),
        InfoRow(
            tr3('食宿', 'Тамақ, жатын орын', 'Питание и жильё'),
            h.foodLodging
                ? tr3('提供', 'Бар', 'Есть')
                : tr3('不提供', 'Жоқ', 'Нет')),
        InfoRow(
            tr3('工具', 'Құрал', 'Инструмент'),
            h.toolsByEmployer
                ? tr3('雇主提供', 'Жұмыс беруші', 'Даёт работодатель')
                : tr3('自带', 'Өзінікі', 'Свой')),
        InfoRow(tr3('结算', 'Есеп айырысу', 'Расчёт'), settleName(h.settleCycle)),
      ];

  List<Widget> _contract(BuildContext context, ContractTerms c) => [
        SectionTitle(tr3('承包范围', 'Мердігерлік көлемі', 'Объём подряда')),
        InfoRow(tr3('范围', 'Көлемі', 'Объём'),
            '${scopeKindName(c.scopeKind)}${c.stages.isEmpty ? '' : ' · ${c.stages.map(stageLabel).join('、')}'}'),
        InfoRow(tr3('人工／材料', 'Жұмыс / материал', 'Работа / материалы'),
            materialName(c.materials)),
        if (c.targetDays != null)
          InfoRow(
              tr3('目标工期', 'Мерзім', 'Срок'),
              tr3('${c.targetDays} 天', '${c.targetDays} күн',
                  '${c.targetDays} дн.')),
        if (c.quoteDeadline != null)
          InfoRow(tr3('报价截止', 'Ұсыныс мерзімі', 'Приём цен до'),
              fmtDay(c.quoteDeadline)),
        if (c.quantities.isNotEmpty) ...[
          const SizedBox(height: 8),
          QtyTable(c.quantities),
        ],
      ];

  List<Widget> _snapshot(BuildContext context, DesignSnapshot s,
      AttachmentVisibility vis, bool mine) {
    final t = YTokens.of(context);
    return [
      PlanAttachment(snapshot: s, hidden: !vis.plan && !mine),
      SectionTitle(tr3('设计附件', 'Жоба тіркемесі', 'Проект')),
      YCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.projectName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text(s.summary, style: TextStyle(color: t.muted)),
        const SizedBox(height: 4),
        Text(
            tr3(
                '固定版本：提取于 ${fmtDay(s.extractedAt)}，设计后续修改不会改变此附件。',
                'Бекітілген нұсқа: ${fmtDay(s.extractedAt)}. Кейінгі өзгерістер әсер етпейді.',
                'Зафиксировано ${fmtDay(s.extractedAt)}; дальнейшие правки проекта не меняют вложение.'),
            style: TextStyle(color: t.muted, fontSize: 12)),
        if (s.stages.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final st in s.stages) StatusPill(stageLabel(st)),
          ]),
        ],
        if (s.lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          QtyTable(s.lines),
        ] else if (!vis.quantities)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  tr3('工程量未公开，可联系发布者', 'Көлем жарияланбаған',
                      'Объёмы не опубликованы'),
                  style: TextStyle(color: t.muted))),
        if (mine)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  '${tr3('公开', 'Жария', 'Публично')}: ${[
                    if (vis.quantities) tr3('工程量', 'көлем', 'объёмы'),
                    if (vis.plan) tr3('平面图', 'жоспар', 'план'),
                    if (vis.render) tr3('效果图', 'көрініс', 'визуализация'),
                  ].join('、')}. ${tr3('完整 .house 文件不公开。', '.house файлы жарияланбайды.', 'Файл .house не публикуется.')}',
                  style: TextStyle(color: t.muted, fontSize: 12))),
      ])),
    ];
  }

  List<Widget> _ownerPanel(BuildContext context) {
    final t = YTokens.of(context);
    final repos = context.repos;
    final hired = hiredCount(data.coops);
    final h = d.current.hire;
    Future<void> act(Future<Object?> Function() f, String done) =>
        attempt(context, f, success: done);
    return [
      SectionTitle(tr3('管理需求', 'Басқару', 'Управление')),
      if (h != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Hint(
                tr3(
                    '已录用 $hired / 计划 ${h.headcount} 人。录用不会自动关闭需求，人数够了可以标记“已找到人”。',
                    'Жалданды $hired / ${h.headcount}. Тапсырыс өзі жабылмайды.',
                    'Нанято $hired из ${h.headcount}. Заявка не закрывается сама.'),
                warn: hired >= h.headcount && d.status == DemandStatus.open)),
      if (d.expiresAt != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                tr3(
                    '有效期至 ${fmtDay(d.expiresAt)}',
                    '${fmtDay(d.expiresAt)} дейін',
                    'Действует до ${fmtDay(d.expiresAt)}'),
                style: TextStyle(color: t.muted))),
      if (d.outcome != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                '${tr3('结果', 'Нәтиже', 'Итог')}: ${outcomeName(d.outcome!)}',
                style: TextStyle(color: t.muted))),
      YCard(
          onTap: () =>
              pushPage<void>(context, (_) => ApplicationsPage(demandId: d.id)),
          child: Row(children: [
            const Icon(Icons.inbox_outlined),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    d.type == DemandType.hire
                        ? tr3(
                            '报名管理（${data.applicationCount}）',
                            'Өтінімдер (${data.applicationCount})',
                            'Отклики (${data.applicationCount})')
                        : tr3(
                            '报价管理与对比（${data.applicationCount}）',
                            'Ұсыныстар (${data.applicationCount})',
                            'Предложения (${data.applicationCount})'),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right),
          ])),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (d.status == DemandStatus.draft || d.status == DemandStatus.rejected)
          FilledButton(
              onPressed: () => act(
                  () => repos.publish(d.id),
                  tr3('已提交审核', 'Тексеруге жіберілді',
                      'Отправлено на проверку')),
              child: Text(tr3('提交审核', 'Тексеруге жіберу', 'На проверку'))),
        if (d.status != DemandStatus.closed)
          OutlinedButton(
              onPressed: () =>
                  pushPage<void>(context, (_) => PublishPage(editing: d)),
              child: Text(tr3('修改（生成新版本）', 'Өзгерту', 'Изменить'))),
        if (d.status == DemandStatus.open)
          OutlinedButton(
              onPressed: () => act(() => repos.pause(d.id),
                  tr3('已暂停', 'Тоқтатылды', 'Приостановлено')),
              child: Text(tr3('暂停', 'Тоқтату', 'Пауза'))),
        if (d.status == DemandStatus.paused || d.status == DemandStatus.found)
          OutlinedButton(
              onPressed: () => act(() => repos.resume(d.id),
                  tr3('继续招募', 'Жалғасты', 'Набор возобновлён')),
              child: Text(tr3('继续招募', 'Жалғастыру', 'Возобновить'))),
        if (d.status == DemandStatus.expired || d.status == DemandStatus.open)
          OutlinedButton(
              onPressed: () => act(() => repos.renew(d.id),
                  tr3('已续期 30 天', '30 күнге ұзартылды', 'Продлено на 30 дней')),
              child: Text(tr3('续期', 'Ұзарту', 'Продлить'))),
        if (const {DemandStatus.open, DemandStatus.paused, DemandStatus.expired}
            .contains(d.status))
          OutlinedButton(
              onPressed: () async {
                final o = await pickOutcome(context, hired > 0);
                if (o != null && context.mounted)
                  await act(() => repos.markFound(d.id, o),
                      tr3('已标记找到人，停止接收新申请', 'Белгіленді', 'Отмечено'));
              },
              child: Text(tr3('已找到人', 'Адам табылды', 'Исполнитель найден'))),
        if (d.status != DemandStatus.closed)
          OutlinedButton(
              onPressed: () async {
                final reason = await askText(
                    context, tr3('关闭需求', 'Жабу', 'Закрыть заявку'),
                    hint: tr3('原因，例如不再需要', 'Себебі', 'Причина'));
                if (reason != null && context.mounted)
                  await act(() => repos.close(d.id, reason),
                      tr3('已关闭', 'Жабылды', 'Закрыто'));
              },
              child: Text(tr3('关闭', 'Жабу', 'Закрыть'))),
        if (d.outcome == null && d.status != DemandStatus.draft)
          TextButton(
              onPressed: () async {
                final o = await pickOutcome(context, hired > 0);
                if (o != null && context.mounted)
                  await act(() => repos.recordOutcome(d.id, o),
                      tr3('谢谢反馈', 'Рақмет', 'Спасибо'));
              },
              child: Text(tr3('回答结果回访', 'Нәтижені айту', 'Ответить на опрос'))),
      ]),
    ];
  }
}

Future<OutcomeKind?> pickOutcome(BuildContext context, bool hasCoop) =>
    pickOne<OutcomeKind>(
        context, tr3('找到合适的人了吗？', 'Адам таптыңыз ба?', 'Нашли исполнителя?'), [
      if (hasCoop)
        (
          OutcomeKind.platformConfirmed,
          outcomeName(OutcomeKind.platformConfirmed)
        ),
      for (final o in OutcomeKind.values)
        if (o != OutcomeKind.platformConfirmed) (o, outcomeName(o)),
    ]);

/// Quantities with their unit and source.
class QtyTable extends StatelessWidget {
  const QtyTable(this.lines, {super.key});
  final List<QtyItem> lines;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Container(
        decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          for (final (i, l) in lines.indexed)
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    border:
                        i == 0 ? null : Border(top: BorderSide(color: t.line))),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(l.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(qtySourceName(l.source),
                            style: TextStyle(color: t.muted, fontSize: 12)),
                      ])),
                  Text(
                      l.quantity == null
                          ? tr3('现场测量', 'Орында', 'Замер')
                          : '${numText(l.quantity!)} ${unitLabel(l.unit)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ])),
        ]));
  }
}

/// Opens a cooperation page; several pages share it.
void openCooperation(BuildContext context, String id) =>
    pushPage<void>(context, (_) => CooperationPage(cooperationId: id));
