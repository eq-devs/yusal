import 'package:flutter/material.dart';
import 'package:yusal/features/demand/state/demand.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';
import 'package:yusal/features/apply/page.dart';
import 'package:yusal/features/demand/widgets/demand_card.dart';
import 'package:yusal/features/chat/page.dart';
import 'package:yusal/features/coop/page.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/home/widgets/plan_viewer.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/demand/pages/applications.dart';
import 'package:yusal/features/demand/pages/publish.dart';
import 'package:yusal/features/demand/pages/share.dart';
import 'package:yusal/features/home/pages/post.dart';
import 'package:yusal/features/shared/motion/motion.dart';
import 'package:yusal/features/voice/actions/demand.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/features/me/pages/trust.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

class DemandDetailPage extends StatelessWidget {
  const DemandDetailPage({super.key, required this.demandId});
  final String demandId;

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Live<DemandDetailData>(
        provider: demandDetailProvider(demandId),
        loading: const SkeletonPage(),
        builder: (context, data) {
          final d = data.demand;
          if (d == null) {
            return PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.visibility_off_outlined,
                    title: tr3('需求不存在、已下架或无权查看', 'Тапсырыс табылмады не жабық',
                        'Заявка не найдена или недоступна',
                        'Request not found or unavailable', ky: 'Суроо-талап табылган жок же жеткиликсиз', uz: 'Soʻrov topilmadi yoki mavjud emas')));
          }
          return _DemandDetail(data: data);
        });
  }
}

class _DemandDetail extends StatefulWidget {
  const _DemandDetail({required this.data});
  final DemandDetailData data;

  @override
  State<_DemandDetail> createState() => _DemandDetailState();
}

