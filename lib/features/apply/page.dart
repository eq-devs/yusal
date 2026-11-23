import 'package:flutter/material.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/apply/state/apply.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/profile/pages/edit.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/model/form.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Sign-up (hire) or quote (contract) editor. Sending again creates a new
/// version of the same application; history is kept.
class ApplyPage extends StatefulWidget {
  const ApplyPage({super.key, required this.demand, this.existing});
  final Demand demand;
  final Application? existing;
  @override
  State<ApplyPage> createState() => _ApplyPageState();
}

class _QuoteRow {
  _QuoteRow(this.name, this.qty, this.unit, this.price);
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  String unit;
}

class _ApplyPageState extends State<ApplyPage> with VoiceScreen {
  @override
  String get screenId => 'apply';

  @override
  List<VoiceField> get fields => [
        if (hire) ...[
          VoiceField.number('wage',
              const L3('期望工资', 'Күтетін жалақы', 'Ожидаемая ставка', 'Expected rate'), wage),
          VoiceField.number('headcount',
              const L3('可提供人数', 'Адам саны', 'Сколько человек', 'How many people'), headcount),
        ] else ...[
          VoiceField.text('scope',
              const L3('承接范围', 'Қандай жұмыс', 'Что вы выполняете', "What you'll do"), scope),
          VoiceField.number(
              'lump_sum', const L3('总价', 'Жалпы баға', 'Сумма', 'Amount'), lump),
          VoiceField.number(
              'days', const L3('预计工期（天）', 'Мерзім (күн)', 'Срок (дней)', 'Duration (days)'), days),
          VoiceField.text(
              'includes', const L3('包含', 'Кіреді', 'Входит', 'Included'), includes),
          VoiceField.text(
              'excludes', const L3('不包含', 'Кірмейді', 'Не входит', 'Not included'), excludes),
        ],
        VoiceField.text(
            'note', const L3('补充说明', 'Қосымша', 'Комментарий', 'Comment'), note),
      ];

  @override
  Future<void> Function()? get voiceSubmit => submit;
  final requestId = const Uuid().v4();
  String? profileId;
  DateTime? availableFrom;
  bool acceptsOffer = true;
  final wage = TextEditingController();
  final headcount = TextEditingController(text: '1');
  final note = TextEditingController();
  final scope = TextEditingController();
  final lump = TextEditingController();
  final days = TextEditingController();
  final includes = TextEditingController();
  final excludes = TextEditingController();
  MaterialMode materials = MaterialMode.labourOnly;
  PricingMode pricing = PricingMode.lumpSum;
  DateTime? validUntil;
  final rows = <_QuoteRow>[];
  String? error;

  Demand get d => widget.demand;
  bool get hire => d.type == DemandType.hire;

  @override
  void initState() {
    super.initState();
    final c = d.current.contract;
    materials = c?.materials == MaterialMode.labourAndMaterial
        ? MaterialMode.labourAndMaterial
        : MaterialMode.labourOnly;
    if (c != null && c.quantities.isNotEmpty) {
      pricing = c.quantities.every((q) => q.quantity != null)
          ? PricingMode.perQuantity
          : PricingMode.siteConfirm;
      for (final q in c.quantities) {
        rows.add(_QuoteRow(
            TextEditingController(text: q.name),
            TextEditingController(
                text: q.quantity == null ? '' : numText(q.quantity!)),
            q.unit,
            TextEditingController()));
      }
    }
    availableFrom = d.current.startDate;
    acceptsOffer = d.current.hire?.wage != null;
    // Start from what the owner asked for; the pro narrows it if needed.
    if (c != null) {
      scope.text = c.stages.isEmpty
          ? scopeKindName(c.scopeKind)
          : c.stages.map(stageLabel).join(listSep);
      if (c.targetDays != null) days.text = '${c.targetDays}';
    }
    final e = widget.existing;
    if (e != null) {
      final v = e.current;
      profileId = e.profileId;
      availableFrom = v.availableFrom;
      acceptsOffer = v.acceptsOffer;
      wage.text = v.expectedWage?.toString() ?? '';
      headcount.text = '${v.headcountOffered}';
      note.text = v.note;
      scope.text = v.scopeText;
      materials = v.materials;
      pricing = v.pricing;
      lump.text = v.lumpSum?.toString() ?? '';
      days.text = v.durationDays?.toString() ?? '';
      includes.text = v.includes;
      excludes.text = v.excludes;
      validUntil = v.validUntil;
      if (v.lines.isNotEmpty) {
        rows
          ..clear()
          ..addAll([
            for (final l in v.lines)
              _QuoteRow(
                  TextEditingController(text: l.name),
                  TextEditingController(text: numText(l.quantity)),
                  l.unit,
                  TextEditingController(text: '${l.unitPrice}'))
          ]);
      }
    }
  }

