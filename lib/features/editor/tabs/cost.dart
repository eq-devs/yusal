part of '../page.dart';

/// The budget page: quantities from the model times unit prices, labour
/// and contingency, stage by stage. Every price, share and own line can be
/// edited; prices left alone use the examples of the chosen currency.
extension _CostTab on _HouseEditorState {
  CostEstimate get estimate {
    syncPrices();
    return estimateCost(history.present, derived,
        currency: languageCurrency, book: priceBook);
  }

  /// Reads the price list of the design's region when the region or the
  /// currency changes; the estimate uses the built-in examples until it
  /// arrives, and again when there is none.
  void syncPrices() {
    final spec = history.present.extras.cost;
    final region = spec.region;
    final currency = spec.currency ?? languageCurrency;
    final key = region == null ? null : '${currency.name}/$region';
    if (key == priceBookKey) return;
    priceBookKey = key;
    priceBook = null;
    if (region == null) return;
    ref.read(priceRepositoryProvider).book(region, currency).then((book) {
      if (!mounted || priceBookKey != key || book == null) return;
      update(() {
        priceBook = book;
        costChipFor = null;
      });
    }, onError: (_) {});
  }

  Future<void> editLabour(CostLine line, Currency currency) async {
    final suffix = '${currencySymbol(currency)}/${unitName(line.unit)}';
    final text = await promptText(context,
        title:
            '${costLineName(line.key)} · ${tr3('人工单价', 'Жұмыс бағасы', 'Цена работы', 'Labour rate', ky: 'Жумуштун баасы', uz: 'Ish narxi')} ($suffix)',
        initial: '${line.labourRate}',
        cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel',
            ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'),
        number: true,
        suffix: suffix);
    if (text == null) return;
    final trimmed = text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (trimmed.isEmpty) {
      action('SetCost', {'labourKey': line.key, 'labourPrice': null});
      return;
    }
    final v = double.tryParse(trimmed);
    if (v != null && v.isFinite) {
      action('SetCost', {'labourKey': line.key, 'labourPrice': v.round()});
    }
  }

