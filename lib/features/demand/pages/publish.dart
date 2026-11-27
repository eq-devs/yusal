import 'package:flutter/material.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';
import 'package:yusal/features/demand/widgets/demand_card.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/shared/ui/unsaved_changes_guard.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/model/form.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Publish wizard for both demand types: type → work → time and budget →
/// attachments and privacy → preview. Also edits a published demand, which
/// creates a new version.
class PublishPage extends StatefulWidget {
  const PublishPage(
      {super.key, this.editing, this.snapshot, this.designProjectId});
  final Demand? editing;

  /// Design extract when publishing from a design; makes it a contract
  /// demand with the extracted quantities.
  final DesignSnapshot? snapshot;
  final String? designProjectId;
  @override
  State<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> with VoiceScreen {
  @override
  String get screenId => 'demand.publish';

  /// The inputs of every step and of both types, so one sentence can set
  /// the type together with its fields. The controllers keep what is
  /// filled while the user moves between steps and reviews it.
  @override
  List<VoiceField> get fields => [
        VoiceField.choice(
            'type',
            const L3('类型', 'Түрі', 'Тип', 'Type', ky: 'Түрү', uz: 'Turi'),
            [for (final t in DemandType.values) t.name],
            (v) => setState(() => type = DemandType.values.byName(v))),
        VoiceField(
            'title', const L3('标题', 'Тақырып', 'Заголовок', 'Title', ky: 'Аталышы', uz: 'Sarlavha'), FieldType.text,
            (v) {
          titleTouched = true;
          title.text = v as String;
        }),
        VoiceField.text(
            'locality',
            const L3('村镇／街区', 'Ауыл / аудан', 'Посёлок / микрорайон', 'Village / neighbourhood', ky: 'Айыл / кичи район', uz: 'Qishloq / mahalla'),
            locality),
        VoiceField.text('address',
            const L3('具体地址', 'Нақты мекенжай', 'Точный адрес', 'Exact address', ky: 'Так дарек', uz: 'Aniq manzil'), address),
        VoiceField.text('description', const L3('说明', 'Сипаттама', 'Описание', 'Description', ky: 'Сүрөттөмө', uz: 'Tavsif'),
            description),
        VoiceField.number('headcount',
            const L3('需要人数', 'Адам саны', 'Сколько человек', 'How many people', ky: 'Канча адам', uz: 'Necha kishi'), headcount),
        VoiceField.number('wage', const L3('工资', 'Жалақы', 'Ставка', 'Rate', ky: 'Акы', uz: 'Stavka'), wage),
        VoiceField.number('days', const L3('预计工作天数', 'Күн саны', 'Дней', 'Days', ky: 'Күн', uz: 'Kun'), days),
        VoiceField.number('target_days',
            const L3('目标工期（天）', 'Мерзім (күн)', 'Срок (дней)', 'Duration (days)', ky: 'Мөөнөтү (күн)', uz: 'Muddati (kun)'), targetDays),
      ];

  @override
  Future<void> Function()? get voiceSubmit => submit;

  int step = 0;
  DemandType type = DemandType.contract;
  PublisherRole role = PublisherRole.owner;
  final title = TextEditingController();
  final locality = TextEditingController();
  final address = TextEditingController();
  final description = TextEditingController();
  final siteNotes = TextEditingController();
  final headcount = TextEditingController(text: '1');
  final wage = TextEditingController();
  final days = TextEditingController();
  final duration = TextEditingController();
  final targetDays = TextEditingController();
  final budgetMin = TextEditingController();
  final budgetMax = TextEditingController();
  final budgetAmount = TextEditingController();
  bool titleTouched = false;
  List<String> trades = [];
  String? region;
  int photos = 0;
  PayMode payMode = PayMode.daily;
  bool wageNegotiable = false;
  String wageUnit = 'day';
  bool food = false;
  bool tools = false;
  String settle = 'weekly';
  ScopeKind scopeKind = ScopeKind.custom;
  List<String> stages = [];
  List<QtyItem> quantities = [];
  MaterialMode materials = MaterialMode.labourOnly;
  DateTime? quoteDeadline;
  DateTime? startDate;
  BudgetMode budgetMode = BudgetMode.askQuote;
  String budgetBasis = 'total';
  AttachmentVisibility visibility = const AttachmentVisibility();
  String? error;

  bool get editing => widget.editing != null;
  bool get fromDesign => widget.snapshot != null || _snapshotId != null;
  String? _snapshotId;
  late String _initialDraft;
  bool _busy = false;
  List<TextEditingController> get _controllers => [
        title,
        locality,
        address,
        description,
        siteNotes,
        headcount,
        wage,
        days,
        duration,
        targetDays,
        budgetMin,
        budgetMax,
        budgetAmount
      ];
  String get _draft => [
        for (final c in _controllers) c.text,
        type,
        role,
        trades.join(','),
        region,
        photos,
        payMode,
        wageNegotiable,
        wageUnit,
        food,
        tools,
        settle,
        scopeKind,
        stages.join(','),
        quantities.map((q) => '${q.name}:${q.quantity}:${q.unit}').join('|'),
        materials,
        quoteDeadline,
        startDate,
        budgetMode,
        budgetBasis,
        visibility.quantities,
        visibility.plan,
        visibility.render
      ].join('\u0000');

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final d = widget.editing;
    final s = widget.snapshot;
    if (d != null) {
      final v = d.current;
      type = d.type;
      role = d.publisherRole;
      title.text = v.title;
      titleTouched = true;
      locality.text = v.locality;
      address.text = v.exactAddress;
      description.text = v.description;
      siteNotes.text = v.siteNotes;
      trades = [...v.trades];
      region = v.region;
      photos = v.photoCount;
      startDate = v.startDate;
      duration.text = v.durationDays?.toString() ?? '';
      budgetMode = v.budget.mode;
      budgetBasis = v.budget.basis;
      budgetMin.text = v.budget.min?.toString() ?? '';
      budgetMax.text = v.budget.max?.toString() ?? '';
      budgetAmount.text = v.budget.amount?.toString() ?? '';
      materials = v.budget.materials;
      visibility = v.visibility;
      _snapshotId = v.snapshotId;
      final h = v.hire;
      if (h != null) {
        headcount.text = '${h.headcount}';
        payMode = h.payMode;
        wageNegotiable = h.wage == null;
        wage.text = h.wage?.toString() ?? '';
        wageUnit = h.wageUnit;
        days.text = h.days?.toString() ?? '';
        food = h.foodLodging;
        tools = h.toolsByEmployer;
        settle = h.settleCycle;
      }
      final c = v.contract;
      if (c != null) {
        scopeKind = c.scopeKind;
        stages = [...c.stages];
        quantities = [...c.quantities];
        materials = c.materials;
        targetDays.text = c.targetDays?.toString() ?? '';
        quoteDeadline = c.quoteDeadline;
      }
      step = 1;
    } else if (s != null) {
      type = DemandType.contract;
      scopeKind = s.stages.length == 7 ? ScopeKind.whole : ScopeKind.stages;
      stages = [...s.stages];
      quantities = [...s.lines];
      trades = _tradesFor(s.stages);
      description.text = s.summary;
      step = 1;
    }
    _initialDraft = _draft;
  }