  double? get lineTotal {
    var sum = 0.0;
    for (final r in rows) {
      final q = parseNum(r.qty.text);
      final p = parseInt(r.price.text);
      if (q == null || p == null) return null;
      sum += q * p;
    }
    return rows.isEmpty ? null : sum;
  }

  ApplicationVersion compose() => ApplicationVersion(
      no: 0,
      demandVersionNo: d.current.no,
      createdAt: DateTime.now(),
      note: note.text,
      availableFrom: availableFrom,
      acceptsOffer: hire && acceptsOffer,
      expectedWage: parseInt(wage.text),
      headcountOffered: parseInt(headcount.text) ?? 1,
      scopeText: scope.text,
      materials: materials,
      pricing: pricing,
      lines: [
        for (final r in rows)
          if (r.name.text.trim().isNotEmpty)
            QuoteLine(
                name: r.name.text.trim(),
                quantity: parseNum(r.qty.text) ?? 0,
                unit: r.unit,
                unitPrice: parseInt(r.price.text) ?? 0)
      ],
      lumpSum: parseInt(lump.text),
      durationDays: parseInt(days.text),
      includes: includes.text,
      excludes: excludes.text,
      validUntil: validUntil);

  String? validate() {
    if (profileId == null) {
      return tr3('请选择用哪个名片报名', 'Профильді таңдаңыз', 'Выберите профиль', 'Choose a profile');
    }
    if (hire) {
      if (!acceptsOffer && (parseInt(wage.text) ?? 0) <= 0) {
        return tr3('请填写期望工资，或接受原条件', 'Жалақыны жазыңыз', 'Укажите ставку', 'Enter a rate');
      }
      return null;
    }
    if (scope.text.trim().isEmpty) {
      return tr3('请写明承接范围', 'Көлемді жазыңыз', 'Опишите объём работ', 'Describe the scope of work');
    }
    if (pricing == PricingMode.lumpSum && (parseInt(lump.text) ?? 0) <= 0) {
      return tr3('请填写总价', 'Жалпы бағаны жазыңыз', 'Укажите сумму', 'Enter an amount');
    }
    if (pricing == PricingMode.perQuantity && lineTotal == null) {
      return tr3('请为每一项填写数量和单价', 'Әр жолға сан мен баға',
          'Заполните количество и цену',
          'Fill in quantity and price');
    }
    return null;
  }

  Future<void> submit() async {
    final problem = validate();
    setState(() => error = problem);
    if (problem != null) return;
    final ok = await attempt(
        context,
        () => context.read(applicationRepositoryProvider).submit(
            demandId: d.id,
            profileId: profileId!,
            version: compose(),
            requestId: requestId),
        success: hire
            ? tr3('报名已发送', 'Өтінім жіберілді', 'Отклик отправлен', 'Response sent')
            : tr3('报价已发送', 'Ұсыныс жіберілді', 'Предложение отправлено', 'Quote sent'));
    if (ok != null && mounted) {
      HapticFeedback.lightImpact();
      Navigator.pop(context);
    }
  }