  /// Picks where the house is built, for that region's prices.
  Future<void> pickRegion() async {
    final t = Tokens.of(context);
    final current = history.present.extras.cost.region;
    final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
                backgroundColor: t.panel,
                title: Text(tr3('房子建在哪里', 'Үй қай жерде салынады',
                    'Где строится дом', 'Where the house is built',
                    ky: 'Үй кайда курулат', uz: 'Uy qayerda quriladi')),
                children: [
                  for (final r in priceRegions)
                    SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop(r),
                        child: Text(priceRegionName(r),
                            style: TextStyle(
                                color: t.ink,
                                fontWeight: r == current
                                    ? FontWeight.w700
                                    : FontWeight.w400))),
                  if (current != null)
                    SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop(''),
                        child: Text(
                            tr3(
                                '不按地区，用示例价',
                                'Аймақсыз, мысал бағамен',
                                'Без региона, примерные цены',
                                'No region, approximate prices',
                                ky: 'Аймаксыз, болжолдуу баалар',
                                uz: 'Hududsiz, taxminiy narxlar'),
                            style: TextStyle(color: t.muted))),
                ]));
    if (picked == null) return;
    action('SetCost', {'region': picked.isEmpty ? null : picked});
  }

  /// Sends the prices the user typed in to the region's price list.
  Future<void> sharePrices() async {
    final spec = history.present.extras.cost;
    final region = spec.region;
    if (region == null) return;
    final known = defaultPrices[Currency.kzt]!.keys.toSet();
    // Brick and cinder block are listed apart from the default masonry.
    String bookKey(String key) {
      final unit = key == 'masonryExt'
          ? spec.outerUnit
          : key == 'masonryInt'
              ? spec.innerUnit
              : MasonryUnit.aerated;
      return unit == MasonryUnit.aerated ? key : 'masonry_${unit.name}';
    }

    try {
      await ref
          .read(priceRepositoryProvider)
          .report(region, spec.currency ?? languageCurrency, [
        for (final e in spec.prices.entries)
          if (known.contains(e.key) && e.value > 0)
            (key: bookKey(e.key), labour: false, price: e.value),
        for (final e in spec.labourPrices.entries)
          if (known.contains(e.key) && e.value > 0)
            (key: e.key, labour: true, price: e.value),
      ]);
      notify(tr3(
          '已分享，谢谢。同地区的人会看到更准的价格',
          'Жіберілді, рақмет. Аймағыңыздағылар дәлірек баға көреді',
          'Отправлено, спасибо. Цены в вашем регионе станут точнее',
          'Sent, thank you. Prices in your region will get more accurate',
          ky: 'Жөнөтүлдү, рахмат. Аймагыңыздагы баалар тагыраак болот',
          uz: 'Yuborildi, rahmat. Hududingizdagi narxlar aniqroq boʻladi'));
    } catch (_) {
      notify(tr3(
          '暂时无法分享，请登录后再试',
          'Қазір жіберу мүмкін емес, кіріп, қайталап көріңіз',
          'Сейчас не удалось отправить; войдите и попробуйте снова',
          "Couldn't send now; sign in and try again",
          ky: 'Азыр жөнөтүү мүмкүн болбоду; кирип, кайра аракет кылыңыз',
          uz: 'Hozir yuborib boʻlmadi; kirib, qayta urinib koʻring'));
    }
  }

  String materialQuantity(MaterialLine l) {
    final v = l.quantity;
    final text = l.unit == 'pcs'
        ? '${v.round()}'
        : dec(v >= 100
            ? v.toStringAsFixed(0)
            : v.toStringAsFixed(v >= 10 ? 1 : 2));
    return '$text ${unitName(l.unit)}';
  }

  String materialPacks(MaterialLine l) => [
        if (l.packs != null) '${l.packs} ${packName(l.pack)}',
        if (l.weight != null)
          '${dec(l.weight! >= 100 ? l.weight!.toStringAsFixed(0) : l.weight!.toStringAsFixed(1))} ${unitName('kg')}',
      ].join(' · ');

  /// The shopping list as plain text, to send to a supplier.
  String materialsText(List<MaterialLine> list) {
    final doc = history.present;
    final out = StringBuffer()
      ..writeln(
          '${doc.meta.name} · ${tr3('材料清单', 'Материалдар тізімі', 'Список материалов', 'Materials list', ky: 'Материалдардын тизмеси', uz: 'Materiallar roʻyxati')}');
    String? stage;
    for (final l in list) {
      if (l.stage != stage) {
        stage = l.stage;
        out
          ..writeln()
          ..writeln('${costStageName(l.stage)}:');
      }
      final packs = materialPacks(l);
      out.writeln(
          '- ${buyName(l.key)}${l.detail.isEmpty ? '' : ' ${l.detail}'}: ${materialQuantity(l)}${packs.isEmpty ? '' : ' ($packs)'}');
    }
    return out.toString();
  }

  Future<void> shareMaterials(List<MaterialLine> list) async {
    final text = materialsText(list);
    try {
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: text));
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
            text: text,
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size));
        return;
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
    notify(tr3('材料清单已复制', 'Тізім көшірілді', 'Список скопирован', 'List copied',
        ky: 'Тизме көчүрүлдү', uz: 'Roʻyxat nusxalandi'));
  }

  /// A number typed by the user; null when cancelled or not a number.
  Future<double?> askNumber(String title, num value, {String? suffix}) async {
    final text = await promptText(context,
        title: title,
        initial: value == value.roundToDouble()
            ? '${value.round()}'
            : value.toStringAsFixed(2),
        cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'),
        number: true,
        suffix: suffix);
    final parsed =
        double.tryParse((text ?? '').replaceAll(',', '.').replaceAll(' ', ''));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  Future<void> editPrice(CostLine line, Currency currency) async {
    final text = await promptText(context,
        title:
            '${costLineName(line.key)} · ${tr3('单价', 'Бірлік бағасы', 'Цена за единицу', 'Unit price', ky: 'Бирдиктин баасы', uz: 'Birlik narxi')} (${currencySymbol(currency)}/${unitName(line.unit)})',
        initial: '${line.price}',
        cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'),
        number: true,
        suffix: '${currencySymbol(currency)}/${unitName(line.unit)}');
    if (text == null) return;
    final trimmed = text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (trimmed.isEmpty) {
      action('SetCost', {'priceKey': line.key, 'price': null});
      return;
    }
    final v = double.tryParse(trimmed);
    if (v != null && v.isFinite) {
      action('SetCost', {'priceKey': line.key, 'price': v.round()});
    }
  }

  Future<void> editCostItem(CostItem? item) async {
    final name =
        await askText(tr3('名称', 'Атауы', 'Наименование', 'Name', ky: 'Аталышы', uz: 'Nomi'), item?.name ?? '');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final unit = await askText(tr3('单位', 'Өлшем бірлігі', 'Единица измерения', 'Unit', ky: 'Бирдик', uz: 'Birlik'),
        item?.unit ?? tr3('项', 'дана', 'шт.', 'pcs', ky: 'даана', uz: 'dona'));
    if (unit == null || !mounted) return;
    final quantity = await askNumber(
        tr3('数量', 'Мөлшері', 'Количество', 'Quantity', ky: 'Саны', uz: 'Miqdori'), (item?.quantity ?? 100) / 100);
    if (quantity == null || !mounted) return;
    final c = history.present.extras.cost.currency ?? languageCurrency;
    final price = await askNumber(
        '${tr3('单价', 'Бірлік бағасы', 'Цена за единицу', 'Unit price', ky: 'Бирдиктин баасы', uz: 'Birlik narxi')} (${currencySymbol(c)})',
        item?.price ?? 0);
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
    Widget setting(String label, Widget control) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 12, color: Tokens.of(context).muted)),
              const SizedBox(height: 4),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: control),
            ]);
    final t = Tokens.of(context);
    final e = estimate;
    final spec = history.present.extras.cost;
    final sym = currencySymbol(e.currency);
    String cash(num v) => '$sym ${groupDigits(v)}';
    String qty(double v) => dec(
        v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v >= 10 ? 1 : 2));
    final stages = [
      for (final s in costStages)
        if (e.stageMaterials(s) > 0) s
    ];
    final currency = Seg<Currency>(
        label: tr3('货币', 'Валюта', 'Валюта', 'Currency', ky: 'Валюта', uz: 'Valyuta'),
        value: e.currency,
        items: [for (final c in Currency.values) (c, currencyName(c))],
        onChanged: (c) {
          if (c == e.currency) return;
          if (action('SetCost', {'currency': c}) is! Applied) return;
          notify(tr3(
              '已换成${currencyName(c)}，单价改用该货币的示例价格',
              '${currencyName(c)} таңдалды, бағалар осы валютадағы мысалға ауысты',
              'Выбрано: ${currencyName(c)}, цены заменены примерными в этой валюте',
              'Selected: ${currencyName(c)}; prices replaced with approximate ones in this currency', ky: 'Тандалды: ${currencyName(c)}; баалар ушул валютадагы болжолдуу бааларга алмаштырылды', uz: 'Tanlandi: ${currencyName(c)}; narxlar shu valyutadagi taxminiy narxlarga almashtirildi'));
        });
    final summary = InfoCard(
        title:
            '${tr3('造价预算', 'Құрылыс сметасы', 'Смета строительства', 'Construction estimate', ky: 'Курулуш сметасы', uz: 'Qurilish smetasi')} · ${cash(e.total)}',
        subtitle: tr3(
            '按模型算出的工程量 × 单价。单价是 2026 年乡村自建房的大致示例，请换成当地报价。',
            'Модельден есептелген көлем × бірлік баға. Бағалар 2026 жылғы ауыл үйінің шамамен алынған мысалы, жергілікті бағамен ауыстырыңыз.',
            'Объёмы, рассчитанные по модели, × цена за единицу. Цены — примерные для сельского дома в 2026 году, замените их местными.',
            'Quantities from the model × unit price. Prices are approximate for a rural house in 2026; replace them with local ones.', ky: 'Моделдеги көлөм × бирдиктин баасы. Баалар 2026-жылдагы айылдык үй үчүн болжолдуу; жергиликтүү бааларга алмаштырыңыз.', uz: 'Modeldagi miqdor × birlik narxi. Narxlar 2026-yil uchun qishloq uyi boʻyicha taxminiy; mahalliy narxlarga almashtiring.'),
        trailing: wide ? currency : null,
        children: [
          if (!wide)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(alignment: Alignment.centerLeft, child: currency)),
          KvGrid([
            Kv(
                cash(e.total),
                tr3('合计 (含人工和预备费)', 'Барлығы (жұмыс пен резервпен)',
                    'Итого (с работой и резервом)',
                    'Total (with labour and contingency)',
                    ky: 'Бардыгы (жумуш жана күтүлбөгөн чыгымдар менен)',
                    uz: 'Jami (ish haqi va kutilmagan xarajatlar bilan)')),
            Kv(
                '${cash(e.low)} – ${groupDigits(e.high)}',
                tr3(
                    '可能的区间 (±${(e.spreadShare * 100).round()}%)',
                    'Ықтимал аралық (±${(e.spreadShare * 100).round()}%)',
                    'Возможный диапазон (±${(e.spreadShare * 100).round()}%)',
                    'Likely range (±${(e.spreadShare * 100).round()}%)',
                    ky: 'Мүмкүн болгон аралык (±${(e.spreadShare * 100).round()}%)',
                    uz: 'Ehtimoliy oraliq (±${(e.spreadShare * 100).round()}%)')),
            Kv(
                '${cash(e.perArea)} / $unitM2',
                tr3('每平方米', 'Әр шаршы метрге', 'На квадратный метр',
                    'Per square metre',
                    ky: 'Бир чарчы метрге', uz: 'Bir kvadrat metrga')),
            Kv(
                cash(e.materials),
                tr3('材料', 'Материалдар', 'Материалы', 'Materials',
                    ky: 'Материалдар', uz: 'Materiallar')),
            if (e.labourByWork)
              Kv(
                  cash(e.labour),
                  tr3('人工 (按工程量)', 'Жұмыс ақысы (көлем бойынша)',
                      'Работа (по объёму)', 'Labour (by work done)',
                      ky: 'Жумуш (көлөм боюнча)',
                      uz: 'Ish haqi (hajm boʻyicha)'))
            else
              Kv(
                  '${cash(e.labour)} · ${e.labourPct}%',
                  tr3('人工 (按材料比例)', 'Жұмыс ақысы (материалдан %)',
                      'Работа (% от материалов)', 'Labour (% of materials)',
                      ky: 'Жумуш (материалдардын %)',
                      uz: 'Ish haqi (materiallarning %)'), onTap: () async {
                final v = await askNumber(
                    tr3('人工占材料的百分比', 'Жұмыс ақысы, материалдан %',
                        'Работа, % от материалов', 'Labour, % of materials',
                        ky: 'Жумуш, материалдардын %',
                        uz: 'Ish haqi, materiallarning %'),
                    e.labourPct,
                    suffix: '%');
                if (v != null) action('SetCost', {'labourPct': v.round()});
              }),
            Kv(
                '${cash(e.contingency)} · ${e.contingencyPct}%',
                tr3('预备费', 'Күтпеген шығын резерві',
                    'Резерв на непредвиденные расходы',
                    'Contingency', ky: 'Күтүлбөгөн чыгымдар', uz: 'Kutilmagan xarajatlar'), onTap: () async {
              final v = await askNumber(
                  tr3('预备费百分比', 'Резерв, %', 'Резерв, %', 'Contingency, %', ky: 'Күтүлбөгөн чыгымдар, %', uz: 'Kutilmagan xarajatlar, %'), e.contingencyPct,
                  suffix: '%');
              if (v != null) action('SetCost', {'contingencyPct': v.round()});
            }),
            Kv(
                '${dec(e.buildingArea.toStringAsFixed(1))} $unitM2',
                tr3('建筑面积 (各层合计)', 'Құрылыс ауданы (барлық қабат)',
                    'Общая площадь (все этажи)',
                    'Total area (all floors)', ky: 'Жалпы аянт (бардык кабаттар)', uz: 'Umumiy maydon (barcha qavatlar)')),
          ], minWidth: 150),
          Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (e.currency == Currency.kzt)
                  Btn(
                      label: spec.region == null
                          ? tr3(
                              '选择地区，用当地价格',
                              'Аймақты таңдап, жергілікті баға алу',
                              'Выбрать регион и местные цены',
                              'Pick a region for local prices',
                              ky: 'Аймакты тандап, жергиликтүү бааларды алуу',
                              uz: 'Hududni tanlab, mahalliy narxlarni olish')
                          : '${tr3('地区', 'Аймақ', 'Регион', 'Region', ky: 'Аймак', uz: 'Hudud')}: ${priceRegionName(spec.region!)}',
                      icon: YIcons.location,
                      onPressed: pickRegion),
                setting(
                    tr3('人工怎么算', 'Жұмыс ақысы қалай есептеледі',
                        'Как считать работу', 'How labour is priced',
                        ky: 'Жумуш кантип эсептелет',
                        uz: 'Ish haqi qanday hisoblanadi'),
                    Seg<bool>(
                        value: e.labourByWork,
                        items: [
                          (
                            false,
                            tr3('按材料比例', 'Материалдан %', '% от материалов',
                                '% of materials',
                                ky: 'Материалдардын %', uz: 'Materiallarning %')
                          ),
                          (
                            true,
                            tr3('按工程量', 'Көлем бойынша', 'По объёму',
                                'By work done',
                                ky: 'Көлөм боюнча', uz: 'Hajm boʻyicha')
                          ),
                        ],
                        onChanged: (v) {
                          if (v != e.labourByWork) {
                            action('SetCost', {'labourByWork': v});
                          }
                        })),
                setting(
                    tr3('外墙用什么砌', 'Сыртқы қабырға неден қаланады',
                        'Из чего наружные стены', 'Outer walls are built of',
                        ky: 'Сырткы дубал эмнеден тургузулат',
                        uz: 'Tashqi devor nimadan teriladi'),
                    Seg<MasonryUnit>(
                        value: spec.outerUnit,
                        items: [
                          for (final u in MasonryUnit.values)
                            (u, masonryUnitName(u))
                        ],
                        onChanged: (u) {
                          if (u != spec.outerUnit) {
                            action('SetCost', {'outerUnit': u});
                          }
                        })),
                setting(
                    tr3('内墙用什么砌', 'Ішкі қабырға неден қаланады',
                        'Из чего внутренние стены', 'Inner walls are built of',
                        ky: 'Ички дубал эмнеден тургузулат',
                        uz: 'Ichki devor nimadan teriladi'),
                    Seg<MasonryUnit>(
                        value: spec.innerUnit,
                        items: [
                          for (final u in MasonryUnit.values)
                            (u, masonryUnitName(u))
                        ],
                        onChanged: (u) {
                          if (u != spec.innerUnit) {
                            action('SetCost', {'innerUnit': u});
                          }
                        })),
              ]),
          if (e.examplePrices > 0)
            Note(tr3(
                '还有 ${e.examplePrices} 项用的是示例价。点单价填入当地报价${e.currency == Currency.kzt && spec.region == null ? '，或先选择地区' : ''}，区间就会变窄。',
                'Әлі ${e.examplePrices} жол мысал бағамен есептелген. Бағаны басып, жергілікті бағаны енгізіңіз${e.currency == Currency.kzt && spec.region == null ? ' не аймақты таңдаңыз' : ''} — аралық тарылады.',
                'Ещё ${e.examplePrices} строк посчитаны по примерным ценам. Нажмите на цену и введите местную${e.currency == Currency.kzt && spec.region == null ? ' или выберите регион' : ''} — диапазон станет уже.',
                '${e.examplePrices} lines still use approximate prices. Tap a price to enter a local one${e.currency == Currency.kzt && spec.region == null ? ', or pick a region' : ''}, and the range narrows.',
                ky: 'Дагы ${e.examplePrices} сап болжолдуу баа менен эсептелген. Бааны басып, жергиликтүү бааны киргизиңиз${e.currency == Currency.kzt && spec.region == null ? ' же аймакты тандаңыз' : ''} — аралык тараят.',
                uz: 'Yana ${e.examplePrices} qator taxminiy narx bilan hisoblangan. Narxni bosib, mahalliy narxni kiriting${e.currency == Currency.kzt && spec.region == null ? ' yoki hududni tanlang' : ''} — oraliq torayadi.')),
          const SizedBox(height: 10),
          Text(
              tr3('各阶段花费 (含人工)', 'Кезеңдер бойынша (жұмыспен)',
                  'По этапам (с работой)',
                  'By stage (with labour)', ky: 'Этаптар боюнча (жумуш менен)', uz: 'Bosqichlar boʻyicha (ish haqi bilan)'),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                label: tr3('施工进度', 'Құрылыс кестесі', 'График строительства', 'Build schedule', ky: 'Курулуш графиги', uz: 'Qurilish jadvali'),
                icon: YIcons.calendar,
                onPressed: () => showTab('build')),
            if (spec.prices.isNotEmpty)
              Btn(
                  label: tr3('全部恢复示例单价', 'Барлық мысал бағаны қайтару',
                      'Вернуть все примерные цены',
                      'Restore all approximate prices', ky: 'Бардык болжолдуу бааларды калыбына келтирүү', uz: 'Barcha taxminiy narxlarni tiklash'),
                  icon: YIcons.refresh,
                  onPressed: () => action('SetCost', {'resetPrices': true})),
            if (spec.region != null &&
                (spec.prices.isNotEmpty || spec.labourPrices.isNotEmpty))
              Btn(
                  label: tr3(
                      '把我的报价分享给同地区的人',
                      'Бағамды аймағыммен бөлісу',
                      'Поделиться моими ценами с регионом',
                      'Share my prices with my region',
                      ky: 'Бааларымды аймагым менен бөлүшүү',
                      uz: 'Narxlarimni hududim bilan boʻlishish'),
                  icon: YIcons.share,
                  onPressed: sharePrices),
          ]),
        ]);
    Widget stageCard(String stage) {
      final lines = e.lines.where((l) => l.stage == stage && !l.custom);
      final self = e.selfBuild.contains(stage);
      final hasLabour = lines.any((l) => !l.service);
      return InfoCard(
          title: '${costStageName(stage)} · ${cash(e.stageMaterials(stage))}',
          subtitle: !hasLabour
              ? null
              : self
                  ? tr3(
                      '自己干，不计人工',
                      'Өзіміз істейміз, жұмыс ақысы есептелмейді',
                      'Делаем сами, работа не начисляется',
                      'We build it ourselves; no labour charged',
                      ky: 'Өзүбүз жасайбыз, жумуш акысы эсептелбейт',
                      uz: 'Oʻzimiz qilamiz, ish haqi hisoblanmaydi')
                  : '${tr3('另加人工', 'Жұмыс ақысы қосымша', 'Работа дополнительно', 'Extra labour', ky: 'Кошумча жумуш', uz: 'Qoʻshimcha ish')} ${cash(e.stageLabour(stage))}',
          trailing: !hasLabour
              ? null
              : Btn(
                  label: self
                      ? tr3('✓ 自己干', '✓ Өзіміз', '✓ Сами', '✓ Self-build',
                          ky: '✓ Өзүбүз', uz: '✓ Oʻzimiz')
                      : tr3('自己干', 'Өзіміз', 'Сами', 'Self-build',
                          ky: 'Өзүбүз', uz: 'Oʻzimiz'),
                  onPressed: () =>
                      action('SetCost', {'selfStage': stage, 'self': !self})),
          children: [
            const SizedBox(height: 6),
            PlainTable(header: [
              tr3('项目', 'Атауы', 'Наименование', 'Item', ky: 'Аталышы', uz: 'Nomi'),
              tr3('数量', 'Мөлшері', 'Количество', 'Quantity', ky: 'Саны', uz: 'Miqdori'),
              tr3('单价', 'Бағасы', 'Цена', 'Price', ky: 'Баасы', uz: 'Narxi'),
              if (e.labourByWork && !self)
                tr3('人工单价', 'Жұмыс', 'Работа', 'Labour',
                    ky: 'Жумуш', uz: 'Ish'),
              tr3('金额', 'Сомасы', 'Сумма', 'Amount',
                  ky: 'Суммасы', uz: 'Summa'),
            ], rows: [
              for (final l in lines)
                [
                  TableCellData(
                      '${costLineName(l.key)}${l.estimated ? tr3(' (估)', ' (шамамен)', ' (прибл.)', ' (approx.)', ky: ' (болжол менен)', uz: ' (taxminan)') : ''}',
                      muted: l.estimated),
                  TableCellData('${qty(l.quantity)} ${unitName(l.unit)}',
                      numeric: true),
                  TableCellData(
                      '${groupDigits(l.price)}${l.source == PriceSource.region ? ' ◆' : ''}',
                      numeric: true,
                      highlight: spec.prices.containsKey(l.key),
                      onTap: () => editPrice(l, e.currency)),
                  if (e.labourByWork && !self)
                    l.service
                        ? const TableCellData('—', numeric: true, muted: true)
                        : TableCellData(groupDigits(l.labourRate),
                            numeric: true,
                            highlight: l.ownLabour,
                            onTap: () => editLabour(l, e.currency)),
                  TableCellData(
                      groupDigits(
                          l.total + e.lineLabour(l) * (e.labourByWork ? 1 : 0)),
                      numeric: true),
                ]
            ]),
          ]);
    }

    final own = InfoCard(
        title:
            '${tr3('其他费用', 'Басқа шығындар', 'Прочие расходы', 'Other costs', ky: 'Башка чыгымдар', uz: 'Boshqa xarajatlar')} · ${cash(e.stageMaterials('other'))}',
        subtitle: tr3(
            '设计费、运输、手续费、家电等自己添加；不另加人工。',
            'Жобалау, тасымал, құжат, тұрмыстық техника т.б. өзіңіз қосасыз; жұмыс ақысы қосылмайды.',
            'Проектирование, доставку, оформление документов, бытовую технику и т. п. добавьте сами; работа на них не начисляется.',
            'Add design, delivery, paperwork, appliances and the like yourself; no labour is charged on them.', ky: 'Долбоорлоо, жеткирүү, документтер, техника сыяктууларды өзүңүз кошуңуз; аларга жумуш акысы кошулбайт.', uz: 'Loyihalash, yetkazib berish, hujjatlar, texnika kabilarni oʻzingiz qoʻshing; ularga ish haqi qoʻshilmaydi.'),
        children: [
          if (spec.items.isNotEmpty) ...[
            const SizedBox(height: 6),
            PlainTable(header: [
              tr3('项目', 'Атауы', 'Наименование', 'Item', ky: 'Аталышы', uz: 'Nomi'),
              tr3('数量', 'Мөлшері', 'Количество', 'Quantity', ky: 'Саны', uz: 'Miqdori'),
              tr3('单价', 'Бағасы', 'Цена', 'Price', ky: 'Баасы', uz: 'Narxi'),
              tr3('金额', 'Сомасы', 'Сумма', 'Amount', ky: 'Суммасы', uz: 'Summa'),
              '',
            ], rows: [
              for (final item in spec.items)
                [
                  TableCellData(item.name, onTap: () => editCostItem(item)),
                  TableCellData(
                      '${dec((item.quantity / 100).toStringAsFixed(item.quantity % 100 == 0 ? 0 : 2))} ${item.unit}',
                      numeric: true),
                  TableCellData(groupDigits(item.price), numeric: true),
                  TableCellData(groupDigits(item.quantity / 100 * item.price),
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
                  label: tr3('添加费用', 'Шығын қосу', 'Добавить расход', 'Add a cost', ky: 'Чыгым кошуу', uz: 'Xarajat qoʻshish'),
                  icon: YIcons.add,
                  onPressed: () => editCostItem(null))),
        ]);
    final list = materialList(history.present, derived, estimate: e);
    final listStages = [
      for (final st in costStages)
        if (list.any((l) => l.stage == st)) st
    ];
    final regional = e.lines
        .where((l) => l.source == PriceSource.region)
        .map((l) => l.quote)
        .whereType<PriceQuote>()
        .toList();
    final materials = InfoCard(
        title: tr3(
            '材料清单', 'Материалдар тізімі', 'Список материалов', 'Materials list',
            ky: 'Материалдардын тизмеси', uz: 'Materiallar roʻyxati'),
        subtitle: tr3(
            '要买什么、买多少：已加损耗，并按整袋、整根、整卷取整。可以直接发给建材店报价。',
            'Не және қанша сатып алу керек: ысырап қосылған, тұтас қап, шыбық, орамға дейін дөңгелектелген. Құрылыс дүкеніне жіберіп, баға сұрауға болады.',
            'Что и сколько купить: с запасом на потери и с округлением до целых мешков, прутков и рулонов. Список можно отправить в магазин стройматериалов.',
            'What to buy and how much: waste included, rounded up to whole bags, bars and rolls. Send it to a builders’ merchant for a quote.',
            ky: 'Эмнени жана канча сатып алуу керек: ысырап кошулган, бүтүн кап, чыбык, түрмөккө чейин тегеректелген. Курулуш дүкөнүнө жөнөтсөңүз болот.',
            uz: 'Nima va qancha sotib olish kerak: isrof qoʻshilgan, butun qop, sterjen, oʻramgacha yaxlitlangan. Qurilish doʻkoniga yuborishingiz mumkin.'),
        children: [
          const SizedBox(height: 8),
          Align(
              alignment: AlignmentDirectional.centerStart,
              child: Btn(
                  label: kIsWeb
                      ? tr3('复制清单', 'Тізімді көшіру', 'Скопировать список',
                          'Copy the list',
                          ky: 'Тизмени көчүрүү', uz: 'Roʻyxatni nusxalash')
                      : tr3('分享清单', 'Тізіммен бөлісу', 'Поделиться списком',
                          'Share the list',
                          ky: 'Тизме менен бөлүшүү', uz: 'Roʻyxatni ulashish'),
                  icon: YIcons.share,
                  onPressed: () => shareMaterials(list))),
          for (final st in listStages) ...[
            Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(costStageName(st),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
            PlainTable(header: [
              tr3('材料', 'Материал', 'Материал', 'Material',
                  ky: 'Материал', uz: 'Material'),
              tr3('规格', 'Өлшемі', 'Размер', 'Size',
                  ky: 'Өлчөмү', uz: 'Oʻlchami'),
              tr3('要买', 'Сатып алу', 'Купить', 'To buy',
                  ky: 'Сатып алуу', uz: 'Sotib olish'),
              tr3('整包', 'Тұтас қаптама', 'Упаковок', 'Packs',
                  ky: 'Таңгак', uz: 'Qadoq'),
            ], rows: [
              for (final l in list.where((l) => l.stage == st))
                [
                  TableCellData(
                      '${buyName(l.key)}${l.estimated ? tr3(' (估)', ' (шамамен)', ' (прибл.)', ' (approx.)', ky: ' (болжол менен)', uz: ' (taxminan)') : ''}',
                      muted: l.estimated),
                  TableCellData(l.detail, muted: true),
                  TableCellData(
                      '${materialQuantity(l)}${l.waste > 0 ? ' (+${l.waste}%)' : ''}',
                      numeric: true),
                  TableCellData(materialPacks(l), numeric: true),
                ]
            ]),
          ],
          Note(tr3(
              '用量按常见做法估算：加气块用薄层胶并每四皮放两根 Ø8 钢筋，每层墙顶一道 200 mm 圈梁 (4Ø12)，洞口上方过梁每端搭 250 mm，椽子间距 600 mm。结构配筋以工程师的设计为准，下单前请和施工队核对。',
              'Мөлшер әдеттегі тәсілмен есептелген: газоблок жұқа желімге қаланып, әр төртінші қатарға екі Ø8 шыбық салынады; әр қабат қабырғасының үстінде 200 мм белдеу (4Ø12); ойық үстіндегі аражабын әр жағынан 250 мм тіреледі; стропила қадамы 600 мм. Арматураны инженер жобасы анықтайды, тапсырыс алдында құрылысшымен тексеріңіз.',
              'Расход посчитан по обычной практике: газоблок на тонком клее с двумя прутками Ø8 в каждом четвёртом ряду, армопояс 200 мм (4Ø12) поверх стен каждого этажа, перемычки с опиранием по 250 мм, стропила с шагом 600 мм. Армирование определяет проект инженера; перед заказом сверьтесь с бригадой.',
              'Quantities follow common practice: aerated blocks on thin adhesive with two Ø8 bars every fourth course, a 200 mm reinforced belt (4Ø12) on top of each floor’s walls, lintels resting 250 mm each side, rafters every 600 mm. Reinforcement is for an engineer to design; check with your builder before ordering.',
              ky: 'Чыгым кадимки ыкма боюнча эсептелген: газоблок жука желимге тизилип, ар бир төртүнчү катарга эки Ø8 чыбык коюлат; ар бир кабаттын дубалынын үстүндө 200 мм кур (4Ø12); тешик үстүндөгү устун ар тараптан 250 мм таянат; стропила кадамы 600 мм. Арматураны инженердин долбоору аныктайт; буйрутма алдында бригада менен текшериңиз.',
              uz: 'Sarf odatiy amaliyot boʻyicha hisoblangan: gazoblok yupqa yelimga terilib, har toʻrtinchi qatorga ikkita Ø8 sterjen qoʻyiladi; har qavat devori ustida 200 mm belbogʻ (4Ø12); teshik ustidagi toʻsin har tomondan 250 mm tayanadi; stropila qadami 600 mm. Armaturani muhandis loyihasi belgilaydi; buyurtmadan oldin brigada bilan tekshiring.')),
        ]);
    return page([
      summary,
      grid2([
        for (final s in stages.where((s) => s != 'other')) stageCard(s),
        own
      ]),
      materials,
      if (regional.isNotEmpty)
        Note(tr3(
            '◆ 是${priceRegionName(spec.region ?? 'kz')}的地区价，来源：${regional.map((q) => priceSourceName(q.source)).toSet().join('、')}；最新日期 ${regional.map((q) => q.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b)}。',
            '◆ — ${priceRegionName(spec.region ?? 'kz')} аймағының бағасы, дереккөз: ${regional.map((q) => priceSourceName(q.source)).toSet().join(', ')}; соңғы күні ${regional.map((q) => q.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b)}.',
            '◆ — цена региона «${priceRegionName(spec.region ?? 'kz')}», источник: ${regional.map((q) => priceSourceName(q.source)).toSet().join(', ')}; последняя дата ${regional.map((q) => q.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b)}.',
            '◆ marks a price of the region “${priceRegionName(spec.region ?? 'kz')}”, source: ${regional.map((q) => priceSourceName(q.source)).toSet().join(', ')}; latest date ${regional.map((q) => q.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b)}.',
            ky: '◆ — «${priceRegionName(spec.region ?? 'kz')}» аймагынын баасы, булак: ${regional.map((q) => priceSourceName(q.source)).toSet().join(', ')}; акыркы күнү ${regional.map((q) => q.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b)}.',
            uz: '◆ — “${priceRegionName(spec.region ?? 'kz')}” hududi narxi, manba: ${regional.map((q) => priceSourceName(q.source)).toSet().join(', ')}; oxirgi sana ${regional.map((q) => q.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b)}.')),
      Note(tr3(
          '数量来自当前设计：改墙、门窗、基础或屋顶后会自动更新。标“估”的行还没有画水电点位，按面积粗估；在 2D 平面“水电”里布置点位后改为实算。点单价可修改，清空恢复示例价。高亮的是你改过的单价。',
          'Көлемдер қазіргі жобадан алынады: қабырға, есік-терезе, іргетас не шатыр өзгерсе, жаңарады. «Шамамен» жолдарда су-электр нүктелері әлі сызылмаған, ауданмен бағаланған; 2D жоспардағы «Су-электр» құралымен нүкте қойсаңыз, нақты есептеледі. Бағаны басып өзгертіңіз, бос қалдырсаңыз мысал баға қайтады. Түсі ерекшеленгені — сіз өзгерткен бағалар.',
          'Объёмы берутся из текущего проекта: при изменении стен, окон и дверей, фундамента или крыши они обновляются. В строках с пометкой «оценка» точки электрики и воды ещё не расставлены, расчёт сделан по площади; расставьте точки инструментом «Электрика и вода» на 2D-плане — и расчёт станет точным. Нажмите на цену, чтобы изменить её; очистите поле — вернётся примерная цена. Цветом выделены цены, которые вы изменили.',
          "Quantities come from the current design and update when you change walls, windows and doors, the foundation or the roof. In rows marked “estimate”, electrical and water points aren't placed yet and the figure is based on area; place points with the “Electrical and water” tool on the 2D plan and the figure becomes exact. Tap a price to change it; clear the field to get the approximate price back. Prices you changed are highlighted.", ky: 'Көлөмдөр учурдагы долбоордон алынат жана дубалдарды, терезе-эшиктерди, пайдубалды же чатырды өзгөрткөндө жаңыланат. «Болжолдуу» деп белгиленген саптарда электр жана суу чекиттери али коюлган эмес, сан аянттан эсептелет; 2D планда «Электр жана суу» аспабы менен чекиттерди койсоңуз, сан так болот. Бааны өзгөртүү үчүн басыңыз; болжолдуу бааны кайтаруу үчүн талааны тазалаңыз. Сиз өзгөрткөн баалар белгиленет.', uz: 'Miqdorlar joriy loyihadan olinadi va devorlar, deraza-eshiklar, poydevor yoki tomni oʻzgartirganda yangilanadi. “Taxminiy” deb belgilangan qatorlarda elektr va suv nuqtalari hali qoʻyilmagan, son maydondan hisoblanadi; 2D rejada “Elektr va suv” asbobi bilan nuqtalarni qoʻysangiz, son aniq boʻladi. Narxni oʻzgartirish uchun bosing; taxminiy narxni qaytarish uchun maydonni tozalang. Siz oʻzgartirgan narxlar ajratib koʻrsatiladi.')),
    ]);
  }
}