  static List<String> _tradesFor(List<String> stages) => {
        for (final s in stages)
          ...switch (s) {
            'found' => ['concrete', 'rebar'],
            'walls' => ['mason'],
            'roof' => ['roofer', 'carpenter'],
            'mep' => ['electrician', 'plumber'],
            'finish' => ['plasterer', 'tiler'],
            'openings' => ['carpenter'],
            _ => ['general'],
          }
      }.toList();

  String suggestedTitle() => autoTitle(
      type: type,
      tradeName: trades.isEmpty ? '' : tradeName(trades.first),
      regionName: region == null ? '' : regionName(region!),
      headcount: int.tryParse(headcount.text),
      scope: type == DemandType.contract && stages.isNotEmpty
          ? stages.map(stageLabel).join(listSep)
          : null);

  String? validate(int s) {
    if (s == 1) {
      if (trades.isEmpty) {
        return tr3('请选择工种', 'Мамандықты таңдаңыз', 'Выберите специальность', 'Choose a trade', ky: 'Кесип тандаңыз', uz: 'Kasb tanlang');
      }
      if (region == null) {
        return tr3('请选择地区', 'Аймақты таңдаңыз', 'Выберите район', 'Choose a district', ky: 'Район тандаңыз', uz: 'Tuman tanlang');
      }
      if (title.text.trim().isEmpty) {
        return tr3('请填写标题', 'Тақырып жазыңыз', 'Введите заголовок', 'Enter a title', ky: 'Аталышын киргизиңиз', uz: 'Sarlavha kiriting');
      }
      if (type == DemandType.hire) {
        if ((parseInt(headcount.text) ?? 0) < 1) {
          return tr3('人数至少 1 人', 'Кемінде 1 адам', 'Минимум 1 человек', 'At least 1 person', ky: 'Кеминде 1 адам', uz: 'Kamida 1 kishi');
        }
        if (!wageNegotiable && (parseInt(wage.text) ?? 0) <= 0) {
          return tr3('请填写工资，或选择面议', 'Жалақыны жазыңыз не «келісіледі»',
              'Укажите ставку или «договорная»',
              'Enter a rate or “negotiable”', ky: 'Акыны же «келишим боюнча» дегенди киргизиңиз', uz: 'Haqni yoki “kelishiladi” ni kiriting');
        }
      } else if (scopeKind == ScopeKind.stages && stages.isEmpty) {
        return tr3('请选择施工阶段', 'Кезеңді таңдаңыз', 'Выберите этапы', 'Choose stages', ky: 'Этаптарды тандаңыз', uz: 'Bosqichlarni tanlang');
      }
    }
    if (s == 2) {
      switch (budgetMode) {
        case BudgetMode.fixed:
          if ((parseInt(budgetAmount.text) ?? 0) <= 0) {
            return tr3('请填写金额，或选择“请报价”', 'Соманы жазыңыз',
                'Укажите сумму или «ждём предложений»',
                'Enter an amount or “waiting for quotes”', ky: 'Сумманы же «сунуштарды күтөм» дегенди киргизиңиз', uz: 'Summani yoki “takliflarni kutaman” ni kiriting');
          }
        case BudgetMode.range:
          final a = parseInt(budgetMin.text) ?? 0;
          final b = parseInt(budgetMax.text) ?? 0;
          if (a <= 0 || b < a) {
            return tr3('区间不正确', 'Аралық қате', 'Неверный диапазон', 'Invalid range', ky: 'Аралык туура эмес', uz: 'Oraliq notoʻgʻri');
          }
        case BudgetMode.askQuote:
          break;
      }
    }
    return null;
  }