  Widget _field(TextEditingController c, String label,
          {bool number = false,
          int lines = 1,
          String? hint,
          ValueChanged<String>? onChanged}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              keyboardType: number ? TextInputType.number : null,
              minLines: lines,
              maxLines: lines == 1 ? 1 : lines + 2,
              onChanged: onChanged,
              decoration: InputDecoration(labelText: label, hintText: hint)));

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final t = YTokens.of(context);
    final e = widget.existing;
    final locked = e != null &&
        (e.status == ApplicationStatus.pendingConfirm ||
            e.status == ApplicationStatus.cooperating);
    return PageScaffold(
        title: hire
            ? tr3('报名', 'Өтінім', 'Отклик', 'Response')
            : tr3('报价', 'Баға ұсынысы', 'Предложение', 'Quote'),
        bottom: locked
            ? null
            : BusyButton(
                label: e == null
                    ? (hire
                        ? tr3('发送报名', 'Жіберу', 'Отправить', 'Send')
                        : tr3('发送报价', 'Жіберу', 'Отправить', 'Send'))
                    : tr3(
                        '更新（保留历史）', 'Жаңарту', 'Обновить (история сохранится)', 'Update (history is kept)'),
                onPressed: submit),
        body: Live<List<ServiceProfile>>(
            provider: applyProfilesProvider,
            builder: (context, profiles) {
              if (profileId == null && profiles.length == 1) {
                profileId = profiles.first.id;
              }
              final hireTerms = d.current.hire;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.current.title,
                        style: const TextStyle(
                            fontSize: YFont.title,
                            fontWeight: FontWeight.w700)),
                    Text(
                        tr3(
                            '依据第 ${d.current.no} 版需求',
                            '${d.current.no}-нұсқа бойынша',
                            'По версии ${d.current.no}',
                            'For version ${d.current.no}'),
                        style: TextStyle(color: t.muted)),
                    if (e != null) ...[
                      const SizedBox(height: 12),
                      Hint(
                          '${tr3('当前状态', 'Күйі', 'Статус', 'Status')}: ${applicationStatusName(e.status)}${e.needsReconfirm ? ' · ${tr3('需求已修改，请确认或更新', 'Тапсырыс өзгерді', 'Заявка изменилась — обновите', 'The request changed; update yours')}' : ''}',
                          warn: e.needsReconfirm),
                      if (locked)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(tr3(
                                '已进入合作约定，修改请在合作页提出变更。',
                                'Келісім жасалған, өзгерісті келісім бетінде ұсыныңыз.',
                                'Есть соглашение — изменения через страницу сотрудничества.',
                                "There's an agreement; make changes on the cooperation page."))),
                      const SizedBox(height: 8),
                      if (e.status == ApplicationStatus.submitted ||
                          e.status == ApplicationStatus.pendingConfirm)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                                onPressed: () async {
                                  if (await confirmDialog(
                                          context,
                                          tr3('撤回？', 'Қайтару?',
                                              'Отозвать?',
                                              'Withdraw?')) &&
                                      context.mounted) {
                                    await attempt(
                                        context,
                                        () => context
                                            .read(applicationRepositoryProvider)
                                            .withdraw(e.id));
                                    if (context.mounted) Navigator.pop(context);
                                  }
                                },
                                child: Text(tr3('撤回', 'Қайтару', 'Отозвать', 'Withdraw')))),
                    ],
                    SectionTitle(tr3('用哪个名片', 'Қай профиль', 'От имени', 'On behalf of')),
                    if (profiles.isEmpty)
                      YCard(
                          onTap: () => pushPage<void>(
                              context, (_) => const ProfileEditPage()),
                          child: Row(children: [
                            const Icon(Icons.badge_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(tr3(
                                    '先创建接活名片（个人或团队），只需几项信息。',
                                    'Алдымен профиль жасаңыз.',
                                    'Сначала создайте профиль мастера или бригады.',
                                    'First create a pro or crew profile.'))),
                            const Icon(Icons.chevron_right),
                          ]))
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final p in profiles)
                          FilterPill(
                              label: '${p.name} · ${profileKindName(p.kind)}',
                              selected: profileId == p.id,
                              onTap: locked
                                  ? () {}
                                  : () => setState(() => profileId = p.id)),
                      ]),
                    if (hire) ...[
                      SectionTitle(
                          tr3('到岗与工资', 'Келу және жалақы', 'Выход и оплата', 'Start and pay')),
                      ListTile(
                          title:
                              Text(tr3('可到岗日期', 'Келу күні', 'Могу выйти с', 'I can start on')),
                          subtitle: Text(fmtDay(availableFrom)),
                          trailing: const YusalIcon(YIcon.calendar),
                          onTap: () async {
                            final v = await showDatePicker(
                                context: context,
                                firstDate: context.now
                                    .subtract(const Duration(days: 1)),
                                lastDate:
                                    context.now.add(const Duration(days: 180)),
                                initialDate: availableFrom ?? context.now);
                            if (v != null) setState(() => availableFrom = v);
                          }),
                      if (hireTerms?.wage != null)
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(tr3(
                                '接受原工资 ${money(hireTerms!.wage, unit: hireTerms.wageUnit)}',
                                'Жалақыға келісемін ${money(hireTerms.wage, unit: hireTerms.wageUnit)}',
                                'Согласен на ${money(hireTerms.wage, unit: hireTerms.wageUnit)}',
                                'I agree to ${money(hireTerms.wage, unit: hireTerms.wageUnit)}')),
                            value: acceptsOffer,
                            onChanged: (v) => setState(() => acceptsOffer = v)),
                      if (!acceptsOffer || hireTerms?.wage == null)
                        _field(
                            wage,
                            tr3('期望工资 ₸ / ${unitLabel(hireTerms?.wageUnit ?? 'day')}',
                                'Күтетін жалақы ₸', 'Ожидаемая ставка ₸', 'Expected rate ₸'),
                            number: true),
                      if (profiles
                              .where((p) => p.id == profileId)
                              .firstOrNull
                              ?.kind ==
                          ProfileKind.team)
                        _field(headcount,
                            tr3('可提供人数', 'Адам саны', 'Сколько человек', 'How many people'),
                            number: true),
                    ] else ...[
                      SectionTitle(tr3('承接范围', 'Көлемі', 'Объём', 'Scope')),
                      _field(scope,
                          tr3('你承接哪些工作', 'Қандай жұмыс', 'Что вы выполняете', "What you'll do"),
                          lines: 2,
                          hint: tr3(
                              '例如：外墙与内墙砌筑，含构造柱模板',
                              'Мысалы: сыртқы және ішкі қабырға',
                              'Напр.: кладка наружных и внутренних стен',
                              'E.g. outer and inner wall masonry')),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final m in const [
                          MaterialMode.labourOnly,
                          MaterialMode.labourAndMaterial
                        ])
                          FilterPill(
                              label: materialName(m),
                              selected: materials == m,
                              onTap: () => setState(() => materials = m)),
                      ]),
                      SectionTitle(tr3('价格', 'Баға', 'Цена', 'Price')),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final p in PricingMode.values)
                          FilterPill(
                              label: pricingName(p),
                              selected: pricing == p,
                              onTap: () => setState(() => pricing = p)),
                      ]),
                      const SizedBox(height: 12),
                      if (pricing == PricingMode.lumpSum)
                        _field(lump, tr3('总价 ₸', 'Жалпы баға ₸', 'Сумма ₸', 'Amount ₸'),
                            number: true),
                      if (pricing == PricingMode.perQuantity) ...[
                        for (final (i, r) in rows.indexed)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              // The name gets the whole width: next to
                              // the numbers a phone showed nine letters of it.
                              child: Column(children: [
                                Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: r.name,
                                          decoration: InputDecoration(
                                              labelText: tr3(
                                                  '分项', 'Жұмыс', 'Работа', 'Labour')))),
                                  IconButton(
                                      tooltip: tr3('删除', 'Жою', 'Удалить', 'Delete'),
                                      onPressed: () =>
                                          setState(() => rows.removeAt(i)),
                                      icon: const Icon(Icons.close, size: 18)),
                                ]),
                                const SizedBox(height: 6),
                                Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: r.qty,
                                          onChanged: (_) => setState(() {}),
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                              labelText: unitLabel(r.unit)))),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: TextField(
                                          controller: r.price,
                                          onChanged: (_) => setState(() {}),
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                              labelText:
                                                  '₸${perUnit(r.unit)}'))),
                                  // Lines the numbers up under the name.
                                  const SizedBox(width: 48),
                                ]),
                              ])),
                        Row(children: [
                          TextButton.icon(
                              onPressed: () => setState(() => rows.add(
                                  _QuoteRow(
                                      TextEditingController(),
                                      TextEditingController(),
                                      'm3',
                                      TextEditingController()))),
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(
                                  tr3('添加分项', 'Жол қосу', 'Добавить строку', 'Add a line'))),
                          const Spacer(),
                          Text(
                              '${tr3('合计', 'Барлығы', 'Итого', 'Total')}: ${money(lineTotal)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ],
                      if (pricing == PricingMode.siteConfirm)
                        Hint(tr3(
                            '报价状态为“需现场确认”，对比时会单独提示，不与确定价格混排。',
                            'Баға орында нақтыланады.',
                            'Цена будет уточнена на месте.',
                            'The price will be confirmed on site.')),
                      const SizedBox(height: 12),
                      _field(
                          days, tr3('预计工期（天）', 'Мерзім (күн)', 'Срок (дней)', 'Duration (days)'),
                          number: true),
                      _field(
                          includes,
                          tr3('包含（运输、设备、清运…）', 'Кіреді',
                              'Входит (доставка, техника…)',
                              'Includes (delivery, machinery…)')),
                      _field(excludes, tr3('不包含', 'Кірмейді', 'Не входит', 'Not included')),
                      ListTile(
                          title:
                              Text(tr3('报价有效期', 'Жарамдылық', 'Действует до', 'Valid until')),
                          subtitle: Text(
                              validUntil == null ? '—' : fmtDay(validUntil)),
                          trailing: const YusalIcon(YIcon.calendar),
                          onTap: () async {
                            final v = await showDatePicker(
                                context: context,
                                firstDate: context.now,
                                lastDate:
                                    context.now.add(const Duration(days: 120)),
                                initialDate: validUntil ??
                                    context.now.add(const Duration(days: 14)));
                            if (v != null) setState(() => validUntil = v);
                          }),
                    ],
                    _field(note, tr3('补充说明（可选）', 'Қосымша', 'Комментарий', 'Comment'),
                        lines: 2),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Hint(error!, warn: true)
                    ],
                    const SizedBox(height: 12),
                    Hint(tr3('不要向发布者缴纳任何押金。遇到可疑要求请举报。', 'Кепілақы төлемеңіз.',
                        'Не платите залог. О подозрительных просьбах сообщайте.',
                        "Don't pay deposits. Report suspicious requests.")),
                    if (d.current.contract?.quantities.isNotEmpty ?? false) ...[
                      SectionTitle(tr3(
                          '需求中的工程量', 'Тапсырыстағы көлем', 'Объёмы в заявке', 'Quantities in the request')),
                      QtyTable(d.current.contract!.quantities),
                    ],
                  ]);
            }));
  }
}
