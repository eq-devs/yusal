import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../widgets.dart';

/// Terms of a cooperation agreement ("合作约定"). Used to invite the chosen
/// applicant and to propose a change; pops the [Agreement] to send.
class AgreementForm extends StatefulWidget {
  const AgreementForm(
      {super.key, required this.demand, this.application, this.current});
  final Demand demand;
  final Application? application;

  /// The agreement in force, when proposing a change.
  final Agreement? current;
  @override
  State<AgreementForm> createState() => _AgreementFormState();
}

class _AgreementFormState extends State<AgreementForm> {
  final scope = TextEditingController(),
      headcount = TextEditingController(),
      amount = TextEditingController(),
      payment = TextEditingController(),
      materials = TextEditingController(),
      open = TextEditingController();
  PricingMode pricing = PricingMode.lumpSum;
  String unit = 'total';
  DateTime? start, end;
  bool shareAddress = false;
  String? error;

  bool get hire => widget.demand.type == DemandType.hire;

  @override
  void initState() {
    super.initState();
    final d = widget.demand.current;
    final c = widget.current;
    if (c != null) {
      scope.text = c.scope;
      headcount.text = c.headcount?.toString() ?? '';
      amount.text = c.amount?.toString() ?? '';
      pricing = c.pricing;
      unit = c.amountUnit;
      start = c.startDate;
      end = c.endDate;
      payment.text = c.paymentTerms;
      materials.text = c.materialsResponsibility;
      open.text = c.openItems;
      shareAddress = c.shareExactAddress;
      return;
    }
    final v = widget.application?.current;
    start = v?.availableFrom ?? d.startDate;
    if (d.durationDays != null && start != null)
      end = start!.add(Duration(days: d.durationDays!));
    if (hire) {
      final h = d.hire!;
      scope.text = d.title;
      headcount.text = '${v?.headcountOffered ?? 1}';
      final w = v == null || v.acceptsOffer ? h.wage : v.expectedWage;
      amount.text = w?.toString() ?? '';
      unit = h.wageUnit;
      pricing = PricingMode.perQuantity;
      materials.text = h.toolsByEmployer
          ? tr3('工具由雇主提供', 'Құралды жұмыс беруші береді',
              'Инструмент от работодателя')
          : tr3('工人自带工具', 'Құрал өзінікі', 'Свой инструмент');
      payment.text = settleName(h.settleCycle);
    } else {
      scope.text = v?.scopeText.isNotEmpty == true ? v!.scopeText : d.title;
      pricing = v?.pricing ?? PricingMode.lumpSum;
      amount.text = v?.total?.round().toString() ?? '';
      if (v?.durationDays != null && start != null)
        end = start!.add(Duration(days: v!.durationDays!));
      materials.text = materialName(v?.materials ?? MaterialMode.labourOnly);
      open.text = v?.excludes.isNotEmpty == true
          ? '${tr3('不包含', 'Кірмейді', 'Не входит')}: ${v!.excludes}'
          : '';
    }
  }

  void done() {
    final a = parseInt(amount.text);
    if (scope.text.trim().isEmpty) {
      setState(
          () => error = tr3('请写明工作范围', 'Көлемді жазыңыз', 'Опишите объём'));
      return;
    }
    if (amount.text.trim().isNotEmpty && (a == null || a <= 0)) {
      setState(() => error = tr3('金额不正确', 'Сома қате', 'Неверная сумма'));
      return;
    }
    Navigator.pop(
        context,
        Agreement(
            version: 0,
            scope: scope.text,
            demandVersionNo: widget.demand.current.no,
            proposedBy: '',
            confirmedBy: const {},
            status: AgreementStatus.proposed,
            createdAt: DateTime.now(),
            headcount: hire ? parseInt(headcount.text) : null,
            amount: a,
            pricing: pricing,
            amountUnit: unit,
            startDate: start,
            endDate: end,
            paymentTerms: payment.text,
            materialsResponsibility: materials.text,
            openItems: open.text,
            shareExactAddress: shareAddress));
  }