  DemandVersion compose() {
    int? n(TextEditingController c) => parseInt(c.text);
    return DemandVersion(
        no: 0,
        title: title.text.trim(),
        trades: trades,
        region: region ?? '',
        locality: locality.text,
        exactAddress: address.text,
        budget: Budget(
            mode: budgetMode,
            min: budgetMode == BudgetMode.range ? n(budgetMin) : null,
            max: budgetMode == BudgetMode.range ? n(budgetMax) : null,
            amount: budgetMode == BudgetMode.fixed ? n(budgetAmount) : null,
            basis: budgetBasis,
            materials: type == DemandType.contract
                ? materials
                : MaterialMode.labourOnly),
        createdAt: DateTime.now(),
        startDate: startDate,
        durationDays: n(duration),
        description: description.text,
        siteNotes: siteNotes.text,
        photoCount: photos,
        hire: type == DemandType.hire
            ? HireTerms(
                headcount: n(headcount) ?? 1,
                payMode: payMode,
                wage: wageNegotiable ? null : n(wage),
                wageUnit: wageUnit,
                days: n(days),
                foodLodging: food,
                toolsByEmployer: tools,
                settleCycle: settle)
            : null,
        contract: type == DemandType.contract
            ? ContractTerms(
                scopeKind: scopeKind,
                stages: scopeKind == ScopeKind.custom ? const [] : stages,
                quantities: quantities,
                materials: materials,
                targetDays: n(targetDays),
                quoteDeadline: quoteDeadline)
            : null,
        snapshotId: _snapshotId,
        visibility: visibility);
  }

