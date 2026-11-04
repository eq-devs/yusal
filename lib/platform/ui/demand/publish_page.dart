import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../cards.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import '../unsaved_changes_guard.dart';
import 'demand_detail_page.dart';

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

class _PublishPageState extends State<PublishPage> {
  int step = 0;
  DemandType type = DemandType.contract;
  PublisherRole role = PublisherRole.owner;
  final title = TextEditingController(),
      locality = TextEditingController(),
      address = TextEditingController(),
      description = TextEditingController(),
      siteNotes = TextEditingController(),
      headcount = TextEditingController(text: '1'),
      wage = TextEditingController(),
      days = TextEditingController(),
      duration = TextEditingController(),
      targetDays = TextEditingController(),
      budgetMin = TextEditingController(),
      budgetMax = TextEditingController(),
      budgetAmount = TextEditingController();
  bool titleTouched = false;
  List<String> trades = [];
  String? region;
  int photos = 0;
  PayMode payMode = PayMode.daily;
  bool wageNegotiable = false;
  String wageUnit = 'day';
  bool food = false, tools = false;
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
          ? stages.map(stageLabel).join('、')
          : null);

  String? validate(int s) {
    if (s == 1) {
      if (trades.isEmpty)
        return tr3('请选择工种', 'Мамандықты таңдаңыз', 'Выберите специальность');
      if (region == null)
        return tr3('请选择地区', 'Аймақты таңдаңыз', 'Выберите район');
      if (title.text.trim().isEmpty)
        return tr3('请填写标题', 'Тақырып жазыңыз', 'Введите заголовок');
      if (type == DemandType.hire) {
        if ((parseInt(headcount.text) ?? 0) < 1)
          return tr3('人数至少 1 人', 'Кемінде 1 адам', 'Минимум 1 человек');
        if (!wageNegotiable && (parseInt(wage.text) ?? 0) <= 0)
          return tr3('请填写工资，或选择面议', 'Жалақыны жазыңыз не «келісіледі»',
              'Укажите ставку или «договорная»');
      } else if (scopeKind == ScopeKind.stages && stages.isEmpty) {
        return tr3('请选择施工阶段', 'Кезеңді таңдаңыз', 'Выберите этапы');
      }
    }
    if (s == 2) {
      switch (budgetMode) {
        case BudgetMode.fixed:
          if ((parseInt(budgetAmount.text) ?? 0) <= 0)
            return tr3('请填写金额，或选择“请报价”', 'Соманы жазыңыз',
                'Укажите сумму или «ждём предложений»');
        case BudgetMode.range:
          final a = parseInt(budgetMin.text) ?? 0,
              b = parseInt(budgetMax.text) ?? 0;
          if (a <= 0 || b < a)
            return tr3('区间不正确', 'Аралық қате', 'Неверный диапазон');
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
    final repos = context.repos;
    final result = await attempt(context, () async {
      if (widget.snapshot != null && _snapshotId == null) {
        _snapshotId = (await repos.saveSnapshot(widget.snapshot!)).id;
      }
      final d = widget.editing;
      if (d == null) {
        final draft = await repos.saveDraft(type, compose(),
            role: role, designProjectId: widget.designProjectId);
        return repos.publish(draft.id);
      }
      if (d.status == DemandStatus.draft) {
        await repos.saveDraft(type, compose(), existingId: d.id);
        return repos.publish(d.id);
      }
      return repos.revise(d.id, compose());
    });
    if (result == null || !mounted) return;
    toast(
        context,
        switch (result.status) {
          DemandStatus.open => tr3('已发布，正在招募', 'Жарияланды', 'Опубликовано'),
          DemandStatus.rejected =>
            tr3('审核未通过，请查看原因', 'Қабылданбады', 'Не прошло проверку'),
          _ => tr3(
              '已提交审核，通过后自动公开', 'Тексеруге жіберілді', 'Отправлено на проверку'),
        });
    Navigator.pop(context);
    if (!editing)
      await pushPage<void>(
          context, (_) => DemandDetailPage(demandId: result.id));
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
    final d = await attempt(context, () async {
      if (widget.snapshot != null && _snapshotId == null)
        _snapshotId = (await context.repos.saveSnapshot(widget.snapshot!)).id;
      return context.repos.saveDraft(type, compose(),
          role: role, designProjectId: widget.designProjectId);
    }, success: tr3('草稿已保存，仅自己可见', 'Жоба сақталды', 'Черновик сохранён'));
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
    AppScope.watch(context);
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
                    ? tr3('修改需求', 'Тапсырысты өзгерту', 'Изменить заявку')
                    : fromDesign
                        ? tr3('从设计发布', 'Жобадан жариялау', 'Из проекта')
                        : tr3('发布需求', 'Тапсырыс беру', 'Новая заявка')),
                actions: [
                  if (!editing && step > 0)
                    TextButton(
                        onPressed: saveDraftOnly,
                        child: Text(tr3('存草稿', 'Сақтау', 'Черновик'))),
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
                    child: Text(tr3('返回', 'Артқа', 'Назад'))),
              const Spacer(),
              if (step < last)
                FilledButton(
                    onPressed: next, child: Text(tr3('下一步', 'Келесі', 'Далее')))
              else
                BusyButton(
                    expand: false,
                    label:
                        editing && widget.editing!.status != DemandStatus.draft
                            ? tr3('发布新版本', 'Жаңа нұсқа', 'Опубликовать версию')
                            : tr3('提交发布', 'Жариялау', 'Опубликовать'),
                    onPressed: submit),
            ]))));
  }

  Widget _heading(String text, [String? sub]) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
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
                                    fontSize: 17, fontWeight: FontWeight.w700)),
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
            tr3('你想找什么样的人？', 'Кімді іздейсіз?', 'Кого вы ищете?'),
            tr3('不需要先画图，也能发布。', 'Сызбасыз да жариялауға болады.',
                'Чертёж не обязателен.')),
        _choice(
            selected: type == DemandType.hire,
            icon: Icons.engineering_outlined,
            title: demandTypeName(DemandType.hire),
            body: tr3(
                '例如：找两名瓦工，按天结算。对方报名并说明到岗时间。',
                'Мысалы: 2 қалаушы, күнделікті төлем.',
                'Например: 2 каменщика, подённая оплата.'),
            onTap: () => setState(() => type = DemandType.hire)),
        _choice(
            selected: type == DemandType.contract,
            icon: Icons.home_work_outlined,
            title: demandTypeName(DemandType.contract),
            body: tr3(
                '例如：130 平米住宅砌墙。对方说明承接范围、价格和工期。',
                'Мысалы: 130 м² үйдің қабырғасы.',
                'Например: кладка стен дома 130 м².'),
            onTap: () => setState(() => type = DemandType.contract)),
        const SizedBox(height: 8),
        Text(tr3('你的身份', 'Сіз кімсіз', 'Вы'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilterPill(
              label: tr3('业主／房屋所有人', 'Үй иесі', 'Владелец'),
              selected: role == PublisherRole.owner,
              onTap: () => setState(() => role = PublisherRole.owner)),
          FilterPill(
              label: tr3('施工方（分包／补人）', 'Мердігер', 'Подрядчик (субподряд)'),
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
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
                decoration: InputDecoration(
                    labelText: label,
                    suffixIcon: const Icon(Icons.expand_more)),
                child: Text(
                    value.isEmpty ? tr3('请选择', 'Таңдаңыз', 'Выберите') : value,
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
          tr3('工作内容', 'Жұмыс', 'Работа'),
          tr3(
              '公开页面只显示城市／村镇／街区；具体地址只在你授权后给合作方。',
              'Жария бетте тек елді мекен көрсетіледі.',
              'Публично виден только населённый пункт; точный адрес — по вашему решению.')),
      _pickerTile(tr3('工种', 'Мамандық', 'Специальность'),
          trades.map(tradeName).join('、'), () async {
        final v = await pickMany<String>(
            context,
            tr3('工种（可多选）', 'Мамандық', 'Специальности'),
            [for (final c in tradeCodes) (c, tradeName(c))],
            trades);
        if (v != null) setState(() => trades = v);
      }),
      _pickerTile(tr3('地区', 'Аймақ', 'Район'),
          region == null ? '' : regionName(region!), () async {
        final v = await pickOne<String>(context, tr3('地区', 'Аймақ', 'Район'),
            [for (final c in regionCodes) (c, regionName(c))],
            selected: region);
        if (v != null) setState(() => region = v);
      }),
      _field(
          locality,
          tr3('村镇／街区（公开）', 'Ауыл / аудан (жария)',
              'Посёлок / микрорайон (публично)')),
      _field(address,
          tr3('具体地址（不公开）', 'Нақты мекенжай (жасырын)', 'Точный адрес (скрыт)'),
          helper: tr3('只在合作约定中由你选择是否告诉对方', 'Тек келісімде көрсетіледі',
              'Передаётся только по соглашению')),
      if (type == DemandType.hire) ...[
        _field(headcount, tr3('需要人数', 'Адам саны', 'Сколько человек'),
            number: true),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in PayMode.values)
            FilterPill(
                label: payModeName(p),
                selected: payMode == p,
                onTap: () => setState(() => payMode = p)),
        ]),
        const SizedBox(height: 12),
        _switch(tr3('工资面议', 'Жалақы келісіледі', 'Ставка договорная'),
            wageNegotiable, (v) => wageNegotiable = v),
        if (!wageNegotiable)
          Row(children: [
            Expanded(
                child: _field(wage, tr3('工资（₸）', 'Жалақы (₸)', 'Ставка (₸)'),
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
        _field(days, tr3('预计工作天数（可空）', 'Күн саны', 'Дней (необязательно)'),
            number: true),
        _switch(tr3('提供食宿', 'Тамақ пен жатын орын бар', 'Питание и жильё'),
            food, (v) => food = v),
        _switch(
            tr3('工具由雇主提供', 'Құралды жұмыс беруші береді',
                'Инструмент от работодателя'),
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
        Text(tr3('承接范围', 'Көлемі', 'Объём работ'),
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
              child: Text(tr3('工程量', 'Көлемдер', 'Объёмы'),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          TextButton.icon(
              onPressed: addQuantity,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr3('添加', 'Қосу', 'Добавить'))),
        ]),
        if (quantities.isEmpty)
          Text(
              tr3('未知可以不填，或注明现场测量。', 'Белгісіз болса, бос қалдырыңыз.',
                  'Можно не указывать или отметить замер.'),
              style: TextStyle(color: t.muted)),
        for (final (i, q) in quantities.indexed)
          ListTile(
              dense: true,
              title: Text(q.name),
              subtitle: Text(qtySourceName(q.source)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(q.quantity == null
                    ? tr3('现场测量', 'Орында', 'Замер')
                    : '${numText(q.quantity!)} ${unitLabel(q.unit)}'),
                IconButton(
                    tooltip: tr3('删除', 'Жою', 'Удалить'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => quantities.removeAt(i))),
              ])),
        const SizedBox(height: 8),
        _field(targetDays, tr3('目标工期（天）', 'Мерзім (күн)', 'Срок (дней)'),
            number: true),
        _pickerTile(tr3('报价截止日期', 'Ұсыныс мерзімі', 'Приём цен до'),
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
      _field(description, tr3('说明（可选）', 'Сипаттама', 'Описание'), lines: 3),
      _field(siteNotes,
          tr3('现场限制（可选）', 'Орын шектеулері', 'Ограничения на объекте'),
          hint: tr3(
              '例如：无电、道路窄', 'Мысалы: жарық жоқ', 'Напр.: нет электричества')),
      Row(children: [
        OutlinedButton.icon(
            onPressed: () => setState(() => photos++),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(tr3('添加照片', 'Фото қосу', 'Добавить фото'))),
        const SizedBox(width: 12),
        Text(
            tr3('$photos 张（测试环境为占位）', '$photos фото',
                '$photos фото (заглушка)'),
            style: TextStyle(color: t.muted)),
      ]),
      const SizedBox(height: 16),
      _field(title, tr3('标题', 'Тақырып', 'Заголовок'),
          hint: suggestedTitle(),
          helper: tr3('留空时根据工种和地区自动生成', 'Бос қалса, автоматты жасалады',
              'Если пусто — создадим автоматически'),
          onChanged: (_) => titleTouched = true),
    ]);
  }

  Future<void> addQuantity() async {
    final name = TextEditingController(), qty = TextEditingController();
    var unit = 'm3';
    var site = false;
    final item = await showDialog<QtyItem>(
        context: context,
        builder: (context) => PlatformTheme(
            child: StatefulBuilder(
                builder: (context, setDialog) => AlertDialog(
                        title: Text(tr3('工程量', 'Көлем', 'Объём')),
                        content:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: name,
                              decoration: InputDecoration(
                                  labelText: tr3('分项名称', 'Атауы', 'Название'))),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: site,
                              title: Text(tr3(
                                  '需现场测量', 'Орында өлшенеді', 'Нужен замер')),
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
                                              tr3('数量', 'Саны', 'Кол-во')))),
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
                              child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                          FilledButton(
                              onPressed: () {
                                final q = parseNum(qty.text);
                                if (name.text.trim().isEmpty ||
                                    (!site && (q == null || q <= 0))) return;
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
                              child: Text(tr3('添加', 'Қосу', 'Добавить'))),
                        ]))));
    if (item != null) setState(() => quantities.add(item));
  }

  Widget _budgetStep(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(
            tr3('时间与预算', 'Уақыт пен бюджет', 'Сроки и бюджет'),
            tr3(
                '不确定可以选择“请报价”，不需要编一个数字。',
                'Білмесеңіз, «баға ұсыныңыз» таңдаңыз.',
                'Не знаете бюджет — выберите «ждём предложений».')),
        _pickerTile(
            tr3('预计开工', 'Басталуы', 'Начало'),
            startDate == null
                ? tr3('待协商', 'Келісіледі', 'По договорённости')
                : fmtDay(startDate), () async {
          final d = await showDatePicker(
              context: context,
              firstDate: context.now.subtract(const Duration(days: 1)),
              lastDate: context.now.add(const Duration(days: 365)),
              initialDate:
                  startDate ?? context.now.add(const Duration(days: 7)));
          setState(() => startDate = d);
        }),
        _field(duration, tr3('预计天数（可空）', 'Күн саны', 'Дней (необязательно)'),
            number: true),
        const SizedBox(height: 4),
        Text(tr3('预算', 'Бюджет', 'Бюджет'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (m, label) in [
            (
              BudgetMode.askQuote,
              tr3('不确定，请报价', 'Баға ұсыныңыз', 'Ждём предложений')
            ),
            (BudgetMode.range, tr3('区间', 'Аралық', 'Диапазон')),
            (BudgetMode.fixed, tr3('明确金额', 'Нақты сома', 'Точная сумма')),
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
                child: _field(budgetMin, tr3('最低 ₸', 'Ең аз ₸', 'От ₸'),
                    number: true)),
            const SizedBox(width: 12),
            Expanded(
                child: _field(budgetMax, tr3('最高 ₸', 'Ең көп ₸', 'До ₸'),
                    number: true)),
          ]),
        if (budgetMode == BudgetMode.fixed)
          _field(budgetAmount, tr3('金额 ₸', 'Сома ₸', 'Сумма ₸'), number: true),
        if (budgetMode != BudgetMode.askQuote)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final u in const ['total', 'day', 'm3', 'm2'])
              FilterPill(
                  label: u == 'total'
                      ? tr3('总价', 'Жалпы', 'Всего')
                      : '/ ${unitLabel(u)}',
                  selected: budgetBasis == u,
                  onTap: () => setState(() => budgetBasis = u)),
          ]),
        if (type == DemandType.contract) ...[
          const SizedBox(height: 12),
          Hint(tr3(
              '预算范围：${materialName(materials)}。人工与材料请分开说明。',
              'Бюджет: ${materialName(materials)}.',
              'Бюджет: ${materialName(materials)}.')),
        ],
      ]);

  Widget _privacyStep(BuildContext context) {
    final t = YTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(tr3('附件与隐私', 'Тіркеме және құпиялық', 'Вложения и приватность')),
      if (fromDesign) ...[
        Text(
            tr3(
                '设计附件会固定为当前版本；之后修改设计不会改变已发布内容。',
                'Жоба тіркемесі осы нұсқада бекітіледі.',
                'Проект фиксируется в текущей версии.'),
            style: TextStyle(color: t.muted)),
        const SizedBox(height: 8),
        _switch(
            tr3('公开工程量', 'Көлемді жариялау', 'Показывать объёмы'),
            visibility.quantities,
            (v) => visibility = AttachmentVisibility(
                quantities: v,
                plan: visibility.plan,
                render: visibility.render)),
        _switch(
            tr3('公开平面图', 'Жоспарды жариялау', 'Показывать план'),
            visibility.plan,
            (v) => visibility = AttachmentVisibility(
                quantities: visibility.quantities,
                plan: v,
                render: visibility.render)),
        _switch(
            tr3('公开效果图', 'Көріністі жариялау', 'Показывать визуализацию'),
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
              'Не публикуется: телефон, точный адрес, файл .house, личные заметки.'),
          icon: Icons.lock_outline),
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
          tr3('预览', 'Алдын ала қарау', 'Предпросмотр'),
          tr3('提交后进入审核，通过后公开。', 'Тексеруден кейін жарияланады.',
              'После проверки заявка станет публичной.')),
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
                'Будет создана версия ${widget.editing!.current.no + 1}. Отклики нужно будет подтвердить заново.'),
            warn: true),
      ],
    ]);
  }
}