  Widget _field(TextEditingController c, String label,
          {bool number = false, int lines = 1, String? hint}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              keyboardType: number ? TextInputType.number : null,
              minLines: lines,
              maxLines: lines + 2,
              decoration: InputDecoration(labelText: label, hintText: hint)));

  Future<void> pickDate(bool isStart) async {
    final v = await showDatePicker(
        context: context,
        firstDate: context.now.subtract(const Duration(days: 30)),
        lastDate: context.now.add(const Duration(days: 365)),
        initialDate: (isStart ? start : end) ?? context.now);
    if (v != null) setState(() => isStart ? start = v : end = v);
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return PageScaffold(
        title: widget.current == null
            ? tr3('合作约定', 'Келісім', 'Соглашение')
            : tr3('提出变更', 'Өзгеріс ұсыну', 'Предложить изменение'),
        bottom: FilledButton(
            onPressed: done,
            child: Text(widget.current == null
                ? tr3(
                    '发起并确认我方', 'Жіберу және растау', 'Отправить и подтвердить')
                : tr3(
                    '发送变更，待对方确认', 'Өзгерісті жіберу', 'Отправить изменение'))),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Hint(tr3(
              '这是双方的书面约定记录，不是具有特定法律效力的电子合同。双方分别确认后生效，修改会生成新版本，旧版本可查。',
              'Бұл екі жақтың жазбаша келісімі, заңды электрондық шарт емес.',
              'Это запись договорённостей сторон, а не юридический договор. Изменения создают новую версию.')),
          const SizedBox(height: 16),
          _field(scope, tr3('工作范围', 'Жұмыс көлемі', 'Объём работ'), lines: 2),
          if (hire)
            _field(headcount, tr3('录用人数', 'Адам саны', 'Человек'),
                number: true),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in PricingMode.values)
              FilterPill(
                  label: pricingName(p),
                  selected: pricing == p,
                  onTap: () => setState(() => pricing = p)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _field(amount, tr3('金额 ₸（可空）', 'Сома ₸', 'Сумма ₸'),
                    number: true)),
            const SizedBox(width: 10),
            DropdownButton<String>(
                value: unit,
                items: [
                  for (final u in const [
                    'total',
                    'day',
                    'hour',
                    'm3',
                    'm2',
                    'm',
                    'pcs',
                    't'
                  ])
                    DropdownMenuItem(
                        value: u,
                        child: Text(
                            u == 'total' ? unitLabel(u) : '/ ${unitLabel(u)}')),
                ],
                onChanged: (v) => setState(() => unit = v ?? 'total')),
          ]),
          ListTile(
              title: Text(tr3('开始', 'Басталуы', 'Начало')),
              subtitle: Text(fmtDay(start)),
              trailing: const Icon(Icons.event),
              onTap: () => pickDate(true)),
          ListTile(
              title: Text(tr3('预计结束', 'Аяқталуы', 'Окончание')),
              subtitle: Text(fmtDay(end)),
              trailing: const Icon(Icons.event),
              onTap: () => pickDate(false)),
          const SizedBox(height: 8),
          _field(payment, tr3('付款节点', 'Төлем кезеңдері', 'Порядок оплаты'),
              hint: tr3('例如：开工 30%，完工 70%', 'Мысалы: 30% / 70%',
                  'Напр.: 30% старт, 70% по завершении')),
          _field(materials,
              tr3('材料与工具责任', 'Материал мен құрал', 'Материалы и инструмент')),
          _field(
              open, tr3('待确认事项', 'Нақтыланатын мәселелер', 'Открытые вопросы'),
              lines: 2),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  tr3('向对方提供具体地址', 'Мекенжайды беру', 'Передать точный адрес')),
              value: shareAddress,
              onChanged: (v) => setState(() => shareAddress = v)),
          if (error != null) Hint(error!, warn: true),
        ]));
  }
}
