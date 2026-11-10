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
        cancel: tr3('取消', 'Болдырмау', 'Отмена'),
        ok: tr3('确定', 'Жарайды', 'ОК'),
        number: true,
        suffix: suffix);
    final parsed =
        double.tryParse((text ?? '').replaceAll(',', '.').replaceAll(' ', ''));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  Future<void> editPrice(CostLine line, Currency currency) async {
    final text = await promptText(context,
        title:
            '${costLineName(line.key)} · ${tr3('单价', 'Бірлік бағасы', 'Цена за единицу')} (${currencySymbol(currency)}/${unitName(line.unit)})',
        initial: '${line.price}',
        cancel: tr3('取消', 'Болдырмау', 'Отмена'),
        ok: tr3('确定', 'Жарайды', 'ОК'),
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
    final name = await askText(tr3('名称', 'Атауы', 'Наименование'), item?.name ?? '');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final unit = await askText(tr3('单位', 'Өлшем бірлігі', 'Единица измерения'), item?.unit ?? tr3('项', 'дана', 'шт.'));
    if (unit == null || !mounted) return;
    final quantity = await askNumber(tr3('数量', 'Мөлшері', 'Количество'), (item?.quantity ?? 100) / 100);
    if (quantity == null || !mounted) return;
    final c = history.present.extras.cost.currency ?? languageCurrency;
    final price = await askNumber(
        '${tr3('单价', 'Бірлік бағасы', 'Цена за единицу')} (${currencySymbol(c)})', item?.price ?? 0);
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
        label: tr3('货币', 'Валюта', 'Валюта'),
        value: e.currency,
        items: [for (final c in Currency.values) (c, currencyName(c))],
        onChanged: (c) {
          if (c == e.currency) return;
          action('SetCost', {'currency': c});
          notify(tr3('已换成${currencyName(c)}，单价改用该货币的示例价格',
              '${currencyName(c)} таңдалды, бағалар осы валютадағы мысалға ауысты', 'Выбрано: ${currencyName(c)}, цены заменены примерными в этой валюте'));
        });
    final summary = InfoCard(
        title: '${tr3('造价预算', 'Құрылыс сметасы', 'Смета строительства')} · ${cash(e.total)}',
        subtitle: tr3('按模型算出的工程量 × 单价。单价是 2026 年乡村自建房的大致示例，请换成当地报价。',
            'Модельден есептелген көлем × бірлік баға. Бағалар 2026 жылғы ауыл үйінің шамамен алынған мысалы, жергілікті бағамен ауыстырыңыз.', 'Объёмы, рассчитанные по модели, × цена за единицу. Цены — примерные для сельского дома в 2026 году, замените их местными.'),
        trailing: wide ? currency : null,
        children: [
          if (!wide)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(alignment: Alignment.centerLeft, child: currency)),
          KvGrid([
            Kv(cash(e.total), tr3('合计 (含人工和预备费)', 'Барлығы (жұмыс пен резервпен)', 'Итого (с работой и резервом)')),
            Kv('${cash(e.perArea)} / $unitM2', tr3('每平方米', 'Әр шаршы метрге', 'На квадратный метр')),
            Kv(cash(e.materials), tr3('材料', 'Материалдар', 'Материалы')),
            Kv('${cash(e.labour)} · ${e.labourPct}%', tr3('人工 (按材料比例)', 'Жұмыс ақысы (материалдан %)', 'Работа (% от материалов)'),
                onTap: () async {
              final v = await askNumber(tr3('人工占材料的百分比', 'Жұмыс ақысы, материалдан %', 'Работа, % от материалов'),
                  e.labourPct, suffix: '%');
              if (v != null) action('SetCost', {'labourPct': v.round()});
            }),
            Kv('${cash(e.contingency)} · ${e.contingencyPct}%', tr3('预备费', 'Күтпеген шығын резерві', 'Резерв на непредвиденные расходы'),
                onTap: () async {
              final v = await askNumber(tr3('预备费百分比', 'Резерв, %', 'Резерв, %'),
                  e.contingencyPct, suffix: '%');
              if (v != null) action('SetCost', {'contingencyPct': v.round()});
            }),
            Kv('${dec(e.buildingArea.toStringAsFixed(1))} $unitM2', tr3('建筑面积 (各层合计)', 'Құрылыс ауданы (барлық қабат)', 'Общая площадь (все этажи)')),
          ], minWidth: 150),
          Text(tr3('各阶段花费 (含人工)', 'Кезеңдер бойынша (жұмыспен)', 'По этапам (с работой)'),
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
                label: tr3('施工进度', 'Құрылыс кестесі', 'График строительства'),
                icon: Icons.event_note_outlined,
                onPressed: () => showTab('build')),
            if (spec.prices.isNotEmpty)
              Btn(
                  label: tr3('全部恢复示例单价', 'Барлық мысал бағаны қайтару', 'Вернуть все примерные цены'),
                  icon: Icons.restart_alt,
                  onPressed: () => action('SetCost', {'resetPrices': true})),
          ]),
        ]);
    Widget stageCard(String stage) {
      final lines = e.lines.where((l) => l.stage == stage && !l.custom);
      return InfoCard(
          title: '${costStageName(stage)} · ${cash(e.stageMaterials(stage))}',
          subtitle:
              '${tr3('另加人工', 'Жұмыс ақысы қосымша', 'Работа дополнительно')} ${cash(e.stageLabour(stage))}',
          children: [
            const SizedBox(height: 6),
            PlainTable(header: [
              tr3('项目', 'Атауы', 'Наименование'),
              tr3('数量', 'Мөлшері', 'Количество'),
              tr3('单价', 'Бағасы', 'Цена'),
              tr3('金额', 'Сомасы', 'Сумма'),
            ], rows: [
              for (final l in lines)
                [
                  TableCellData(
                      '${costLineName(l.key)}${l.estimated ? tr3(' (估)', ' (шамамен)', ' (прибл.)') : ''}',
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
            '${tr3('其他费用', 'Басқа шығындар', 'Прочие расходы')} · ${cash(e.stageMaterials('other'))}',
        subtitle: tr3('设计费、运输、手续费、家电等自己添加；不另加人工。',
            'Жобалау, тасымал, құжат, тұрмыстық техника т.б. өзіңіз қосасыз; жұмыс ақысы қосылмайды.', 'Проектирование, доставку, оформление документов, бытовую технику и т. п. добавьте сами; работа на них не начисляется.'),
        children: [
          if (spec.items.isNotEmpty) ...[
            const SizedBox(height: 6),
            PlainTable(header: [
              tr3('项目', 'Атауы', 'Наименование'),
              tr3('数量', 'Мөлшері', 'Количество'),
              tr3('单价', 'Бағасы', 'Цена'),
              tr3('金额', 'Сомасы', 'Сумма'),
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
                  label: tr3('添加费用', 'Шығын қосу', 'Добавить расход'),
                  icon: Icons.add,
                  onPressed: () => editCostItem(null))),
        ]);
    return page([
      summary,
      grid2([for (final s in stages.where((s) => s != 'other')) stageCard(s), own]),
      Note(tr3(
          '数量来自当前设计：改墙、门窗、基础或屋顶后会自动更新。标“估”的行还没有画水电点位，按面积粗估；在 2D 平面“水电”里布置点位后改为实算。点单价可修改，清空恢复示例价。高亮的是你改过的单价。',
          'Көлемдер қазіргі жобадан алынады: қабырға, есік-терезе, іргетас не шатыр өзгерсе, жаңарады. «Шамамен» жолдарда су-электр нүктелері әлі сызылмаған, ауданмен бағаланған; 2D жоспардағы «Су-электр» құралымен нүкте қойсаңыз, нақты есептеледі. Бағаны басып өзгертіңіз, бос қалдырсаңыз мысал баға қайтады. Түсі ерекшеленгені — сіз өзгерткен бағалар.', 'Объёмы берутся из текущего проекта: при изменении стен, окон и дверей, фундамента или крыши они обновляются. В строках с пометкой «оценка» точки электрики и воды ещё не расставлены, расчёт сделан по площади; расставьте точки инструментом «Электрика и вода» на 2D-плане — и расчёт станет точным. Нажмите на цену, чтобы изменить её; очистите поле — вернётся примерная цена. Цветом выделены цены, которые вы изменили.')),
    ]);
  }
}
