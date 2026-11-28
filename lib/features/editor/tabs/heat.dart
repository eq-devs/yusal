part of '../page.dart';

/// Insulation and heating: the heat the house loses on the coldest day,
/// where it goes, how big a boiler it needs and the fuel for a winter.
/// Climate, U-values of windows and doors and every layer's conductivity
/// can be edited here.
extension _HeatTab on _HouseEditorState {
  Widget heatTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final loss = heatLoss(doc, derived);
    final spec = doc.extras.heat;
    String kw(double w) => dec((w / 1000).toStringAsFixed(1));
    String w0(double w) => groupDigits(w);
    String u(double v) => dec(v.toStringAsFixed(2));
    Future<void> editInt(String field, String title, {String? suffix}) async {
      final v = await askNumber(title, spec.ints[field]!, suffix: suffix);
      if (v != null) action('SetHeat', {'field': field, 'value': v.round()});
    }

    Future<void> editHundredths(String field, String title,
        {String? suffix}) async {
      final v = await askNumber(title, spec.ints[field]! / 100, suffix: suffix);
      if (v != null) {
        action('SetHeat', {'field': field, 'value': (v * 100).round()});
      }
    }

    final summary = InfoCard(
        title:
            '${tr3('保温与采暖', 'Жылу оқшаулау және жылыту', 'Утепление и отопление', 'Insulation and heating', ky: 'Жылуулоо жана жылытуу', uz: 'Issiqlik izolyatsiyasi va isitish')} · ${kw(loss.total)} kW',
        subtitle: tr3(
            '最冷天 (室外 ${spec.outdoor} °C、室内 ${spec.indoor} °C) 全屋需要补的热量。未扣除人体、做饭和日照得热，结果偏保守。',
            'Ең суық күні (сыртта ${spec.outdoor} °C, ішінде ${spec.indoor} °C) үйге керек жылу. Адам, ас пісіру және күн жылуы шегерілмеген, сондықтан нәтиже қорлы.',
            'Тепло, необходимое дому в самый холодный день (снаружи ${spec.outdoor} °C, внутри ${spec.indoor} °C). Тепло от людей, готовки и солнца не вычтено, поэтому результат с запасом.',
            "Heat the house needs on the coldest day (outside ${spec.outdoor} °C, inside ${spec.indoor} °C). Heat from people, cooking and the sun isn't subtracted, so the result has a margin.", ky: 'Эң суук күнү үйгө керектүү жылуулук (сыртта ${spec.outdoor} °C, ичинде ${spec.indoor} °C). Адамдардан, тамак бышыруудан жана күндөн келген жылуулук кемитилбейт, ошондуктан жыйынтыкта запас бар.', uz: 'Eng sovuq kunda uyga kerakli issiqlik (tashqarida ${spec.outdoor} °C, ichkarida ${spec.indoor} °C). Odamlar, ovqat pishirish va quyoshdan keladigan issiqlik ayirilmaydi, shuning uchun natijada zaxira bor.'),
        children: [
          KvGrid([
            Kv(
                '${kw(loss.total)} kW',
                tr3('设计热负荷', 'Есептік жылу жүктемесі',
                    'Расчётная тепловая нагрузка',
                    'Design heat load', ky: 'Эсептик жылуулук жүгү', uz: 'Hisobiy issiqlik yuklamasi')),
            Kv('${loss.perArea.round()} W/$unitM2',
                tr3('每平方米', 'Әр шаршы метрге', 'На квадратный метр', 'Per square metre', ky: 'Бир чарчы метрге', uz: 'Bir kvadrat metrga')),
            Kv(
                '${loss.boilerKw} kW',
                tr3('建议锅炉功率 (留 15% 余量)', 'Ұсынылатын қазандық (15% қормен)',
                    'Рекомендуемый котёл (с запасом 15%)',
                    'Recommended boiler (15% margin)', ky: 'Сунушталган казан (15% запас)', uz: 'Tavsiya etilgan qozon (15% zaxira)')),
            Kv('${groupDigits(loss.seasonKwh)} ${tr3('度', 'кВт·сағ', 'кВт·ч', 'kWh', ky: 'кВт·с', uz: 'kVt·soat')}',
                tr3('一个采暖季用热', 'Бір жылыту маусымы', 'За отопительный сезон', 'Per heating season', ky: 'Жылытуу мезгилине', uz: 'Isitish mavsumiga')),
            Kv('${dec(loss.fuel.toStringAsFixed(spec.fuel == FuelKind.coal || spec.fuel == FuelKind.wood ? 1 : 0))} ${fuelUnit(spec.fuel)}',
                '${tr3('约需', 'Шамамен', 'Примерно', 'About', ky: 'Болжол менен', uz: 'Taxminan')} ${fuelName(spec.fuel)} · ${tr3('效率', 'ПӘК', 'КПД', 'Efficiency', ky: 'ПАК', uz: 'FIK')} ${spec.efficiency}%',
                onTap: () => editInt('efficiency',
                    tr3('锅炉/炉子效率', 'Қазандық ПӘК', 'КПД котла / печи', 'Boiler / stove efficiency', ky: 'Казандын / мештин ПАК', uz: 'Qozon / pechning FIK'),
                    suffix: '%')),
            Kv('${dec(loss.heatedArea.toStringAsFixed(1))} $unitM2',
                tr3('采暖面积', 'Жылытылатын аудан', 'Отапливаемая площадь', 'Heated area', ky: 'Жылытылган аянт', uz: 'Isitiladigan maydon')),
          ], minWidth: 160),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in FuelKind.values)
              PillToggle(
                  label: fuelName(f),
                  checkbox: false,
                  selected: spec.fuel == f,
                  onChanged: (_) => action('SetHeat', {'fuel': f})),
          ]),
        ]);
    final climate = InfoCard(
        title: tr3('气候与门窗', 'Климат және есік-терезе', 'Климат, окна и двери', 'Climate, windows and doors', ky: 'Климат, терезелер жана эшиктер', uz: 'Iqlim, derazalar va eshiklar'),
        trailing: IconButton(
            tooltip:
                tr3('恢复默认', 'Әдепкі мәндер', 'Вернуть значения по умолчанию', 'Restore the defaults', ky: 'Демейкини калыбына келтирүү', uz: 'Standartni tiklash'),
            visualDensity: VisualDensity.compact,
            onPressed: () => action('SetHeat', {'reset': true}),
            icon: const Icon(YIcons.refresh, size: 18)),
        children: [
          KvGrid([
            Kv(
                '${spec.outdoor} °C',
                tr3('采暖室外计算温度', 'Есептік сыртқы температура',
                    'Расчётная наружная температура',
                    'Design outdoor temperature', ky: 'Сырткы эсептик температура', uz: 'Tashqi hisobiy harorat'),
                onTap: () => editInt(
                    'outdoor',
                    tr3('采暖室外计算温度', 'Есептік сыртқы температура',
                        'Расчётная наружная температура',
                        'Design outdoor temperature', ky: 'Сырткы эсептик температура', uz: 'Tashqi hisobiy harorat'),
                    suffix: '°C')),
            Kv('${spec.indoor} °C',
                tr3('室内温度', 'Ішкі температура', 'Внутренняя температура', 'Indoor temperature', ky: 'Ички температура', uz: 'Ichki harorat'),
                onTap: () => editInt('indoor',
                    tr3('室内温度', 'Ішкі температура', 'Внутренняя температура', 'Indoor temperature', ky: 'Ички температура', uz: 'Ichki harorat'),
                    suffix: '°C')),
            Kv('${spec.degreeDays}',
                tr3('采暖度日数 K·d', 'Градус-тәулік, K·d', 'Градусо-сутки, °C·сут', 'Degree-days, °C·d', ky: 'Градус-күн, °C·к', uz: 'Gradus-kun, °C·k'),
                onTap: () => editInt(
                    'degreeDays',
                    tr3('采暖度日数', 'Жылыту градус-тәулігі',
                        'Градусо-сутки отопительного периода',
                        'Heating degree-days', ky: 'Жылытуу градус-күндөрү', uz: 'Isitish gradus-kunlari'))),
            Kv(
                dec((spec.airChange / 100).toStringAsFixed(2)),
                tr3('换气次数 /小时', 'Ауа алмасу, сағатына',
                    'Воздухообмен, раз в час',
                    'Air changes per hour', ky: 'Сааттагы аба алмашуу', uz: 'Soatiga havo almashinuvi'),
                onTap: () => editHundredths(
                    'airChange',
                    tr3('换气次数', 'Ауа алмасу жиілігі',
                        'Кратность воздухообмена',
                        'Air change rate', ky: 'Аба алмашуу ылдамдыгы', uz: 'Havo almashinuv darajasi'),
                    suffix: '1/h')),
            Kv(
                u(loss.windowU),
                tr3('窗 U 值 W/(m²·K)', 'Терезе U, Вт/(м²·К)',
                    'U окна, Вт/(м²·К)',
                    'Window U, W/(m²·K)', ky: 'Терезе U, Вт/(м²·К)', uz: 'Deraza U, Vt/(m²·K)'),
                onTap: () => editHundredths(
                    'windowU',
                    tr3('窗传热系数', 'Терезенің жылу өткізгіштігі',
                        'Коэффициент теплопередачи окна',
                        'Window heat transfer coefficient', ky: 'Терезенин жылуулук өткөрүү коэффициенти', uz: 'Derazaning issiqlik uzatish koeffitsienti'),
                    suffix: 'W/m²K')),
            Kv(
                u(loss.doorU),
                tr3('外门 U 值 W/(m²·K)', 'Сыртқы есік U, Вт/(м²·К)',
                    'U наружной двери, Вт/(м²·К)',
                    'Exterior door U, W/(m²·K)', ky: 'Сырткы эшик U, Вт/(м²·К)', uz: 'Tashqi eshik U, Vt/(m²·K)'),
                onTap: () => editHundredths(
                    'doorU',
                    tr3('外门传热系数', 'Есіктің жылу өткізгіштігі',
                        'Коэффициент теплопередачи двери',
                        'Door heat transfer coefficient', ky: 'Эшиктин жылуулук өткөрүү коэффициенти', uz: 'Eshikning issiqlik uzatish koeffitsienti'),
                    suffix: 'W/m²K')),
          ]),
          Note(tr3(
              '室外计算温度和度日数请查当地气象或节能规范。新疆北部和哈萨克斯坦北部一般在 -30 °C 以下，度日数 5500 以上；伊犁、阿拉木图一带较暖。',
              'Есептік температура мен градус-тәулікті жергілікті климат не энергия үнемдеу нормасынан алыңыз. Қазақстанның солтүстігі мен Шыңжаңның солтүстігінде әдетте -30 °C-тан төмен, 5500-ден жоғары; Іле, Алматы өңірі жылырақ.',
              'Расчётную температуру и градусо-сутки возьмите из местных климатических данных или норм по энергосбережению. На севере Казахстана и на севере Синьцзяна температура обычно ниже -30 °C, а градусо-сутки — больше 5500; в районе Или и Алматы теплее.',
              'Take the design temperature and degree-days from local climate data or energy-saving codes. In northern Kazakhstan and northern Xinjiang the temperature is usually below -30 °C and degree-days exceed 5500; the Ili and Almaty areas are warmer.', ky: 'Эсептик температура менен градус-күндөрдү жергиликтүү климат маалыматтарынан же энергия үнөмдөө ченемдеринен алыңыз. Түндүк Казакстанда жана Түндүк Шинжаңда температура адатта -30 °C төмөн, градус-күн 5500дөн ашат; Иле жана Алматы аймактары жылуураак.', uz: 'Hisobiy harorat va gradus-kunlarni mahalliy iqlim maʼlumotlari yoki energiya tejash meʼyorlaridan oling. Shimoliy Qozogʻiston va Shimoliy Shinjonda harorat odatda -30 °C dan past, gradus-kunlar 5500 dan oshadi; Ili va Olmaota hududlari issiqroq.')),
        ]);
    final parts = [
      (
        tr3('外墙', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi'),
        loss.wallU,
        loss.wallArea,
        loss.walls
      ),
      (tr3('窗', 'Терезе', 'Окно', 'Window', ky: 'Терезе', uz: 'Deraza'), loss.windowU, loss.windowArea, loss.windows),
      (
        tr3('外门', 'Сыртқы есік', 'Наружная дверь', 'Exterior door', ky: 'Сырткы эшик', uz: 'Tashqi eshik'),
        loss.doorU,
        loss.doorArea,
        loss.doors
      ),
      (tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'), loss.roofU, loss.roofArea, loss.roof),
      (
        tr3('首层地面', 'Бірінші қабат едені', 'Пол первого этажа', 'Ground floor build-up', ky: 'Биринчи кабаттын полунун катмарлары', uz: 'Birinchi qavat poli qatlamlari'),
        loss.floorU,
        loss.floorArea,
        loss.floor
      ),
      (tr3('通风换气', 'Желдету', 'Вентиляция', 'Ventilation', ky: 'Желдетүү', uz: 'Shamollatish'), null, loss.volume, loss.air),
    ];
    final envelope = InfoCard(
        title: tr3('热量从哪里散失', 'Жылу қайдан кетеді', 'Куда уходит тепло', 'Where the heat goes', ky: 'Жылуулук кайда кетет', uz: 'Issiqlik qayerga ketadi'),
        children: [
          ShareBars([
            for (final p in parts)
              if (p.$4 > 0)
                (
                  p.$1,
                  p.$4,
                  '${w0(p.$4)} W · ${(p.$4 / math.max(1, loss.total) * 100).round()}%'
                )
          ]),
          PlainTable(header: [
            tr3('部位', 'Бөлік', 'Элемент', 'Element', ky: 'Элемент', uz: 'Element'),
            'U W/(m²·K)',
            tr3('面积/体积', 'Аудан/көлем', 'Площадь/объём', 'Area/volume', ky: 'Аянт/көлөм', uz: 'Maydon/hajm'),
            tr3('失热 W', 'Шығын, Вт', 'Потери, Вт', 'Loss, W', ky: 'Жоготуу, Вт', uz: 'Yoʻqotish, Vt'),
          ], rows: [
            for (final p in parts)
              [
                TableCellData(p.$1),
                TableCellData(p.$2 == null ? '—' : u(p.$2!),
                    numeric: true,
                    color: p.$2 != null &&
                            ((p.$1 == parts[0].$1 && p.$2! > 0.40) ||
                                (p.$1 == parts[3].$1 && p.$2! > 0.30))
                        ? t.crit
                        : null),
                TableCellData(
                    '${dec(p.$3.toStringAsFixed(1))} ${p.$2 == null ? unitM3 : unitM2}',
                    numeric: true),
                TableCellData(w0(p.$4), numeric: true),
              ]
          ]),
          Note(tr3(
              '外墙、屋顶、地面的 U 值由“构造细节”里的构造层算出；可在下表修改每种材料的导热系数。',
              'Қабырға, шатыр және еден U мәні «Құрылым бөлшектері» қабаттарынан есептеледі; төмендегі кестеде әр материалдың жылу өткізгіштігін өзгертуге болады.',
              'Значение U стен, крыши и пола рассчитывается по слоям из раздела «Детали конструкции»; в таблице ниже можно изменить теплопроводность каждого материала.',
              "U-values of walls, roof and floor are calculated from the layers in “Construction details”; you can change each material's conductivity in the table below.", ky: 'Дубалдардын, чатырдын жана полдун U маанилери «Конструкция деталдары» бөлүмүндөгү катмарлардан эсептелет; ар бир материалдын жылуулук өткөрүмдүүлүгүн төмөнкү таблицада өзгөртсөңүз болот.', uz: 'Devorlar, tom va polning U qiymatlari “Konstruksiya tafsilotlari” boʻlimidagi qatlamlardan hisoblanadi; har bir materialning issiqlik oʻtkazuvchanligini quyidagi jadvalda oʻzgartirishingiz mumkin.')),
        ]);
    Widget layers(String title, String group, List<Layer> list) {
      Future<void> editLambda(int i) async {
        final l = list[i];
        final v = await askNumber(
            '${tr(l.name, l.nameKk)} · λ', l.conductivity / 1000,
            suffix: 'W/(m·K)');
        if (v == null || v <= 0) return;
        final value = (v * 1000).round();
        final next = [...list];
        next[i] = Layer(l.name, l.nameKk, l.thickness, l.material,
            lambda: value == materialLambda[l.material] ? null : value);
        action('SetLayers', {'group': group, 'layers': next});
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
        PlainTable(header: [
          tr3('构造层', 'Қабат', 'Слой', 'Layer', ky: 'Катмар', uz: 'Qatlam'),
          unitMm,
          'λ W/(m·K)',
          'R m²K/W',
        ], rows: [
          for (var i = 0; i < list.length; i++)
            [
              TableCellData(tr(list[i].name, list[i].nameKk)),
              TableCellData('${list[i].thickness}', numeric: true),
              TableCellData(
                  dec((list[i].conductivity / 1000).toStringAsFixed(3)),
                  numeric: true,
                  highlight: list[i].lambda != null,
                  onTap: () => editLambda(i)),
              TableCellData(
                  list[i].material == LayerMaterial.earth ||
                          list[i].thickness == 0
                      ? '—'
                      : dec((list[i].thickness / list[i].conductivity)
                          .toStringAsFixed(2)),
                  numeric: true),
            ]
        ]),
      ]);
    }

    final x = doc.extras;
    final materials = InfoCard(
        title: tr3('材料导热系数', 'Материалдың жылу өткізгіштігі',
            'Теплопроводность материалов',
            'Material conductivity', ky: 'Материалдын жылуулук өткөрүмдүүлүгү', uz: 'Material issiqlik oʻtkazuvchanligi'),
        subtitle: tr3(
            '点 λ 修改；高亮的是你改过的值。保温材料看产品说明：岩棉约 0.040，XPS 约 0.032，加气块 D500 约 0.14。',
            'λ мәнін басып өзгертіңіз; ерекшеленгені — сіз өзгерткендер. Жылытқыш өнімінің құжатын қараңыз: минералды мақта ≈0,040, XPS ≈0,032, газоблок D500 ≈0,14.',
            'Нажмите на λ, чтобы изменить; выделены значения, которые вы изменили. Для утеплителя смотрите документацию изделия: минеральная вата ≈0,040, XPS ≈0,032, газоблок D500 ≈0,14.',
            'Tap λ to change it; values you changed are highlighted. For insulation see the product data: mineral wool ≈0.040, XPS ≈0.032, aerated block D500 ≈0.14.', ky: 'Өзгөртүү үчүн λ басыңыз; сиз өзгөрткөн маанилер белгиленет. Жылуулоочу үчүн буюмдун маалыматын караңыз: минерал пахта ≈0,040, XPS ≈0,032, газоблок D500 ≈0,14.', uz: 'Oʻzgartirish uchun λ ga bosing; siz oʻzgartirgan qiymatlar ajratib koʻrsatiladi. Izolyatsiya uchun mahsulot maʼlumotlariga qarang: mineral paxta ≈0,040, XPS ≈0,032, gazoblok D500 ≈0,14.'),
        children: [
          layers(
              '${tr3('外墙', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi')} · U ${u(loss.wallU)}',
              'wall',
              x.wallLayers),
          layers('${tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom')} · U ${u(loss.roofU)}', 'roof',
              x.roofLayers),
          layers('${tr3('地面', 'Еден', 'Пол', 'Floor', ky: 'Пол', uz: 'Pol')} · U ${u(loss.floorU)}', 'floor',
              x.floorLayers),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: Btn(
                  label: tr3('编辑构造层', 'Қабаттарды өзгерту', 'Изменить слои', 'Edit layers', ky: 'Катмарларды түзөтүү', uz: 'Qatlamlarni tahrirlash'),
                  icon: YIcons.layers,
                  onPressed: () => showTab('det'))),
        ]);
    final rows = <List<TableCellData>>[];
    final multi = doc.floors.length > 1;
    for (final s in loss.spaces) {
      final room =
          doc.floors[s.floorIndex].rooms.where((r) => r.id == s.id).firstOrNull;
      if (room == null || s.total <= 0) continue;
      rows.add([
        TableCellData(displayRoomName(room)),
        if (multi)
          TableCellData(displayFloorName(doc.floors[s.floorIndex].name),
              muted: true),
        TableCellData(dec(s.area.toStringAsFixed(1)), numeric: true),
        TableCellData(w0(s.total), numeric: true),
        TableCellData('${s.area <= 0 ? '—' : (s.total / s.area).round()}',
            numeric: true),
        TableCellData('${s.sections}', numeric: true),
      ]);
    }
    final perRoom = InfoCard(
        title: tr3('各房间热负荷与暖气片', 'Бөлмелердің жылу жүктемесі мен радиаторы',
            'Тепловая нагрузка и радиаторы по комнатам',
            'Heat load and radiators by room', ky: 'Бөлмөлөр боюнча жылуулук жүгү жана радиаторлор', uz: 'Xonalar boʻyicha issiqlik yuklamasi va radiatorlar'),
        subtitle: tr3(
            '暖气片按每片约 150 W (铝制、供水 70 °C 左右) 估算，最终以产品样本为准。',
            'Радиатор секциясы шамамен 150 Вт (алюминий, су ≈70 °C) деп алынды; нақтысын өнім құжатынан қараңыз.',
            'Секция радиатора принята примерно за 150 Вт (алюминий, вода ≈70 °C); точные данные смотрите в документации изделия.',
            'A radiator section is taken as about 150 W (aluminium, water ≈70 °C); see the product data for exact figures.', ky: 'Радиатордун бир секциясы болжол менен 150 Вт деп алынат (алюминий, суу ≈70 °C); так сандар үчүн буюмдун маалыматын караңыз.', uz: 'Radiatorning bir seksiyasi taxminan 150 Vt deb olinadi (alyuminiy, suv ≈70 °C); aniq raqamlar uchun mahsulot maʼlumotlariga qarang.'),
        children: [
          const SizedBox(height: 6),
          PlainTable(header: [
            tr3('房间', 'Бөлме', 'Комната', 'Room', ky: 'Бөлмө', uz: 'Xona'),
            if (multi) tr3('楼层', 'Қабат', 'Этаж', 'Floor', ky: 'Кабат', uz: 'Qavat'),
            unitM2,
            'W',
            'W/$unitM2',
            tr3('暖气片 片', 'Секция', 'Секций', 'Sections', ky: 'Кесилиштер', uz: 'Kesimlar'),
          ], rows: rows),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: Btn(
                  label: tr3('在平面上布置暖气片', 'Жоспарға радиатор қою',
                      'Разместить радиаторы на плане',
                      'Place radiators on the plan', ky: 'Радиаторлорду планга коюу', uz: 'Radiatorlarni rejaga joylash'),
                  icon: YIcons.radiator,
                  onPressed: () {
                    showTab('plan');
                    update(() => showUtilities = true);
                    chooseUtility();
                  })),
        ]);
    return page([
      summary,
      grid2([envelope, climate, perRoom, materials]),
      Note(tr3(
          '稳态估算，按 EN ISO 13370 简化方法计算地面失热，用于比较方案和选锅炉。正式设计请由暖通工程师按当地规范复核。',
          'Тұрақты күйдегі бағалау, еден EN ISO 13370 жеңілдетілген әдісімен. Нұсқаларды салыстыру мен қазандық таңдауға арналған; нақты жобаны жылу инженері жергілікті норма бойынша тексерсін.',
          'Оценка для стационарного режима, теплопотери пола — по упрощённому методу EN ISO 13370. Предназначена для сравнения вариантов и выбора котла; рабочий проект должен проверить инженер по отоплению по местным нормам.',
          'Steady-state estimate; floor heat loss uses the simplified EN ISO 13370 method. Meant for comparing options and choosing a boiler; a heating engineer must check the working design against local codes.', ky: 'Туруктуу абалдагы баа; полдун жылуулук жоготуусу EN ISO 13370 жөнөкөйлөтүлгөн ыкмасы менен эсептелет. Варианттарды салыштыруу жана казан тандоо үчүн; иштөөчү долбоорду жылытуу инженери жергиликтүү ченемдер боюнча текшериши керек.', uz: 'Barqaror holat boʻyicha baho; pol issiqlik yoʻqotishi EN ISO 13370 soddalashtirilgan usuli bilan hisoblanadi. Variantlarni solishtirish va qozon tanlash uchun; ishchi loyihani isitish muhandisi mahalliy meʼyorlar boʻyicha tekshirishi kerak.')),
    ]);
  }
}
