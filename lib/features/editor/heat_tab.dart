part of '../house_editor.dart';

/// Insulation and heating: the heat the house loses on the coldest day,
/// where it goes, how big a boiler it needs and the fuel for a winter.
/// Climate, U-values of windows and doors and every layer's conductivity
/// can be edited here.
extension _HeatTab on _HouseEditorState {
  Widget heatTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final loss = heatLoss(doc, derived), spec = doc.extras.heat;
    String kw(double w) => dec((w / 1000).toStringAsFixed(1));
    String w0(double w) => money(w);
    String u(double v) => dec(v.toStringAsFixed(2));
    Future<void> editInt(String field, String title, {String? suffix}) async {
      final v = await askNumber(title, spec.ints[field]!, suffix: suffix);
      if (v != null) action('SetHeat', {'field': field, 'value': v.round()});
    }

    Future<void> editHundredths(String field, String title,
        {String? suffix}) async {
      final v = await askNumber(title, spec.ints[field]! / 100, suffix: suffix);
      if (v != null)
        action('SetHeat', {'field': field, 'value': (v * 100).round()});
    }

    final summary = InfoCard(
        title: '${tr('保温与采暖', 'Жылу оқшаулау және жылыту')} · ${kw(loss.total)} kW',
        subtitle: tr('最冷天 (室外 ${spec.outdoor} °C、室内 ${spec.indoor} °C) 全屋需要补的热量。未扣除人体、做饭和日照得热，结果偏保守。',
            'Ең суық күні (сыртта ${spec.outdoor} °C, ішінде ${spec.indoor} °C) үйге керек жылу. Адам, ас пісіру және күн жылуы шегерілмеген, сондықтан нәтиже қорлы.'),
        children: [
          KvGrid([
            Kv('${kw(loss.total)} kW', tr('设计热负荷', 'Есептік жылу жүктемесі')),
            Kv('${loss.perArea.round()} W/$unitM2', tr('每平方米', 'Әр шаршы метрге')),
            Kv('${loss.boilerKw} kW', tr('建议锅炉功率 (留 15% 余量)', 'Ұсынылатын қазандық (15% қормен)')),
            Kv('${money(loss.seasonKwh)} ${tr('度', 'кВт·сағ')}', tr('一个采暖季用热', 'Бір жылыту маусымы')),
            Kv('${dec(loss.fuel.toStringAsFixed(spec.fuel == FuelKind.coal || spec.fuel == FuelKind.wood ? 1 : 0))} ${fuelUnit(spec.fuel)}',
                '${tr('约需', 'Шамамен')} ${fuelName(spec.fuel)} · ${tr('效率', 'ПӘК')} ${spec.efficiency}%',
                onTap: () => editInt('efficiency', tr('锅炉/炉子效率', 'Қазандық ПӘК'), suffix: '%')),
            Kv('${dec(loss.heatedArea.toStringAsFixed(1))} $unitM2', tr('采暖面积', 'Жылытылатын аудан')),
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
        title: tr('气候与门窗', 'Климат және есік-терезе'),
        trailing: IconButton(
            tooltip: tr('恢复默认', 'Әдепкі мәндер'),
            visualDensity: VisualDensity.compact,
            onPressed: () => action('SetHeat', {'reset': true}),
            icon: const Icon(Icons.restart_alt, size: 18)),
        children: [
          KvGrid([
            Kv('${spec.outdoor} °C', tr('采暖室外计算温度', 'Есептік сыртқы температура'),
                onTap: () => editInt('outdoor', tr('采暖室外计算温度', 'Есептік сыртқы температура'), suffix: '°C')),
            Kv('${spec.indoor} °C', tr('室内温度', 'Ішкі температура'),
                onTap: () => editInt('indoor', tr('室内温度', 'Ішкі температура'), suffix: '°C')),
            Kv('${spec.degreeDays}', tr('采暖度日数 K·d', 'Градус-тәулік, K·d'),
                onTap: () => editInt('degreeDays', tr('采暖度日数', 'Жылыту градус-тәулігі'))),
            Kv(dec((spec.airChange / 100).toStringAsFixed(2)), tr('换气次数 /小时', 'Ауа алмасу, сағатына'),
                onTap: () => editHundredths('airChange', tr('换气次数', 'Ауа алмасу жиілігі'), suffix: '1/h')),
            Kv(u(loss.windowU), tr('窗 U 值 W/(m²·K)', 'Терезе U, Вт/(м²·К)'),
                onTap: () => editHundredths('windowU', tr('窗传热系数', 'Терезенің жылу өткізгіштігі'), suffix: 'W/m²K')),
            Kv(u(loss.doorU), tr('外门 U 值 W/(m²·K)', 'Сыртқы есік U, Вт/(м²·К)'),
                onTap: () => editHundredths('doorU', tr('外门传热系数', 'Есіктің жылу өткізгіштігі'), suffix: 'W/m²K')),
          ]),
          Note(tr('室外计算温度和度日数请查当地气象或节能规范。新疆北部和哈萨克斯坦北部一般在 -30 °C 以下，度日数 5500 以上；伊犁、阿拉木图一带较暖。',
              'Есептік температура мен градус-тәулікті жергілікті климат не энергия үнемдеу нормасынан алыңыз. Қазақстанның солтүстігі мен Шыңжаңның солтүстігінде әдетте -30 °C-тан төмен, 5500-ден жоғары; Іле, Алматы өңірі жылырақ.')),
        ]);
    final parts = [
      (tr('外墙', 'Сыртқы қабырға'), loss.wallU, loss.wallArea, loss.walls),
      (tr('窗', 'Терезе'), loss.windowU, loss.windowArea, loss.windows),
      (tr('外门', 'Сыртқы есік'), loss.doorU, loss.doorArea, loss.doors),
      (tr('屋顶', 'Шатыр'), loss.roofU, loss.roofArea, loss.roof),
      (tr('首层地面', 'Бірінші қабат едені'), loss.floorU, loss.floorArea, loss.floor),
      (tr('通风换气', 'Желдету'), null, loss.volume, loss.air),
    ];
    final envelope = InfoCard(
        title: tr('热量从哪里散失', 'Жылу қайдан кетеді'),
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
            tr('部位', 'Бөлік'),
            'U W/(m²·K)',
            tr('面积/体积', 'Аудан/көлем'),
            tr('失热 W', 'Шығын, Вт'),
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
          Note(tr('外墙、屋顶、地面的 U 值由“构造细节”里的构造层算出；可在下表修改每种材料的导热系数。',
              'Қабырға, шатыр және еден U мәні «Құрылым бөлшектері» қабаттарынан есептеледі; төмендегі кестеде әр материалдың жылу өткізгіштігін өзгертуге болады.')),
        ]);
    Widget layers(String title, String group, List<Layer> list) {
      Future<void> editLambda(int i) async {
        final l = list[i];
        final v = await askNumber(
            '${isKk ? l.nameKk : l.name} · λ', l.conductivity / 1000,
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
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        PlainTable(header: [
          tr('构造层', 'Қабат'),
          unitMm,
          'λ W/(m·K)',
          'R m²K/W',
        ], rows: [
          for (var i = 0; i < list.length; i++)
            [
              TableCellData(isKk ? list[i].nameKk : list[i].name),
              TableCellData('${list[i].thickness}', numeric: true),
              TableCellData(dec((list[i].conductivity / 1000).toStringAsFixed(3)),
                  numeric: true,
                  highlight: list[i].lambda != null,
                  onTap: () => editLambda(i)),
              TableCellData(
                  list[i].material == LayerMaterial.earth || list[i].thickness == 0
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
        title: tr('材料导热系数', 'Материалдың жылу өткізгіштігі'),
        subtitle: tr('点 λ 修改；高亮的是你改过的值。保温材料看产品说明：岩棉约 0.040，XPS 约 0.032，加气块 D500 约 0.14。',
            'λ мәнін басып өзгертіңіз; ерекшеленгені — сіз өзгерткендер. Жылытқыш өнімінің құжатын қараңыз: минералды мақта ≈0,040, XPS ≈0,032, газоблок D500 ≈0,14.'),
        children: [
          layers('${tr('外墙', 'Сыртқы қабырға')} · U ${u(loss.wallU)}', 'wall', x.wallLayers),
          layers('${tr('屋顶', 'Шатыр')} · U ${u(loss.roofU)}', 'roof', x.roofLayers),
          layers('${tr('地面', 'Еден')} · U ${u(loss.floorU)}', 'floor', x.floorLayers),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: Btn(
                  label: tr('编辑构造层', 'Қабаттарды өзгерту'),
                  icon: Icons.layers_outlined,
                  onPressed: () => showTab('det'))),
        ]);
    final rows = <List<TableCellData>>[];
    final multi = doc.floors.length > 1;
    for (final s in loss.spaces) {
      final room = doc.floors[s.floorIndex].rooms
          .where((r) => r.id == s.id)
          .firstOrNull;
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
        title: tr('各房间热负荷与暖气片', 'Бөлмелердің жылу жүктемесі мен радиаторы'),
        subtitle: tr('暖气片按每片约 150 W (铝制、供水 70 °C 左右) 估算，最终以产品样本为准。',
            'Радиатор секциясы шамамен 150 Вт (алюминий, су ≈70 °C) деп алынды; нақтысын өнім құжатынан қараңыз.'),
        children: [
          const SizedBox(height: 6),
          PlainTable(header: [
            tr('房间', 'Бөлме'),
            if (multi) tr('楼层', 'Қабат'),
            unitM2,
            'W',
            'W/$unitM2',
            tr('暖气片 片', 'Секция'),
          ], rows: rows),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: Btn(
                  label: tr('在平面上布置暖气片', 'Жоспарға радиатор қою'),
                  icon: Icons.heat_pump_outlined,
                  onPressed: () {
                    showTab('plan');
                    update(() => showUtilities = true);
                    chooseUtility();
                  })),
        ]);
    return page([
      summary,
      grid2([envelope, climate, perRoom, materials]),
      Note(tr('稳态估算，按 EN ISO 13370 简化方法计算地面失热，用于比较方案和选锅炉。正式设计请由暖通工程师按当地规范复核。',
          'Тұрақты күйдегі бағалау, еден EN ISO 13370 жеңілдетілген әдісімен. Нұсқаларды салыстыру мен қазандық таңдауға арналған; нақты жобаны жылу инженері жергілікті норма бойынша тексерсін.')),
    ]);
  }
}
