part of '../house_editor.dart';

/// The budget page: quantities from the model times unit prices, labour
/// and contingency, stage by stage. Every price, share and own line can be
/// edited; prices left alone use the examples of the chosen currency.
extension _CostTab on _HouseEditorState {
  CostEstimate get estimate =>
      estimateCost(history.present, derived, currency: languageCurrency);

  /// A number typed by the user; null when cancelled or not a number.
  Future<double?> askNumber(String title, num value, {String? suffix}) async {
    final text = await promptText(context,
        title: title,
        initial: value == value.roundToDouble()
            ? '${value.round()}'
            : value.toStringAsFixed(2),
        cancel: tr('取消', 'Болдырмау'),
        ok: tr('确定', 'Жарайды'),
        number: true,
        suffix: suffix);
    final parsed =
        double.tryParse((text ?? '').replaceAll(',', '.').replaceAll(' ', ''));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  Future<void> editPrice(CostLine line, Currency currency) async {
    final text = await promptText(context,
        title:
            '${costLineName(line.key)} · ${tr('单价', 'Бірлік бағасы')} (${currencySymbol(currency)}/${unitName(line.unit)})',
        initial: '${line.price}',
        cancel: tr('取消', 'Болдырмау'),
        ok: tr('确定', 'Жарайды'),
        number: true,
        suffix: '${currencySymbol(currency)}/${unitName(line.unit)}');
    if (text == null) return;
    final trimmed = text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (trimmed.isEmpty) {
      action('SetCost', {'priceKey': line.key, 'price': null});
      return;
    }
    final v = double.tryParse(trimmed);
    if (v != null && v.isFinite)
      action('SetCost', {'priceKey': line.key, 'price': v.round()});
  }

  Future<void> editCostItem(CostItem? item) async {
    final name = await askText(tr('名称', 'Атауы'), item?.name ?? '');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final unit = await askText(tr('单位', 'Өлшем бірлігі'), item?.unit ?? tr('项', 'дана'));
    if (unit == null || !mounted) return;
    final quantity = await askNumber(tr('数量', 'Мөлшері'), (item?.quantity ?? 100) / 100);
    if (quantity == null || !mounted) return;
    final c = history.present.extras.cost.currency ?? languageCurrency;
    final price = await askNumber(
        '${tr('单价', 'Бірлік бағасы')} (${currencySymbol(c)})', item?.price ?? 0);
    if (price == null) return;
    final args = {
      'name': name,
      'unit': unit,
      'quantity': (quantity * 100).round(),
      'price': price.round()
    };
    item == null
        ? action('AddCostItem', args)
        : action('UpdateCostItem', {'itemId': item.id, ...args});
  }

  Widget costTab(bool wide) {
    final t = Tokens.of(context);
    final e = estimate, spec = history.present.extras.cost;
    final sym = currencySymbol(e.currency);
    String cash(num v) => '$sym ${money(v)}';
    String qty(double v) =>
        dec(v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v >= 10 ? 1 : 2));
    final stages = [for (final s in costStages) if (e.stageMaterials(s) > 0) s];
    final currency = Seg<Currency>(
        label: tr('货币', 'Валюта'),
        value: e.currency,
        items: [for (final c in Currency.values) (c, currencyName(c))],
        onChanged: (c) {
          if (c == e.currency) return;
          action('SetCost', {'currency': c});
          notify(tr('已换成${currencyName(c)}，单价改用该货币的示例价格',
              '${currencyName(c)} таңдалды, бағалар осы валютадағы мысалға ауысты'));
        });
    final summary = InfoCard(
        title: '${tr('造价预算', 'Құрылыс сметасы')} · ${cash(e.total)}',
        subtitle: tr('按模型算出的工程量 × 单价。单价是 2026 年乡村自建房的大致示例，请换成当地报价。',
            'Модельден есептелген көлем × бірлік баға. Бағалар 2026 жылғы ауыл үйінің шамамен алынған мысалы, жергілікті бағамен ауыстырыңыз.'),
        trailing: wide ? currency : null,
        children: [
          if (!wide)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(alignment: Alignment.centerLeft, child: currency)),
          KvGrid([
            Kv(cash(e.total), tr('合计 (含人工和预备费)', 'Барлығы (жұмыс пен резервпен)')),
            Kv('${cash(e.perArea)} / $unitM2', tr('每平方米', 'Әр шаршы метрге')),
            Kv(cash(e.materials), tr('材料', 'Материалдар')),
            Kv('${cash(e.labour)} · ${e.labourPct}%', tr('人工 (按材料比例)', 'Жұмыс ақысы (материалдан %)'),
                onTap: () async {
              final v = await askNumber(tr('人工占材料的百分比', 'Жұмыс ақысы, материалдан %'),
                  e.labourPct, suffix: '%');
              if (v != null) action('SetCost', {'labourPct': v.round()});
            }),
            Kv('${cash(e.contingency)} · ${e.contingencyPct}%', tr('预备费', 'Күтпеген шығын резерві'),
                onTap: () async {
              final v = await askNumber(tr('预备费百分比', 'Резерв, %'),
                  e.contingencyPct, suffix: '%');
              if (v != null) action('SetCost', {'contingencyPct': v.round()});
            }),
            Kv('${dec(e.buildingArea.toStringAsFixed(1))} $unitM2', tr('建筑面积 (各层合计)', 'Құрылыс ауданы (барлық қабат)')),
          ], minWidth: 150),
          Text(tr('各阶段花费 (含人工)', 'Кезеңдер бойынша (жұмыспен)'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ShareBars([
            for (final s in stages)
              (
                costStageName(s),
                e.stageTotal(s),
                '${cash(e.stageTotal(s))} · ${(e.stageTotal(s) / math.max(1, e.materials + e.labour) * 100).round()}%'
              )
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('施工进度', 'Құрылыс кестесі'),
                icon: Icons.event_note_outlined,
                onPressed: () => showTab('build')),
            if (spec.prices.isNotEmpty)
              Btn(
                  label: tr('全部恢复示例单价', 'Барлық мысал бағаны қайтару'),
                  icon: Icons.restart_alt,
                  onPressed: () => action('SetCost', {'resetPrices': true})),
          ]),
        ]);
    Widget stageCard(String stage) {
      final lines = e.lines.where((l) => l.stage == stage && !l.custom);
      return InfoCard(
          title: '${costStageName(stage)} · ${cash(e.stageMaterials(stage))}',
          subtitle:
              '${tr('另加人工', 'Жұмыс ақысы қосымша')} ${cash(e.stageLabour(stage))}',
          children: [
            const SizedBox(height: 6),
            PlainTable(header: [
              tr('项目', 'Атауы'),
              tr('数量', 'Мөлшері'),
              tr('单价', 'Бағасы'),
              tr('金额', 'Сомасы'),
            ], rows: [
              for (final l in lines)
                [
                  TableCellData(
                      '${costLineName(l.key)}${l.estimated ? tr(' (估)', ' (шамамен)') : ''}',
                      muted: l.estimated),
                  TableCellData('${qty(l.quantity)} ${unitName(l.unit)}',
                      numeric: true),
                  TableCellData(money(l.price),
                      numeric: true,
                      highlight: spec.prices.containsKey(l.key),
                      onTap: () => editPrice(l, e.currency)),
                  TableCellData(money(l.total), numeric: true),
                ]
            ]),
          ]);
    }

    final own = InfoCard(
        title:
            '${tr('其他费用', 'Басқа шығындар')} · ${cash(e.stageMaterials('other'))}',
        subtitle: tr('设计费、运输、手续费、家电等自己添加；不另加人工。',
            'Жобалау, тасымал, құжат, тұрмыстық техника т.б. өзіңіз қосасыз; жұмыс ақысы қосылмайды.'),
        children: [
          if (spec.items.isNotEmpty) ...[
            const SizedBox(height: 6),
            PlainTable(header: [
              tr('项目', 'Атауы'),
              tr('数量', 'Мөлшері'),
              tr('单价', 'Бағасы'),
              tr('金额', 'Сомасы'),
              '',
            ], rows: [
              for (final item in spec.items)
                [
                  TableCellData(item.name, onTap: () => editCostItem(item)),
                  TableCellData(
                      '${dec((item.quantity / 100).toStringAsFixed(item.quantity % 100 == 0 ? 0 : 2))} ${item.unit}',
                      numeric: true),
                  TableCellData(money(item.price), numeric: true),
                  TableCellData(money(item.quantity / 100 * item.price),
                      numeric: true),
                  TableCellData('×',
                      color: t.crit,
                      onTap: () =>
                          action('DeleteCostItem', {'itemId': item.id})),
                ]
            ]),
          ],
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: Btn(
                  label: tr('添加费用', 'Шығын қосу'),
                  icon: Icons.add,
                  onPressed: () => editCostItem(null))),
        ]);
    return page([
      summary,
      grid2([for (final s in stages.where((s) => s != 'other')) stageCard(s), own]),
      Note(tr(
          '数量来自当前设计：改墙、门窗、基础或屋顶后会自动更新。标“估”的行还没有画水电点位，按面积粗估；在 2D 平面“水电”里布置点位后改为实算。点单价可修改，清空恢复示例价。高亮的是你改过的单价。',
          'Көлемдер қазіргі жобадан алынады: қабырға, есік-терезе, іргетас не шатыр өзгерсе, жаңарады. «Шамамен» жолдарда су-электр нүктелері әлі сызылмаған, ауданмен бағаланған; 2D жоспардағы «Су-электр» құралымен нүкте қойсаңыз, нақты есептеледі. Бағаны басып өзгертіңіз, бос қалдырсаңыз мысал баға қайтады. Түсі ерекшеленгені — сіз өзгерткен бағалар.')),
    ]);
  }
}