class _DemandDetailState extends State<_DemandDetail>
    with VoiceScreen
    implements DemandHost {
  DemandDetailData get data => widget.data;
  Demand get d => data.demand!;

  @override
  String get screenId => 'demand.detail';

  @override
  Demand? get ownDemand =>
      context.session.currentAccount?.id == d.ownerId ? d : null;

  @override
  bool get hiredSomeone => hiredCount(data.coops) > 0;

  /// The status, so the assistant can say where the demand stands; what
  /// can be done with it is the offered demand.* actions.
  @override
  String get summary => 'demand ${d.status.name}: ${d.current.title}';

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.session.currentAccount?.id;
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
      final conv = await attempt(
          context,
          () => context
              .read(chatRepositoryProvider)
              .openConversation(d.ownerId, demandId: d.id));
      if (conv != null && context.mounted) {
        await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
      }
    }

    final body =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // A picture only when there is a real drawing; otherwise the facts
      // start at the top of the page.
      if (data.snapshot?.preview != null || d.current.snapshotId != null)
        Cover(
            icon: demandIcon(d),
            seed: d.id,
            height: 190,
            image: data.snapshot?.preview == null
                ? null
                : MemoryImage(imageBytes(data.snapshot!.preview!)),
            child: data.snapshot?.preview == null
                ? PlanCover(snapshotId: d.current.snapshotId!, demandId: d.id)
                : null),
      Live<HousePost?>(
          provider: postForDemandProvider(d.id),
          loading: const SizedBox(height: 18),
          error: (_, __) => const SizedBox(height: 18),
          builder: (context, post) => post == null
              ? const SizedBox(height: 18)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: InkWell(
                      key: const Key('demand-house-link'),
                      borderRadius: BorderRadius.circular(YRadius.row),
                      onTap: () => pushPage<void>(
                          context, (_) => PostPage(postId: post.id)),
                      child: Row(children: [
                        Icon(Icons.home_outlined, size: 18, color: t.accent),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                tr3('属于：${post.title}', 'Үй: ${post.title}',
                                    'Дом: ${post.title}',
                                    'House: ${post.title}', ky: 'Үй: ${post.title}', uz: 'Uy: ${post.title}'),
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
          StatusPill(tr3('分包需求', 'Қосалқы мердігерлік', 'Субподряд', 'Subcontract', ky: 'Субподряд', uz: 'Subpudrat')),
      ]),
      const SizedBox(height: 10),
      Semantics(
          header: true,
          child: Text(v.title, style: display(size: 26, color: t.ink))),
      const SizedBox(height: 6),
      Text(
          '${placeText(v.region, v.locality)} · ${tr3('第 ${v.no} 版', '${v.no}-нұсқа', 'версия ${v.no}', 'version ${v.no}', ky: '${v.no}-версия', uz: '${v.no}-versiya')} · ${ago(v.createdAt, context.now)}',
          style: TextStyle(color: t.muted)),
      if (mine &&
          d.status == DemandStatus.rejected &&
          d.rejectReason != null) ...[
        const SizedBox(height: 14),
        Hint(
            '${tr3('未通过原因', 'Себебі', 'Причина', 'Reason', ky: 'Себеби', uz: 'Sababi')}: ${d.rejectReason!.startsWith('banned:') ? tr3('包含不允许的内容（如收取押金）', 'Рұқсат етілмеген мазмұн (мысалы кепілақы)', 'Недопустимое содержание (например, залог)', 'Content not allowed (e.g. a deposit)', ky: 'Тыюу салынган мазмун (мис., алдын ала төлөм)', uz: 'Taqiqlangan kontent (masalan, oldindan toʻlov)') : reasonText(d.rejectReason!)}. ${tr3('修改后可重新提交审核。', 'Түзетіп, қайта жіберіңіз.', 'Исправьте и отправьте снова.', 'Fix it and send it again.', ky: 'Оңдоп, кайра жөнөтүңүз.', uz: 'Tuzatib, qayta yuboring.')}',
            warn: true),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
                onPressed: () => appealDecision(context, 'demand', d.id),
                child: Text(tr3('认为处理有误？申诉', 'Шешім қате ме? Шағымдану',
                    'Не согласны? Обжаловать',
                    'Disagree? Appeal', ky: 'Макул эмессизби? Даттаныңыз', uz: 'Rozi emasmisiz? Apellyatsiya bering')))),
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
                  'Автор: ${deletedName(data.owner)}',
                  'Author: ${deletedName(data.owner)}', ky: 'Автор: ${deletedName(data.owner)}', uz: 'Muallif: ${deletedName(data.owner)}'),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: YFont.body)),
          Text(
              [
                if (d.publisherRole == PublisherRole.contractor)
                  tr3('施工方发布，非房屋所有人', 'Мердігер жариялаған',
                      'Размещено подрядчиком',
                      'Posted by a contractor', ky: 'Подрядчы жарыялаган', uz: 'Pudratchi eʼlon qilgan'),
              ].join(' · '),
              style: TextStyle(color: t.muted, fontSize: YFont.small)),
        ])),
      ]),
      const Divider(height: 36),
      if (v.description.isNotEmpty) ...[
        Text(v.description,
            style: const TextStyle(fontSize: YFont.body, height: 1.5)),
        const SizedBox(height: 12),
      ],
      InfoRow(tr3('工种', 'Мамандық', 'Специальность', 'Trade', ky: 'Кесип', uz: 'Kasb'),
          v.trades.map(tradeName).join(listSep),
          icon: Icons.handyman_outlined),
      InfoRow(tr3('开工', 'Басталуы', 'Начало', 'Start', ky: 'Башталышы', uz: 'Boshlanishi'), fmtDay(v.startDate),
          icon: Icons.event_outlined),
      if (v.durationDays != null)
        InfoRow(tr3('预计天数', 'Күн саны', 'Срок, дней', 'Duration, days', ky: 'Мөөнөтү, күн', uz: 'Muddati, kun'), '${v.durationDays}',
            icon: Icons.timelapse_outlined),
      InfoRow(tr3('预算', 'Бюджет', 'Бюджет', 'Budget', ky: 'Бюджет', uz: 'Byudjet'),
          '${budgetText(v.budget)} · ${materialName(v.budget.materials)}',
          icon: Icons.payments_outlined),
      if (v.photoCount > 0)
        InfoRow(tr3('现场照片', 'Фото', 'Фото', 'Photos', ky: 'Сүрөттөр', uz: 'Rasmlar'), '${v.photoCount}',
            icon: Icons.photo_library_outlined),
      if (v.siteNotes.isNotEmpty)
        InfoRow(tr3('现场限制', 'Орын шектеулері', 'Ограничения', 'Restrictions', ky: 'Чектөөлөр', uz: 'Cheklovlar'), v.siteNotes,
            icon: Icons.warning_amber_outlined),
      if (mine && v.exactAddress.isNotEmpty)
        InfoRow(
            tr3('具体地址（仅自己可见）', 'Мекенжай (тек сізге)',
                'Адрес (видите только вы)',
                'Address (only you see it)', ky: 'Дарек (сиз гана көрөсүз)', uz: 'Manzil (faqat siz koʻrasiz)'),
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
          'Платформа не требует залогов от рабочих. Гарантии оплаты нет — платите по соглашению.',
          "The platform doesn't require deposits from workers. Payment isn't guaranteed; pay as agreed.", ky: 'Платформа жумушчулардан алдын ала төлөм талап кылбайт. Төлөмгө кепилдик жок; макулдашуу боюнча төлөңүз.', uz: 'Platforma ishchilardan oldindan toʻlov talab qilmaydi. Toʻlov kafolatlanmaydi; kelishuvga koʻra toʻlang.')),
      if (mine) ..._ownerPanel(context),
      if (!mine && data.coops.isNotEmpty) ...[
        SectionTitle(tr3('我的合作', 'Менің келісімдерім', 'Моё сотрудничество', 'My cooperation', ky: 'Менин кызматташуум', uz: 'Mening hamkorligim')),
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
              'Өтінімімді көру', 'Мой отклик', 'My response', ky: 'Менин жообум', uz: 'Mening javobim')
          : d.type == DemandType.hire
              ? tr3('报名', 'Өтінім беру', 'Откликнуться', 'Respond', ky: 'Жооп берүү', uz: 'Javob berish')
              : tr3('报价', 'Баға ұсыну', 'Предложить цену', 'Quote a price', ky: 'Баа сунуштоо', uz: 'Narx taklif qilish');
      bottom = Row(children: [
        Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Two lines, so "waiting for offers" is never cut beside
              // the button.
              Text(budgetText(v.budget),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: YFont.body,
                      height: 1.2,
                      fontFeatures: YText.tabular)),
              Text(
                  accepting
                      ? (d.expiresAt == null
                          ? ''
                          : tr3(
                              '${fmtDay(d.expiresAt)} 截止',
                              '${fmtDay(d.expiresAt)} дейін',
                              'до ${fmtDay(d.expiresAt)}',
                              'until ${fmtDay(d.expiresAt)}', ky: '${fmtDay(d.expiresAt)} чейин', uz: '${fmtDay(d.expiresAt)} gacha'))
                      : tr3('暂不接收新申请', 'Жаңа өтінім қабылданбайды',
                          'Отклики не принимаются',
                          'Not accepting responses', ky: 'Жооп кабыл алынбайт', uz: 'Javoblar qabul qilinmaydi'),
                  style: TextStyle(color: t.muted, fontSize: YFont.caption)),
            ])),
        IconButton(
            tooltip: tr3('联系发布者', 'Жариялаушыға жазу', 'Написать автору', 'Message the author', ky: 'Авторго жазуу', uz: 'Muallifga yozish'),
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
              tooltip: tr3('分享', 'Бөлісу', 'Поделиться', 'Share', ky: 'Бөлүшүү', uz: 'Ulashish'),
              icon: const YusalIcon(YIcon.share),
              onPressed: () =>
                  pushPage<void>(context, (_) => SharePage(demand: d))),
          if (!mine)
            PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'report') {
                    await reportContent(context, ReportTarget.demand, d.id);
                  }
                  if (value == 'block' && context.mounted) {
                    if (await requireLogin(context) && context.mounted) {
                      await attempt(
                          context,
                          () => context
                              .read(chatRepositoryProvider)
                              .block(d.ownerId),
                          success: tr3('已拉黑，不再看到对方内容', 'Бұғатталды',
                              'Пользователь заблокирован',
                              'User blocked', ky: 'Колдонуучу бөгөттөлгөн', uz: 'Foydalanuvchi bloklangan'));
                    }
                  }
                },
                itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'report',
                          child: Text(tr3('举报', 'Шағым', 'Пожаловаться', 'Report', ky: 'Арыз берүү', uz: 'Shikoyat qilish'))),
                      PopupMenuItem(
                          value: 'block',
                          child: Text(tr3(
                              '拉黑发布者', 'Бұғаттау', 'Заблокировать автора', 'Block the author', ky: 'Авторду бөгөттөө', uz: 'Muallifni bloklash'))),
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
        SectionTitle(tr3('招工条件', 'Жалдау шарттары', 'Условия найма', 'Hiring terms', ky: 'Жалдоо шарттары', uz: 'Yollash shartlari')),
        InfoRow(tr3('人数', 'Адам саны', 'Человек', 'People', ky: 'Адамдар', uz: 'Odamlar'), '${h.headcount}'),
        InfoRow(tr3('计酬方式', 'Төлем түрі', 'Оплата', 'Pay', ky: 'Акы', uz: 'Haq'), payModeName(h.payMode)),
        InfoRow(
            tr3('工资', 'Жалақы', 'Ставка', 'Rate', ky: 'Акы', uz: 'Stavka'),
            h.wage == null
                ? tr3('面议', 'Келісіледі', 'Договорная', 'Negotiable', ky: 'Келишим боюнча', uz: 'Kelishiladi')
                : money(h.wage, unit: h.wageUnit)),
        if (h.days != null) InfoRow(tr3('工作天数', 'Күн', 'Дней', 'Days', ky: 'Күн', uz: 'Kun'), '${h.days}'),
        InfoRow(
            tr3('食宿', 'Тамақ, жатын орын', 'Питание и жильё', 'Meals and lodging', ky: 'Тамак жана жатакана', uz: 'Ovqat va turar joy'),
            h.foodLodging
                ? tr3('提供', 'Бар', 'Есть', 'Yes', ky: 'Ооба', uz: 'Ha')
                : tr3('不提供', 'Жоқ', 'Нет', 'No', ky: 'Жок', uz: 'Yoʻq')),
        InfoRow(
            tr3('工具', 'Құрал', 'Инструмент', 'Tools', ky: 'Аспаптар', uz: 'Asboblar'),
            h.toolsByEmployer
                ? tr3('雇主提供', 'Жұмыс беруші', 'Даёт работодатель', 'Provided by the employer', ky: 'Иш берүүчү берет', uz: 'Ish beruvchi beradi')
                : tr3('自带', 'Өзінікі', 'Свой', 'Own', ky: 'Өзүнүкү', uz: 'Oʻziniki')),
        InfoRow(tr3('结算', 'Есеп айырысу', 'Расчёт', 'Settlement', ky: 'Эсептешүү', uz: 'Hisob-kitob'), settleName(h.settleCycle)),
      ];

  List<Widget> _contract(BuildContext context, ContractTerms c) => [
        SectionTitle(tr3('承包范围', 'Мердігерлік көлемі', 'Объём подряда', 'Contract scope', ky: 'Келишимдин көлөмү', uz: 'Shartnoma hajmi')),
        InfoRow(tr3('范围', 'Көлемі', 'Объём', 'Scope', ky: 'Иштин көлөмү', uz: 'Ish hajmi'),
            '${scopeKindName(c.scopeKind)}${c.stages.isEmpty ? '' : ' · ${c.stages.map(stageLabel).join(listSep)}'}'),
        InfoRow(tr3('人工／材料', 'Жұмыс / материал', 'Работа / материалы', 'Labour / materials', ky: 'Жумуш / материалдар', uz: 'Ish / materiallar'),
            materialName(c.materials)),
        if (c.targetDays != null)
          InfoRow(
              tr3('目标工期', 'Мерзім', 'Срок', 'Duration', ky: 'Мөөнөтү', uz: 'Muddati'),
              tr3('${c.targetDays} 天', '${c.targetDays} күн',
                  '${c.targetDays} дн.',
                  '${c.targetDays} d', ky: '${c.targetDays} к', uz: '${c.targetDays} k')),
        if (c.quoteDeadline != null)
          InfoRow(tr3('报价截止', 'Ұсыныс мерзімі', 'Приём цен до', 'Quotes accepted until', ky: 'Сунуштар кабыл алынат', uz: 'Takliflar qabul qilinadi'),
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
      SectionTitle(tr3('设计附件', 'Жоба тіркемесі', 'Проект', 'Design', ky: 'Долбоор', uz: 'Loyiha')),
      YCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.projectName,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: YFont.body)),
        const SizedBox(height: 4),
        Text(s.summary, style: TextStyle(color: t.muted)),
        const SizedBox(height: 4),
        Text(
            tr3(
                '固定版本：提取于 ${fmtDay(s.extractedAt)}，设计后续修改不会改变此附件。',
                'Бекітілген нұсқа: ${fmtDay(s.extractedAt)}. Кейінгі өзгерістер әсер етпейді.',
                'Зафиксировано ${fmtDay(s.extractedAt)}; дальнейшие правки проекта не меняют вложение.',
                "Captured ${fmtDay(s.extractedAt)}; later design edits don't change the attachment.", ky: '${fmtDay(s.extractedAt)} алынды; долбоордогу кийинки өзгөртүүлөр тиркемени өзгөртпөйт.', uz: '${fmtDay(s.extractedAt)} olindi; loyihadagi keyingi oʻzgarishlar ilovani oʻzgartirmaydi.'),
            style: TextStyle(color: t.muted, fontSize: YFont.caption)),
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
                      'Объёмы не опубликованы',
                      'Quantities not published', ky: 'Көлөмдөр жарыяланган эмес', uz: 'Miqdorlar eʼlon qilinmagan'),
                  style: TextStyle(color: t.muted))),
        if (mine)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  '${tr3('公开', 'Жария', 'Публично', 'Public', ky: 'Ачык', uz: 'Ommaviy')}: ${[
                    if (vis.quantities) tr3('工程量', 'көлем', 'объёмы', 'quantities', ky: 'көлөмдөр', uz: 'miqdorlar'),
                    if (vis.plan) tr3('平面图', 'жоспар', 'план', 'plan', ky: 'план', uz: 'reja'),
                    if (vis.render) tr3('效果图', 'көрініс', 'визуализация', 'rendering', ky: 'сүрөт', uz: 'tasvir'),
                  ].join(listSep)}. ${tr3('完整 .house 文件不公开。', '.house файлы жарияланбайды.', 'Файл .house не публикуется.', "The .house file isn't published.", ky: '.house файлы жарыяланбайт.', uz: '.house fayli eʼlon qilinmaydi.')}',
                  style: TextStyle(color: t.muted, fontSize: YFont.caption))),
      ])),
    ];
  }

  List<Widget> _ownerPanel(BuildContext context) {
    final t = YTokens.of(context);
    final hired = hiredCount(data.coops);
    final h = d.current.hire;
    Future<void> act(Future<Object?> Function() f, String done) =>
        attempt(context, f, success: done);
    // The buttons are the events the demand's status allows, the same
    // ones voice is offered.
    bool can(DemandEvent e) => demandButton(d.status, e);
    return [
      SectionTitle(tr3('管理需求', 'Басқару', 'Управление', 'Manage', ky: 'Башкаруу', uz: 'Boshqarish')),
      if (h != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Hint(
                tr3(
                    '已录用 $hired / 计划 ${h.headcount} 人。录用不会自动关闭需求，人数够了可以标记“已找到人”。',
                    'Жалданды $hired / ${h.headcount}. Тапсырыс өзі жабылмайды.',
                    'Нанято $hired из ${h.headcount}. Заявка не закрывается сама.',
                    "Hired $hired of ${h.headcount}. The request doesn't close by itself.", ky: '${h.headcount} ичинен $hired жалданды. Суроо-талап өзүнөн өзү жабылбайт.', uz: '${h.headcount} dan $hired yollandi. Soʻrov oʻz-oʻzidan yopilmaydi.'),
                warn: hired >= h.headcount && d.status == DemandStatus.open)),
      if (d.expiresAt != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                tr3(
                    '有效期至 ${fmtDay(d.expiresAt)}',
                    '${fmtDay(d.expiresAt)} дейін',
                    'Действует до ${fmtDay(d.expiresAt)}',
                    'Valid until ${fmtDay(d.expiresAt)}', ky: '${fmtDay(d.expiresAt)} чейин жарактуу', uz: '${fmtDay(d.expiresAt)} gacha amal qiladi'),
                style: TextStyle(color: t.muted))),
      if (d.outcome != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                '${tr3('结果', 'Нәтиже', 'Итог', 'Outcome', ky: 'Жыйынтык', uz: 'Natija')}: ${outcomeName(d.outcome!)}',
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
                            'Отклики (${data.applicationCount})',
                            'Responses (${data.applicationCount})', ky: 'Жооптор (${data.applicationCount})', uz: 'Javoblar (${data.applicationCount})')
                        : tr3(
                            '报价管理与对比（${data.applicationCount}）',
                            'Ұсыныстар (${data.applicationCount})',
                            'Предложения (${data.applicationCount})',
                            'Quotes (${data.applicationCount})', ky: 'Сунуштар (${data.applicationCount})', uz: 'Takliflar (${data.applicationCount})'),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right),
          ])),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (can(DemandEvent.publish))
          FilledButton(
              onPressed: () => act(
                  () => context.read(demandRepositoryProvider).publish(d.id),
                  tr3('已提交审核', 'Тексеруге жіберілді',
                      'Отправлено на проверку',
                      'Sent for review', ky: 'Текшерүүгө жөнөтүлдү', uz: 'Tekshiruvga yuborildi')),
              child: Text(tr3('提交审核', 'Тексеруге жіберу', 'На проверку', 'Send for review', ky: 'Текшерүүгө жөнөтүү', uz: 'Tekshiruvga yuborish'))),
        if (d.status != DemandStatus.closed)
          OutlinedButton(
              onPressed: () =>
                  pushPage<void>(context, (_) => PublishPage(editing: d)),
              child: Text(tr3('修改（生成新版本）', 'Өзгерту', 'Изменить', 'Edit', ky: 'Түзөтүү', uz: 'Tahrirlash'))),
        if (can(DemandEvent.pause))
          OutlinedButton(
              onPressed: () => act(
                  () => context.read(demandRepositoryProvider).pause(d.id),
                  tr3('已暂停', 'Тоқтатылды', 'Приостановлено', 'Paused', ky: 'Тындырылды', uz: 'Toʻxtatildi')),
              child: Text(tr3('暂停', 'Тоқтату', 'Пауза', 'Pause', ky: 'Тындыруу', uz: 'Toʻxtatish'))),
        if (can(DemandEvent.resume))
          OutlinedButton(
              onPressed: () => act(
                  () => context.read(demandRepositoryProvider).resume(d.id),
                  tr3('继续招募', 'Жалғасты', 'Набор возобновлён', 'Hiring resumed', ky: 'Жалдоо уланды', uz: 'Yollash davom ettirildi')),
              child: Text(tr3('继续招募', 'Жалғастыру', 'Возобновить', 'Resume', ky: 'Улантуу', uz: 'Davom ettirish'))),
        if (can(DemandEvent.renew))
          OutlinedButton(
              onPressed: () => act(
                  () => context.read(demandRepositoryProvider).renew(d.id),
                  tr3('已续期 30 天', '30 күнге ұзартылды', 'Продлено на 30 дней', 'Extended by 30 days', ky: '30 күнгө узартылды', uz: '30 kunga uzaytirildi')),
              child: Text(tr3('续期', 'Ұзарту', 'Продлить', 'Extend', ky: 'Узартуу', uz: 'Uzaytirish'))),
        if (can(DemandEvent.markFound))
          OutlinedButton(
              onPressed: () async {
                final o = await pickOutcome(context, hired > 0);
                if (o != null && context.mounted) {
                  await act(
                      () => context
                          .read(demandRepositoryProvider)
                          .markFound(d.id, o),
                      tr3('已标记找到人，停止接收新申请', 'Белгіленді', 'Отмечено', 'Marked', ky: 'Белгиленди', uz: 'Belgilandi'));
                }
              },
              child: Text(tr3('已找到人', 'Адам табылды', 'Исполнитель найден', 'Someone was found', ky: 'Адам табылды', uz: 'Odam topildi'))),
        if (can(DemandEvent.close))
          OutlinedButton(
              onPressed: () async {
                final reason = await askText(
                    context, tr3('关闭需求', 'Жабу', 'Закрыть заявку', 'Close the request', ky: 'Суроо-талапты жабуу', uz: 'Soʻrovni yopish'),
                    hint: tr3('原因，例如不再需要', 'Себебі', 'Причина', 'Reason', ky: 'Себеби', uz: 'Sababi'));
                if (reason != null && context.mounted) {
                  await act(
                      () => context
                          .read(demandRepositoryProvider)
                          .close(d.id, reason),
                      tr3('已关闭', 'Жабылды', 'Закрыто', 'Closed', ky: 'Жабылды', uz: 'Yopildi'));
                }
              },
              child: Text(tr3('关闭', 'Жабу', 'Закрыть', 'Close', ky: 'Жабуу', uz: 'Yopish'))),
        if (d.outcome == null && d.status != DemandStatus.draft)
          TextButton(
              onPressed: () async {
                final o = await pickOutcome(context, hired > 0);
                if (o != null && context.mounted) {
                  await act(
                      () => context
                          .read(demandRepositoryProvider)
                          .recordOutcome(d.id, o),
                      tr3('谢谢反馈', 'Рақмет', 'Спасибо', 'Thank you', ky: 'Рахмат', uz: 'Rahmat'));
                }
              },
              child: Text(tr3('回答结果回访', 'Нәтижені айту', 'Ответить на опрос', 'Answer the survey', ky: 'Сурамжылоого жооп берүү', uz: 'Soʻrovnomaga javob berish'))),
      ]),
    ];
  }
}

Future<OutcomeKind?> pickOutcome(BuildContext context, bool hasCoop) =>
    pickOne<OutcomeKind>(
        context, tr3('找到合适的人了吗？', 'Адам таптыңыз ба?', 'Нашли исполнителя?', 'Did you find someone?', ky: 'Адам таптыңызбы?', uz: 'Odam topdingizmi?'), [
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
    return DecoratedBox(
        decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(YRadius.control)),
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
                            style: TextStyle(
                                color: t.muted, fontSize: YFont.caption)),
                      ])),
                  Text(
                      l.quantity == null
                          ? tr3('现场测量', 'Орында', 'Замер', 'Site measure', ky: 'Объектиде өлчөө', uz: 'Obyektda oʻlchash')
                          : '${numText(l.quantity!)} ${unitLabel(l.unit)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ])),
        ]));
  }
}

/// Opens a cooperation page; several pages share it.
void openCooperation(BuildContext context, String id) =>
    pushPage<void>(context, (_) => CooperationPage(cooperationId: id));