  Future<void> submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _submit();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final snapshots = context.read(snapshotRepositoryProvider);
    final demands = context.read(demandRepositoryProvider);
    final result = await attempt(context, () async {
      if (widget.snapshot != null && _snapshotId == null) {
        _snapshotId = (await snapshots.saveSnapshot(widget.snapshot!)).id;
      }
      final d = widget.editing;
      if (d == null) {
        final draft = await demands.saveDraft(type, compose(),
            role: role, designProjectId: widget.designProjectId);
        return demands.publish(draft.id);
      }
      if (d.status == DemandStatus.draft) {
        await demands.saveDraft(type, compose(), existingId: d.id);
        return demands.publish(d.id);
      }
      return demands.revise(d.id, compose());
    });
    if (result == null || !mounted) return;
    toast(
        context,
        switch (result.status) {
          DemandStatus.open => tr3('已发布，正在招募', 'Жарияланды', 'Опубликовано', 'Published', ky: 'Жарыяланды', uz: 'Eʼlon qilindi'),
          DemandStatus.rejected =>
            tr3('审核未通过，请查看原因', 'Қабылданбады', 'Не прошло проверку', "Didn't pass review", ky: 'Текшерүүдөн өткөн жок', uz: 'Tekshiruvdan oʻtmadi'),
          _ => tr3(
              '已提交审核，通过后自动公开', 'Тексеруге жіберілді', 'Отправлено на проверку', 'Sent for review', ky: 'Текшерүүгө жөнөтүлдү', uz: 'Tekshiruvga yuborildi'),
        });
    Navigator.pop(context);
    if (!editing) {
      await pushPage<void>(
          context, (_) => DemandDetailPage(demandId: result.id));
    }
  }

  Future<void> saveDraftOnly() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _saveDraftOnly();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraftOnly() async {
    final snapshots = context.read(snapshotRepositoryProvider);
    final demands = context.read(demandRepositoryProvider);
    final d = await attempt(context, () async {
      if (widget.snapshot != null && _snapshotId == null) {
        _snapshotId = (await snapshots.saveSnapshot(widget.snapshot!)).id;
      }
      return demands.saveDraft(type, compose(),
          role: role, designProjectId: widget.designProjectId);
    }, success: tr3('草稿已保存，仅自己可见', 'Жоба сақталды', 'Черновик сохранён', 'Draft saved', ky: 'Долбоор сакталды', uz: 'Qoralama saqlandi'));
    if (d != null && mounted) Navigator.pop(context);
  }

  void next() {
    final problem = validate(step);
    setState(() => error = problem);
    if (problem != null) return;
    if (step == 1 && !titleTouched) title.text = suggestedTitle();
    setState(() => step++);
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final t = YTokens.of(context);
    const last = 4;
    final pages = [
      _typeStep,
      _workStep,
      _budgetStep,
      _privacyStep,
      _previewStep
    ];
    return UnsavedChangesGuard(
        hasChanges: () => _draft != _initialDraft,
        isBusy: () => _busy,
        changes: Listenable.merge(_controllers),
        child: Scaffold(
            appBar: AppBar(
                title: Text(editing
                    ? tr3('修改需求', 'Тапсырысты өзгерту', 'Изменить заявку', 'Edit the request', ky: 'Суроо-талапты түзөтүү', uz: 'Soʻrovni tahrirlash')
                    : fromDesign
                        ? tr3('从设计发布', 'Жобадан жариялау', 'Из проекта', 'From a design', ky: 'Долбоордон', uz: 'Loyihadan')
                        : tr3('发布需求', 'Тапсырыс беру', 'Новая заявка', 'New request', ky: 'Жаңы суроо-талап', uz: 'Yangi soʻrov')),
                actions: [
                  if (!editing && step > 0)
                    TextButton(
                        onPressed: saveDraftOnly,
                        child: Text(tr3('存草稿', 'Сақтау', 'Черновик', 'Draft', ky: 'Черновик', uz: 'Qoralama'))),
                ],
                bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(4),
                    child: LinearProgressIndicator(
                        value: (step + 1) / (last + 1),
                        minHeight: 4,
                        backgroundColor: t.line,
                        color: t.ink))),
            body: SafeArea(
                top: false,
                child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                            children: [
                              pages[step](context),
                              if (error != null) ...[
                                const SizedBox(height: 14),
                                Hint(error!, warn: true),
                              ],
                            ])))),
            bottomNavigationBar: ActionBar(
                child: Row(children: [
              if (step > (editing || widget.snapshot != null ? 1 : 0))
                TextButton(
                    onPressed: () => setState(() {
                          error = null;
                          step--;
                        }),
                    child: Text(tr3('返回', 'Артқа', 'Назад', 'Back', ky: 'Артка', uz: 'Orqaga'))),
              const Spacer(),
              if (step < last)
                FilledButton(
                    onPressed: next, child: Text(tr3('下一步', 'Келесі', 'Далее', 'Next', ky: 'Кийинки', uz: 'Keyingi')))
              else
                BusyButton(
                    expand: false,
                    label:
                        editing && widget.editing!.status != DemandStatus.draft
                            ? tr3('发布新版本', 'Жаңа нұсқа', 'Опубликовать версию', 'Publish version', ky: 'Версияны жарыялоо', uz: 'Versiyani eʼlon qilish')
                            : tr3('提交发布', 'Жариялау', 'Опубликовать', 'Publish', ky: 'Жарыялоо', uz: 'Eʼlon qilish'),
                    onPressed: submit),
            ]))));
  }

  Widget _heading(String text, [String? sub]) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text,
              style: const TextStyle(
                  fontSize: YFont.display, fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub, style: TextStyle(color: t.muted, height: 1.4)),
          ],
        ]));
  }

  Widget _choice(
      {required bool selected,
      required IconData icon,
      required String title,
      required String body,
      required VoidCallback onTap}) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
            color: selected ? t.surface : t.bg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(yRadius),
                side: BorderSide(
                    color: selected ? t.ink : t.line, width: selected ? 2 : 1)),
            child: InkWell(
                borderRadius: BorderRadius.circular(yRadius),
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: YFont.heading,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(body, style: TextStyle(color: t.muted)),
                          ])),
                      const SizedBox(width: 12),
                      Icon(icon, size: 32),
                    ])))));
  }

  Widget _typeStep(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(
            tr3('你想找什么样的人？', 'Кімді іздейсіз?', 'Кого вы ищете?', 'Who are you looking for?', ky: 'Кимди издеп жатасыз?', uz: 'Kimni qidiryapsiz?'),
            tr3('不需要先画图，也能发布。', 'Сызбасыз да жариялауға болады.',
                'Чертёж не обязателен.',
                "A drawing isn't required.", ky: 'Чийме милдеттүү эмес.', uz: 'Chizma shart emas.')),
        _choice(
            selected: type == DemandType.hire,
            icon: YIcons.hire,
            title: demandTypeName(DemandType.hire),
            body: tr3(
                '例如：找两名瓦工，按天结算。对方报名并说明到岗时间。',
                'Мысалы: 2 қалаушы, күнделікті төлем.',
                'Например: 2 каменщика, подённая оплата.',
                'E.g. 2 masons, paid by the day.', ky: 'Мисалы, 2 дубалчы, күнүмдүк акы.', uz: 'Masalan, 2 gʻishtchi, kunbay haq.'),
            onTap: () => setState(() => type = DemandType.hire)),
        _choice(
            selected: type == DemandType.contract,
            icon: YIcons.home,
            title: demandTypeName(DemandType.contract),
            body: tr3(
                '例如：130 平米住宅砌墙。对方说明承接范围、价格和工期。',
                'Мысалы: 130 м² үйдің қабырғасы.',
                'Например: кладка стен дома 130 м².',
                'E.g. wall masonry for a 130 m² house.', ky: 'Мисалы, 130 м² үйдүн дубалдарын тургузуу.', uz: 'Masalan, 130 m² uy devorlarini terish.'),
            onTap: () => setState(() => type = DemandType.contract)),
        const SizedBox(height: 8),
        Text(tr3('你的身份', 'Сіз кімсіз', 'Вы', 'You', ky: 'Сиз', uz: 'Siz'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilterPill(
              label: tr3('业主／房屋所有人', 'Үй иесі', 'Владелец', 'Owner', ky: 'Ээси', uz: 'Egasi'),
              selected: role == PublisherRole.owner,
              onTap: () => setState(() => role = PublisherRole.owner)),
          FilterPill(
              label: tr3('施工方（分包／补人）', 'Мердігер', 'Подрядчик (субподряд)', 'Contractor (subcontract)', ky: 'Подрядчы (субподряд)', uz: 'Pudratchi (subpudrat)'),
              selected: role == PublisherRole.contractor,
              onTap: () => setState(() => role = PublisherRole.contractor)),
        ]),
      ]);

  Widget _pickerTile(String label, String value, VoidCallback onTap) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(YRadius.control),
            child: InputDecorator(
                decoration: InputDecoration(
                    labelText: label,
                    suffixIcon: const Icon(YIcons.chevronDown)),
                child: Text(
                    value.isEmpty ? tr3('请选择', 'Таңдаңыз', 'Выберите', 'Choose', ky: 'Тандоо', uz: 'Tanlash') : value,
                    style:
                        TextStyle(color: value.isEmpty ? t.muted : t.ink)))));
  }

  Widget _field(TextEditingController c, String label,
          {String? hint,
          bool number = false,
          int lines = 1,
          ValueChanged<String>? onChanged,
          String? helper}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              minLines: lines,
              maxLines: lines == 1 ? 1 : lines + 3,
              onChanged: onChanged,
              keyboardType: number ? TextInputType.number : null,
              decoration: InputDecoration(
                  labelText: label, hintText: hint, helperText: helper)));

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: (v) => setState(() => onChanged(v)));

  Widget _workStep(BuildContext context) {
    final t = YTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(
          tr3('工作内容', 'Жұмыс', 'Работа', 'Work', ky: 'Иш', uz: 'Ish'),
          tr3(
              '公开页面只显示城市／村镇／街区；具体地址只在你授权后给合作方。',
              'Жария бетте тек елді мекен көрсетіледі.',
              'Публично виден только населённый пункт; точный адрес — по вашему решению.',
              'Only the town is public; the exact address is up to you.', ky: 'Шаар гана ачык; так даректи өзүңүз чечесиз.', uz: 'Faqat shahar ommaviy; aniq manzilni oʻzingiz hal qilasiz.')),
      _pickerTile(tr3('工种', 'Мамандық', 'Специальность', 'Trade', ky: 'Кесип', uz: 'Kasb'),
          trades.map(tradeName).join(listSep), () async {
        final v = await pickMany<String>(
            context,
            tr3('工种（可多选）', 'Мамандық', 'Специальности', 'Trades', ky: 'Кесиптер', uz: 'Kasblar'),
            [for (final c in tradeCodes) (c, tradeName(c))],
            trades);
        if (v != null) setState(() => trades = v);
      }),
      _pickerTile(tr3('地区', 'Аймақ', 'Район', 'District', ky: 'Район', uz: 'Tuman'),
          region == null ? '' : regionName(region!), () async {
        final v = await pickOne<String>(context, tr3('地区', 'Аймақ', 'Район', 'District', ky: 'Район', uz: 'Tuman'),
            [for (final c in regionCodes) (c, regionName(c))],
            selected: region);
        if (v != null) setState(() => region = v);
      }),
      _field(
          locality,
          tr3('村镇／街区（公开）', 'Ауыл / аудан (жария)',
              'Посёлок / микрорайон (публично)',
              'Village / neighbourhood (public)', ky: 'Айыл / кичи район (ачык)', uz: 'Qishloq / mahalla (ommaviy)')),
      _field(address,
          tr3('具体地址（不公开）', 'Нақты мекенжай (жасырын)', 'Точный адрес (скрыт)', 'Exact address (hidden)', ky: 'Так дарек (жашырылган)', uz: 'Aniq manzil (yashirin)'),
          helper: tr3('只在合作约定中由你选择是否告诉对方', 'Тек келісімде көрсетіледі',
              'Передаётся только по соглашению',
              'Shared only by agreement', ky: 'Макулдашуу боюнча гана бөлүшүлөт', uz: 'Faqat kelishuv boʻyicha ulashiladi')),
      if (type == DemandType.hire) ...[
        _field(headcount, tr3('需要人数', 'Адам саны', 'Сколько человек', 'How many people', ky: 'Канча адам', uz: 'Necha kishi'),
            number: true),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in PayMode.values)
            FilterPill(
                label: payModeName(p),
                selected: payMode == p,
                onTap: () => setState(() => payMode = p)),
        ]),
        const SizedBox(height: 12),
        _switch(tr3('工资面议', 'Жалақы келісіледі', 'Ставка договорная', 'Rate negotiable', ky: 'Акы келишим боюнча', uz: 'Haq kelishiladi'),
            wageNegotiable, (v) => wageNegotiable = v),
        if (!wageNegotiable)
          Row(children: [
            Expanded(
                child: _field(wage, tr3('工资（₸）', 'Жалақы (₸)', 'Ставка (₸)', 'Rate (₸)', ky: 'Акы (₸)', uz: 'Haq (₸)'),
                    number: true)),
            const SizedBox(width: 12),
            DropdownButton<String>(
                value: wageUnit,
                items: [
                  for (final u in const [
                    'day',
                    'hour',
                    'm3',
                    'm2',
                    'pcs',
                    't',
                    'total'
                  ])
                    DropdownMenuItem(
                        value: u, child: Text('/ ${unitLabel(u)}')),
                ],
                onChanged: (v) => setState(() => wageUnit = v ?? 'day')),
          ]),
        _field(days, tr3('预计工作天数（可空）', 'Күн саны', 'Дней (необязательно)', 'Days (optional)', ky: 'Күн (милдеттүү эмес)', uz: 'Kun (ixtiyoriy)'),
            number: true),
        _switch(tr3('提供食宿', 'Тамақ пен жатын орын бар', 'Питание и жильё', 'Meals and lodging', ky: 'Тамак жана жатакана', uz: 'Ovqat va turar joy'),
            food, (v) => food = v),
        _switch(
            tr3('工具由雇主提供', 'Құралды жұмыс беруші береді',
                'Инструмент от работодателя',
                'Tools from the employer', ky: 'Аспаптар иш берүүчүдөн', uz: 'Asboblar ish beruvchidan'),
            tools,
            (v) => tools = v),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in const ['daily', 'weekly', 'monthly', 'onFinish'])
            FilterPill(
                label: settleName(s),
                selected: settle == s,
                onTap: () => setState(() => settle = s)),
        ]),
        const SizedBox(height: 12),
      ] else ...[
        Text(tr3('承接范围', 'Көлемі', 'Объём работ', 'Scope of work', ky: 'Иштин көлөмү', uz: 'Ish hajmi'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in ScopeKind.values)
            FilterPill(
                label: scopeKindName(k),
                selected: scopeKind == k,
                onTap: () => setState(() => scopeKind = k)),
        ]),
        if (scopeKind == ScopeKind.stages) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in const [
              'found',
              'walls',
              'roof',
              'openings',
              'mep',
              'finish',
              'site'
            ])
              FilterPill(
                  label: stageLabel(s),
                  selected: stages.contains(s),
                  onTap: () => setState(() =>
                      stages.contains(s) ? stages.remove(s) : stages.add(s))),
          ]),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const [
            MaterialMode.labourOnly,
            MaterialMode.labourAndMaterial,
            MaterialMode.undecided
          ])
            FilterPill(
                label: materialName(m),
                selected: materials == m,
                onTap: () => setState(() => materials = m)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Text(tr3('工程量', 'Көлемдер', 'Объёмы', 'Quantities', ky: 'Көлөмдөр', uz: 'Miqdorlar'),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          TextButton.icon(
              onPressed: addQuantity,
              icon: const Icon(YIcons.add, size: 18),
              label: Text(tr3('添加', 'Қосу', 'Добавить', 'Add', ky: 'Кошуу', uz: 'Qoʻshish'))),
        ]),
        if (quantities.isEmpty)
          Text(
              tr3('未知可以不填，或注明现场测量。', 'Белгісіз болса, бос қалдырыңыз.',
                  'Можно не указывать или отметить замер.',
                  'You can leave them out or mark a site measure.', ky: 'Аларды калтырбасаңыз же объектиде өлчөө деп белгилесеңиз болот.', uz: 'Ularni qoldirmasangiz yoki obyektda oʻlchash deb belgilasangiz boʻladi.'),
              style: TextStyle(color: t.muted)),
        for (final (i, q) in quantities.indexed)
          ListTile(
              dense: true,
              title: Text(q.name),
              subtitle: Text(qtySourceName(q.source)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    q.quantity == null
                        ? tr3('现场测量', 'Орында', 'Замер', 'Site measure', ky: 'Объектиде өлчөө', uz: 'Obyektda oʻlchash')
                        : '${numText(q.quantity!)} ${unitLabel(q.unit)}',
                    style: const TextStyle(fontFeatures: YText.tabular)),
                IconButton(
                    tooltip: tr3('删除', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish'),
                    icon: const Icon(YIcons.close, size: 18),
                    onPressed: () => setState(() => quantities.removeAt(i))),
              ])),
        const SizedBox(height: 8),
        _field(targetDays, tr3('目标工期（天）', 'Мерзім (күн)', 'Срок (дней)', 'Duration (days)', ky: 'Мөөнөтү (күн)', uz: 'Muddati (kun)'),
            number: true),
        _pickerTile(tr3('报价截止日期', 'Ұсыныс мерзімі', 'Приём цен до', 'Quotes accepted until', ky: 'Сунуштар кабыл алынат', uz: 'Takliflar qabul qilinadi'),
            quoteDeadline == null ? '' : fmtDay(quoteDeadline), () async {
          final d = await showDatePicker(
              context: context,
              firstDate: context.now,
              lastDate: context.now.add(const Duration(days: 60)),
              initialDate:
                  quoteDeadline ?? context.now.add(const Duration(days: 7)));
          if (d != null) setState(() => quoteDeadline = d);
        }),
      ],
      _field(description, tr3('说明（可选）', 'Сипаттама', 'Описание', 'Description', ky: 'Сүрөттөмө', uz: 'Tavsif'), lines: 3),
      _field(siteNotes,
          tr3('现场限制（可选）', 'Орын шектеулері', 'Ограничения на объекте', 'Site restrictions', ky: 'Объекттеги чектөөлөр', uz: 'Obyektdagi cheklovlar'),
          hint: tr3(
              '例如：无电、道路窄', 'Мысалы: жарық жоқ', 'Напр.: нет электричества', 'E.g. no electricity', ky: 'Мисалы, электр жок', uz: 'Masalan, elektr yoʻq')),
      Row(children: [
        OutlinedButton.icon(
            onPressed: () => setState(() => photos++),
            icon: const Icon(YIcons.camera),
            label: Text(tr3('添加照片', 'Фото қосу', 'Добавить фото', 'Add photos', ky: 'Сүрөт кошуу', uz: 'Rasm qoʻshish'))),
        const SizedBox(width: 12),
        Text(
            tr3('$photos 张（测试环境为占位）', '$photos фото',
                '$photos фото (заглушка)',
                '$photos photos (placeholder)', ky: '$photos сүрөт (белгилөөчү)', uz: '$photos ta rasm (vaqtinchalik)'),
            style: TextStyle(color: t.muted)),
      ]),
      const SizedBox(height: 16),
      _field(title, tr3('标题', 'Тақырып', 'Заголовок', 'Title', ky: 'Аталышы', uz: 'Sarlavha'),
          hint: suggestedTitle(),
          helper: tr3('留空时根据工种和地区自动生成', 'Бос қалса, автоматты жасалады',
              'Если пусто — создадим автоматически',
              "If empty, we'll create one automatically", ky: 'Бош болсо, автоматтык түрдө түзөбүз', uz: 'Boʻsh boʻlsa, avtomatik yaratamiz'),
          onChanged: (_) => titleTouched = true),
    ]);
  }

  Future<void> addQuantity() async {
    final name = TextEditingController();
    final qty = TextEditingController();
    var unit = 'm3';
    var site = false;
    final item = await showDialog<QtyItem>(
        context: context,
        builder: (context) => PlatformTheme(
            child: StatefulBuilder(
                builder: (context, setDialog) => AlertDialog(
                        title: Text(tr3('工程量', 'Көлем', 'Объём', 'Quantity', ky: 'Саны', uz: 'Miqdori')),
                        content:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: name,
                              decoration: InputDecoration(
                                  labelText: tr3('分项名称', 'Атауы', 'Название', 'Name', ky: 'Аталышы', uz: 'Nomi'))),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: site,
                              title: Text(tr3(
                                  '需现场测量', 'Орында өлшенеді', 'Нужен замер', 'Needs a site measure', ky: 'Объектиде өлчөө керек', uz: 'Obyektda oʻlchash kerak')),
                              onChanged: (v) =>
                                  setDialog(() => site = v ?? false)),
                          if (!site)
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: qty,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                          labelText:
                                              tr3('数量', 'Саны', 'Кол-во', 'Qty', ky: 'Саны', uz: 'Soni')))),
                              const SizedBox(width: 10),
                              DropdownButton<String>(
                                  value: unit,
                                  items: [
                                    for (final u in const [
                                      'm3',
                                      'm2',
                                      'm',
                                      'pcs',
                                      't'
                                    ])
                                      DropdownMenuItem(
                                          value: u, child: Text(unitLabel(u))),
                                  ],
                                  onChanged: (v) =>
                                      setDialog(() => unit = v ?? 'm3')),
                            ]),
                        ]),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                          FilledButton(
                              onPressed: () {
                                final q = parseNum(qty.text);
                                if (name.text.trim().isEmpty ||
                                    (!site && (q == null || q <= 0))) {
                                  return;
                                }
                                Navigator.pop(
                                    context,
                                    QtyItem(
                                        name: name.text.trim(),
                                        quantity: site ? null : q,
                                        unit: unit,
                                        source: site
                                            ? QtySource.siteMeasure
                                            : QtySource.manual));
                              },
                              child: Text(tr3('添加', 'Қосу', 'Добавить', 'Add', ky: 'Кошуу', uz: 'Qoʻshish'))),
                        ]))));
    if (item != null) setState(() => quantities.add(item));
  }

  Widget _budgetStep(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(
            tr3('时间与预算', 'Уақыт пен бюджет', 'Сроки и бюджет', 'Dates and budget', ky: 'Мөөнөттөр жана бюджет', uz: 'Muddatlar va byudjet'),
            tr3(
                '不确定可以选择“请报价”，不需要编一个数字。',
                'Білмесеңіз, «баға ұсыныңыз» таңдаңыз.',
                'Не знаете бюджет — выберите «ждём предложений».',
                "Don't know the budget? Choose “waiting for quotes”.", ky: 'Бюджетти билбейсизби? «Сунуштарды күтөм» дегенди тандаңыз.', uz: 'Byudjetni bilmaysizmi? “Takliflarni kutaman” ni tanlang.')),
        _pickerTile(
            tr3('预计开工', 'Басталуы', 'Начало', 'Start', ky: 'Башталышы', uz: 'Boshlanishi'),
            startDate == null
                ? tr3('待协商', 'Келісіледі', 'По договорённости', 'By agreement', ky: 'Макулдашуу боюнча', uz: 'Kelishuv boʻyicha')
                : fmtDay(startDate), () async {
          final d = await showDatePicker(
              context: context,
              firstDate: context.now.subtract(const Duration(days: 1)),
              lastDate: context.now.add(const Duration(days: 365)),
              initialDate:
                  startDate ?? context.now.add(const Duration(days: 7)));
          setState(() => startDate = d);
        }),
        _field(duration, tr3('预计天数（可空）', 'Күн саны', 'Дней (необязательно)', 'Days (optional)', ky: 'Күн (милдеттүү эмес)', uz: 'Kun (ixtiyoriy)'),
            number: true),
        const SizedBox(height: 4),
        Text(tr3('预算', 'Бюджет', 'Бюджет', 'Budget', ky: 'Бюджет', uz: 'Byudjet'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (m, label) in [
            (
              BudgetMode.askQuote,
              tr3('不确定，请报价', 'Баға ұсыныңыз', 'Ждём предложений', 'Waiting for quotes', ky: 'Сунуштарды күтөм', uz: 'Takliflarni kutaman')
            ),
            (BudgetMode.range, tr3('区间', 'Аралық', 'Диапазон', 'Range', ky: 'Аралык', uz: 'Oraliq')),
            (BudgetMode.fixed, tr3('明确金额', 'Нақты сома', 'Точная сумма', 'Exact amount', ky: 'Так сумма', uz: 'Aniq summa')),
          ])
            FilterPill(
                label: label,
                selected: budgetMode == m,
                onTap: () => setState(() => budgetMode = m)),
        ]),
        const SizedBox(height: 12),
        if (budgetMode == BudgetMode.range)
          Row(children: [
            Expanded(
                child: _field(budgetMin, tr3('最低 ₸', 'Ең аз ₸', 'От ₸', 'From ₸', ky: '₸ баштап', uz: '₸ dan'),
                    number: true)),
            const SizedBox(width: 12),
            Expanded(
                child: _field(budgetMax, tr3('最高 ₸', 'Ең көп ₸', 'До ₸', 'To ₸', ky: '₸ чейин', uz: '₸ gacha'),
                    number: true)),
          ]),
        if (budgetMode == BudgetMode.fixed)
          _field(budgetAmount, tr3('金额 ₸', 'Сома ₸', 'Сумма ₸', 'Amount ₸', ky: 'Суммасы ₸', uz: 'Summa ₸'), number: true),
        if (budgetMode != BudgetMode.askQuote)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final u in const ['total', 'day', 'm3', 'm2'])
              FilterPill(
                  label: u == 'total'
                      ? tr3('总价', 'Жалпы', 'Всего', 'Total', ky: 'Бардыгы', uz: 'Jami')
                      : '/ ${unitLabel(u)}',
                  selected: budgetBasis == u,
                  onTap: () => setState(() => budgetBasis = u)),
          ]),
        if (type == DemandType.contract) ...[
          const SizedBox(height: 12),
          Hint(tr3(
              '预算范围：${materialName(materials)}。人工与材料请分开说明。',
              'Бюджет: ${materialName(materials)}.',
              'Бюджет: ${materialName(materials)}.',
              'Budget: ${materialName(materials)}.', ky: 'Бюджет: ${materialName(materials)}.', uz: 'Byudjet: ${materialName(materials)}.')),
        ],
      ]);

  Widget _privacyStep(BuildContext context) {
    final t = YTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(tr3('附件与隐私', 'Тіркеме және құпиялық', 'Вложения и приватность', 'Attachments and privacy', ky: 'Тиркемелер жана купуялык', uz: 'Ilovalar va maxfiylik')),
      if (fromDesign) ...[
        Text(
            tr3(
                '设计附件会固定为当前版本；之后修改设计不会改变已发布内容。',
                'Жоба тіркемесі осы нұсқада бекітіледі.',
                'Проект фиксируется в текущей версии.',
                'The design is captured at its current version.', ky: 'Долбоор учурдагы версиясында алынат.', uz: 'Loyiha joriy versiyasida olinadi.'),
            style: TextStyle(color: t.muted)),
        const SizedBox(height: 8),
        _switch(
            tr3('公开工程量', 'Көлемді жариялау', 'Показывать объёмы', 'Show quantities', ky: 'Көлөмдөрдү көрсөтүү', uz: 'Miqdorlarni koʻrsatish'),
            visibility.quantities,
            (v) => visibility = AttachmentVisibility(
                quantities: v,
                plan: visibility.plan,
                render: visibility.render)),
        _switch(
            tr3('公开平面图', 'Жоспарды жариялау', 'Показывать план', 'Show the plan', ky: 'Планды көрсөтүү', uz: 'Rejani koʻrsatish'),
            visibility.plan,
            (v) => visibility = AttachmentVisibility(
                quantities: visibility.quantities,
                plan: v,
                render: visibility.render)),
        _switch(
            tr3('公开效果图', 'Көріністі жариялау', 'Показывать визуализацию', 'Show the rendering', ky: 'Сүрөттү көрсөтүү', uz: 'Tasvirni koʻrsatish'),
            visibility.render,
            (v) => visibility = AttachmentVisibility(
                quantities: visibility.quantities,
                plan: visibility.plan,
                render: v)),
        const SizedBox(height: 8),
      ],
      Hint(
          tr3(
              '不会公开：手机号、具体地址、完整 .house 设计文件、家庭备注。',
              'Жарияланбайды: телефон, мекенжай, .house файлы, отбасы жазбалары.',
              'Не публикуется: телефон, точный адрес, файл .house, личные заметки.',
              'Not published: phone, exact address, .house file, private notes.', ky: 'Жарыяланбайт: телефон, так дарек, .house файлы, жеке эскертмелер.', uz: 'Eʼlon qilinmaydi: telefon, aniq manzil, .house fayli, shaxsiy izohlar.'),
          icon: YIcons.lock),
    ]);
  }

  Widget _previewStep(BuildContext context) {
    final v = compose();
    final preview = Demand(
        id: 'preview',
        ownerId: '',
        type: type,
        status: DemandStatus.open,
        versions: [v],
        createdAt: context.now,
        shareToken: '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(
          tr3('预览', 'Алдын ала қарау', 'Предпросмотр', 'Preview', ky: 'Алдын ала көрүү', uz: 'Oldindan koʻrish'),
          tr3('提交后进入审核，通过后公开。', 'Тексеруден кейін жарияланады.',
              'После проверки заявка станет публичной.',
              'After review the request becomes public.', ky: 'Текшерүүдөн кийин суроо-талап ачык болот.', uz: 'Tekshiruvdan keyin soʻrov ommaviy boʻladi.')),
      DemandCard(demand: preview, onTap: () {}),
      const SizedBox(height: 12),
      if (v.contract != null && v.contract!.quantities.isNotEmpty)
        QtyTable(v.contract!.quantities),
      if (editing && widget.editing!.status != DemandStatus.draft) ...[
        const SizedBox(height: 12),
        Hint(
            tr3(
                '将生成第 ${widget.editing!.current.no + 1} 版。已有报名／报价会标记“待重新确认”，已确认的合作不受影响。',
                '${widget.editing!.current.no + 1}-нұсқа жасалады. Бар ұсыныстар қайта расталуы керек.',
                'Будет создана версия ${widget.editing!.current.no + 1}. Отклики нужно будет подтвердить заново.',
                'Version ${widget.editing!.current.no + 1} will be created. Responses will need to be confirmed again.', ky: '${widget.editing!.current.no + 1}-версия түзүлөт. Жоопторду кайра ырастоо керек болот.', uz: '${widget.editing!.current.no + 1}-versiya yaratiladi. Javoblarni qayta tasdiqlash kerak boʻladi.'),
            warn: true),
      ],
    ]);
  }
}
