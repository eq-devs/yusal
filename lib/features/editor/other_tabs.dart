part of '../house_editor.dart';

/// Construction details, schedules and the issue list: pages computed from
/// the model where every parameter, label and note can be edited.
extension _OtherTabs on _HouseEditorState {
  Widget page(List<Widget> children) => ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 40),
      children: [
        for (final c in children) ...[c, const SizedBox(height: 12)]
      ]);

  /// Two columns on wide screens, one on phones.
  Widget grid2(List<Widget> cards) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 860 ? 2 : 1;
        if (columns == 1)
          return Column(children: [
            for (final card in cards) ...[card, const SizedBox(height: 12)]
          ]);
        final left = <Widget>[], right = <Widget>[];
        for (var i = 0; i < cards.length; i++)
          (i.isEven ? left : right)
              .addAll([cards[i], const SizedBox(height: 12)]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 12),
          Expanded(child: Column(children: right)),
        ]);
      });

  // ---------------------------------------------------------------- notes

  /// Default advice per section; the user's own text replaces it.
  String defaultNote(String key) {
    final f = history.present.extras.foundation;
    final buried = f.height - f.plinth;
    return switch (key) {
      'foundation' => tr(
          '外墙和承重墙下按 ${f.width}×${f.height} 做条形基础；隔墙基础${f.partitions ? '已按 ${f.partitionWidth}×${f.partitionHeight} 计入' : '未计入，可在上面打开'}。高 ${f.height} mm、埋深 $buried mm 属于浅埋基础，只适合冻深较浅、土质为砂或砂砾的地区，而且必须做砂砾石垫层、外侧 XPS 和保温散水。黏土地基或冻深 1.5–2 m 的地区，要么把基础加深到冻深以下，要么请结构师按浅埋保温基础计算。动工前先挖一个 1.5 m 的探坑看土层和地下水。',
          'Сыртқы және көтергіш қабырғалардың астында ${f.width}×${f.height} таспалы іргетас; қалқа іргетасы ${f.partitions ? '${f.partitionWidth}×${f.partitionHeight} етіп есептелді' : 'есепке кірмеген, жоғарыда қосуға болады'}. Биіктігі ${f.height} мм, тереңдігі $buried мм — таяз іргетас, тек қату таяз, құм не құм-қиыршық топырақты аймаққа жарайды; құм-қиыршық төсеме, сыртқы XPS пен жылы отмостка міндетті. Саз топырақта не қату 1,5–2 м жерде іргетасты қату тереңдігінен төмен түсіріңіз не конструктор есептесін. Бастамас бұрын 1,5 м шұңқыр қазып, топырақ пен жер асты суын қараңыз.'),
      'wall' => tr(
          '寒冷地区不建议纯砖墙不加保温，热工达不到。加气块加外保温是性价比高的做法，也可换成 380 砖 + 100 保温。',
          'Суық климатта жылытқышсыз кірпіш қабырға жылу талабына жетпейді. Газоблок пен сыртқы жылытқыш — тиімді шешім. Баламасы: 380 мм кірпіш + 100 мм жылытқыш.'),
      'roof' => history.present.roof.type == RoofType.flat
          ? tr(
              '寒冷地区平屋顶要注意三点：排水口和落水管容易冻堵，建议加电伴热；积雪荷载按当地规范计算；女儿墙内侧防水上翻不少于 300 mm，并留一个检修上人孔。',
              'Суық аймақта тегіс шатырдың үш маңызды жері бар: су қабылдағыш пен құбыр қатуы мүмкін — электр жылытқыш қойыңыз; қар жүктемесін жергілікті норма бойынша есептеңіз; парапет ішіне гидрооқшауды кемінде 300 мм көтеріп, шатырға шығатын люк қалдырыңыз.')
          : tr(
              '坡屋顶注意檐口保温连续、屋脊通风和雪挡。坡度越大积雪越少，但屋面面积和造价随之增加。',
              'Қос беткейлі шатырда карниз жылытқышы үзіліссіз, жотада желдету және қар ұстағыш болсын. Еңіс үлкен болса қар аз жиналады, бірақ шатыр ауданы мен құны артады.'),
      'floor' => tr(
          '如果考虑地暖，找平层里埋管，XPS 必须连续不断。卫生间和厨房在找平层上面再加一道防水，墙根上翻 200–300 mm。',
          'Жылы еден жасасаңыз, құбыр тегістеу қабатына салынады, XPS үзіліссіз болуы керек. Жуыну бөлмесі мен ас үйде тағы бір гидрооқшау салып, қабырғаға 200–300 мм көтеріңіз.'),
      'style' => tr(
          '全家席地而坐吃饭、喝茶，所以地面温度最重要。客厅和卧室建议做地暖；挂毯挂在外墙或卧室墙上，同时起到保温和隔音作用，墙上提前预埋挂杆或木条。门厅设换鞋区，地毯就能保持干净。',
          'Отбасы еденде отырып тамақ ішеді, сондықтан еденнің жылы болуы ең маңызды. Қонақ бөлме мен жатын бөлмелерге жылы еден жасаған дұрыс; тұскиіз жылу мен дыбыс оқшаулауға көмектеседі — қабырғаға ілгіш ағаш алдын ала бекітіңіз. Кіреберісте аяқ киім ауыстыратын орын болса, кілем таза тұрады.'),
      'windows' => tr(
          '建议 PVC 多腔型材配双中空 (三玻) 玻璃。窗装在保温层附近而不是墙的正中，用预压膨胀密封带封缝，可避免窗边结露发霉。北面大窗冬季失热最多。',
          'Көпкамералы ПВХ профиль мен екі камералы (үш әйнекті) шыны пакет ұсынылады. Терезені қабырға ортасына емес, жылытқышқа жақын орнатып, саңылауын кеңейетін лентамен бітеңіз — конденсат пен көгеру болмайды. Солтүстіктегі үлкен терезе қыста ең көп жылу жоғалтады.'),
      'doors' => tr(
          '入户门选带保温层和双道密封的钢门。卫生间门底留 20 mm 缝或装百叶，方便排气扇进风。锅炉房门的耐火等级和开启方向请按燃气验收要求确认。',
          'Кіреберіске жылытқышы және екі қабат тығыздағышы бар болат есік таңдаңыз. Жуыну бөлмесі есігінің астынан 20 мм саңылау қалдырыңыз. Қазандық есігінің отқа төзімділігін газ қабылдау талабына сай нақтылаңыз.'),
      'areas' => tr('实算按墙体内边净尺寸计算。图纸标注面积可在表中填写，差值大于 2 m² 标红。',
          'Есеп қабырғаның ішкі таза өлшемі бойынша. Сызбадағы ауданды кестеге жазуға болады; айырмасы 2 м²-ден асса қызыл.'),
      'qty' => tr('按模型尺寸自动计算，未计损耗、钢筋搭接以外的附加和抹灰。修改墙体、门窗或基础参数会同步更新。',
          'Модель өлшемдері бойынша автоматты есептелген; шығын мен сылақ кірмейді. Қабырға, есік-терезе не іргетас өзгерсе, бірге жаңарады.'),
      _ => '',
    };
  }

  Widget editableNote(String key, {Color? color}) {
    final t = Tokens.of(context);
    final own = history.present.extras.notes[key];
    return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          final value = await askText(tr('编辑说明', 'Жазбаны өзгерту'),
              own ?? defaultNote(key),
              multiline: true);
          if (value == null) return;
          action('SetNote', {
            'key': key,
            'value': value.trim() == defaultNote(key) ? '' : value
          });
        },
        child: Stack(children: [
          Note(own ?? defaultNote(key), color: color),
          Positioned(
              right: 0,
              top: 12,
              child: Icon(Icons.edit_outlined, size: 13, color: t.muted)),
        ]));
  }

  // ---------------------------------------------------------- details tab

  Widget detailsTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final x = doc.extras;
    return page([
      foundationCard(),
      grid2([
        layerCard(
            title: tr('外墙', 'Сыртқы қабырға'),
            group: 'wall',
            layers: x.wallLayers,
            note: 'wall',
            horizontal: true),
        layerCard(
            title: doc.roof.type == RoofType.flat
                ? tr('平屋顶 · 坡度 2%', 'Тегіс шатыр · еңісі 2%')
                : tr('双坡屋顶', 'Қос беткейлі шатыр'),
            group: 'roof',
            layers: x.roofLayers,
            note: 'roof',
            extra: roofFigures()),
        layerCard(
            title: tr('地坪 (首层地面)', 'Еден (бірінші қабат)'),
            group: 'floor',
            layers: x.floorLayers,
            note: 'floor'),
        InfoCard(title: tr('室内风格 · 哈萨克乡村', 'Интерьер · қазақ ауылы стилі'), children: [
          KvGrid([
            for (final k in [
              FurnitureKind.rug,
              FurnitureKind.wallRug,
              FurnitureKind.sandyq,
              FurnitureKind.korpe,
            ])
              Kv('${x.furniture.where((f) => f.kind == k).length}',
                  furnitureName(k)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('布置家具', 'Жиһаз қою'),
                icon: Icons.chair_outlined,
                onPressed: () {
                  showTab('plan');
                  chooseFurniture();
                })
          ]),
          editableNote('style'),
        ]),
        windowsCard(),
        doorsCard(),
      ]),
      Text(
          tr('构造做法是按寒冷气候给出的参考组合，用于和施工方、结构师沟通。最终厚度、配筋和冻深以当地规范和计算为准。',
              'Құрылым шешімдері суық климатқа арналған ұсыныс, құрылысшы және конструктормен сөйлесуге арналған. Нақты қалыңдық, арматура және қату тереңдігі жергілікті нормалар мен есеп бойынша анықталады.'),
          style: TextStyle(fontSize: 12, color: t.muted)),
    ]);
  }

  List<Widget> roofFigures() {
    final roof = history.present.roof;
    if (roof.type == RoofType.flat)
      return [
        KvGrid([
          Kv('${roof.parapetHeight}', tr('女儿墙高出墙顶 mm', 'Парапет биіктігі, мм'),
              onTap: () async {
            final v = await askMm(tr('女儿墙高度', 'Парапет биіктігі'),
                roof.parapetHeight ?? 900);
            if (v != null)
              action('SetRoof', {
                'roof': {'type': 'flat', 'parapetHeight': v}
              });
          }),
          Kv('2%', tr('排水坡度', 'Су ағатын еңіс')),
          Kv('${history.present.defaults.slabThickness}',
              tr('屋面板 mm', 'Жабын плитасы, мм'), onTap: () async {
            final v = await askMm(tr('楼板厚度', 'Плита қалыңдығы'),
                history.present.defaults.slabThickness);
            if (v != null)
              action('SetDefault', {'field': 'slabThickness', 'value': v});
          }),
        ]),
        Wrap(spacing: 8, children: [
          Btn(
              label: tr('改为双坡屋顶', 'Қос беткейлі ету'),
              icon: Icons.roofing,
              onPressed: () => action('SetRoof', {
                    'roof': {
                      'type': 'gable',
                      'ridgeDir': history.present.footprint.width >=
                              history.present.footprint.depth
                          ? 'H'
                          : 'V',
                      'pitchDeg': 30,
                      'overhang': 500
                    }
                  }))
        ]),
      ];
    Future<void> gable(String field, String title, int value) async {
      final v = await askMm(title, value);
      if (v == null) return;
      action('SetRoof', {
        'roof': {
          'type': 'gable',
          'ridgeDir': roof.ridgeDir!.name,
          'pitchDeg': field == 'pitch' ? v : roof.pitchDeg,
          'overhang': field == 'overhang' ? v : roof.overhang,
        }
      });
    }

    return [
      KvGrid([
        Kv('${roof.pitchDeg}°', tr('坡度', 'Еңісі'),
            onTap: () => gable('pitch', tr('坡度 (度)', 'Еңісі (градус)'),
                roof.pitchDeg!)),
        Kv('${roof.overhang}', tr('挑檐 mm', 'Карниз, мм'),
            onTap: () =>
                gable('overhang', tr('挑檐', 'Карниз'), roof.overhang!)),
        Kv(roof.ridgeDir == AxisDir.H ? tr('左右', 'көлденең') : tr('上下', 'тік'),
            tr('屋脊方向', 'Жота бағыты'),
            onTap: () => action('SetRoof', {
                  'roof': {
                    'type': 'gable',
                    'ridgeDir': roof.ridgeDir == AxisDir.H ? 'V' : 'H',
                    'pitchDeg': roof.pitchDeg,
                    'overhang': roof.overhang,
                  }
                })),
      ]),
      Wrap(spacing: 8, children: [
        Btn(
            label: tr('改为平屋顶', 'Тегіс ету'),
            icon: Icons.crop_landscape,
            onPressed: () => action('SetRoof', {
                  'roof': {'type': 'flat', 'parapetHeight': 1000}
                }))
      ]),
    ];
  }

  Widget layerCard(
      {required String title,
      required String group,
      required List<Layer> layers,
      required String note,
      bool horizontal = false,
      List<Widget> extra = const []}) {
    final t = Tokens.of(context);
    final names = [for (final l in layers) isKk ? l.nameKk : l.name];
    final total = layers.fold(0, (s, l) => s + l.thickness);
    void save(List<Layer> next) =>
        action('SetLayers', {'group': group, 'layers': next});
    Future<void> editLayer(int i) async {
      final l = layers[i];
      final name = await askText(tr('名称', 'Атауы'), names[i]);
      if (name == null || !mounted) return;
      final thickness = await askMm(tr('厚度', 'Қалыңдығы'), l.thickness);
      if (thickness == null || !mounted) return;
      final material = await showModalBottomSheet<LayerMaterial>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final m in LayerMaterial.values)
                  ListTile(
                      leading: SizedBox(
                          width: 28,
                          height: 18,
                          child: CustomPaint(painter: _MaterialSwatch(m, t))),
                      title: Text(materialName(m)),
                      selected: m == l.material,
                      onTap: () => Navigator.pop(context, m))
              ])));
      final next = [...layers];
      next[i] = Layer(isKk ? l.name : name.trim(), isKk ? name.trim() : l.nameKk,
          thickness, material ?? l.material);
      save(next);
    }

    return InfoCard(
        title: '$title · $total $unitMm',
        trailing: IconButton(
            tooltip: tr('恢复默认构造', 'Әдепкі құрылым'),
            visualDensity: VisualDensity.compact,
            onPressed: () => save(switch (group) {
                  'wall' => defaultWallLayers,
                  'roof' => defaultRoofLayers,
                  _ => defaultFloorLayers
                }),
            icon: const Icon(Icons.restart_alt, size: 18)),
        children: [
          const SizedBox(height: 6),
          SectionView(
              painter: horizontal
                  ? WallSectionPainter(t, layers, names,
                      outside: tr('室外', 'Сырты'), inside: tr('室内', 'Іші'))
                  : LayerStackPainter(t, layers, names,
                      scale: group == 'roof' ? 0.22 : 0.2)),
          const SizedBox(height: 6),
          for (var i = 0; i < layers.length; i++)
            InkWell(
                onTap: () => editLayer(i),
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                          width: 22,
                          height: 14,
                          child: CustomPaint(
                              painter: _MaterialSwatch(layers[i].material, t))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(names[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13))),
                      Text('${layers[i].thickness}',
                          style: mono(size: 13, color: t.muted)),
                      IconButton(
                          tooltip: tr('上移', 'Жоғары'),
                          visualDensity: VisualDensity.compact,
                          onPressed: i == 0
                              ? null
                              : () {
                                  final next = [...layers];
                                  next.insert(i - 1, next.removeAt(i));
                                  save(next);
                                },
                          icon: const Icon(Icons.arrow_upward, size: 16)),
                      IconButton(
                          tooltip: tr('删除这一层', 'Қабатты жою'),
                          visualDensity: VisualDensity.compact,
                          onPressed: layers.length <= 1
                              ? null
                              : () => save([...layers]..removeAt(i)),
                          icon: const Icon(Icons.close, size: 16)),
                    ]))),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => save([
                        ...layers,
                        Layer(tr('新构造层', 'Жаңа қабат'), 'Жаңа қабат', 50,
                            LayerMaterial.plaster)
                      ]),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr('添加一层', 'Қабат қосу')))),
          ...extra,
          editableNote(note),
        ]);
  }

  Widget foundationCard() {
    final t = Tokens.of(context);
    final doc = history.present;
    final f = doc.extras.foundation;
    final q = foundationTakeoff(doc, derived);
    String n1(double v) => dec(v.toStringAsFixed(1));
    String n0(double v) => '${v.round()}';
    Future<void> edit(String field, String title) async {
      final v = await askMm(title, f.ints[field]!);
      if (v != null) action('SetFoundation', {'field': field, 'value': v});
    }

    TableCellData e(String text, String field, String title) =>
        TableCellData(text, numeric: true, onTap: () => edit(field, title));
    final params = <List<TableCellData>>[
      [
        TableCellData(tr('类型', 'Түрі')),
        TableCellData(tr('整体浇筑钢筋混凝土条形基础', 'Монолитті темірбетон таспалы іргетас'))
      ],
      [
        TableCellData(tr('宽 mm', 'Ені, мм')),
        e('${f.width}', 'width', tr('基础宽度', 'Іргетас ені'))
      ],
      [
        TableCellData(tr('高 mm', 'Биіктігі, мм')),
        e('${f.height}', 'height', tr('基础高度', 'Іргетас биіктігі'))
      ],
      [
        TableCellData(tr('露出地面 (勒脚) mm', 'Жер үстінде (цоколь), мм')),
        e('${f.plinth}', 'plinth', tr('露出地面高度', 'Цоколь биіктігі'))
      ],
      [
        TableCellData(tr('砂砾石垫层 mm', 'Құм-қиыршық төсеме, мм')),
        e('${f.cushion}', 'cushion', tr('垫层厚度', 'Төсеме қалыңдығы'))
      ],
      [
        TableCellData(tr('垫层每侧加宽 mm', 'Төсеме кеңейтуі, мм')),
        e('${f.cushionExtra}', 'cushionExtra', tr('垫层加宽', 'Кеңейту'))
      ],
      [
        TableCellData(tr('混凝土', 'Бетон')),
        TableCellData(f.concrete, onTap: () async {
          final v = await askText(tr('混凝土', 'Бетон'), f.concrete);
          if (v != null && v.trim().isNotEmpty)
            action('SetFoundation', {'concrete': v.trim()});
        })
      ],
      [
        TableCellData(tr('上部纵筋 根', 'Үстіңгі арматура, дана')),
        e('${f.topBars}', 'topBars', tr('上部纵筋根数', 'Үстіңгі арматура саны'))
      ],
      [
        TableCellData(tr('下部纵筋 根', 'Астыңғы арматура, дана')),
        e('${f.bottomBars}', 'bottomBars', tr('下部纵筋根数', 'Астыңғы арматура саны'))
      ],
      [
        TableCellData(tr('纵筋直径 Ø', 'Арматура Ø')),
        e('${f.barDia}', 'barDia', tr('纵筋直径', 'Арматура диаметрі'))
      ],
      [
        TableCellData(tr('箍筋 Ø / 间距', 'Қамыт Ø / қадамы')),
        TableCellData('Ø${f.stirrupDia} @${f.stirrupStep}',
            numeric: true, onTap: () async {
          await edit('stirrupDia', tr('箍筋直径', 'Қамыт диаметрі'));
          if (mounted) await edit('stirrupStep', tr('箍筋间距', 'Қамыт қадамы'));
        })
      ],
      [
        TableCellData(tr('保护层 mm', 'Қорғаныш қабаты, мм')),
        e('${f.cover}', 'cover', tr('保护层', 'Қорғаныш қабаты'))
      ],
      [
        TableCellData(tr('承重墙判定 (墙厚 ≥) mm', 'Көтергіш қабырға (≥), мм')),
        e('${f.bearingMin}', 'bearingMin', tr('承重墙最小厚度', 'Көтергіш қабырғаның ең аз қалыңдығы'))
      ],
      [
        TableCellData(tr('隔墙基础', 'Қалқа іргетасы')),
        TableCellData(
            f.partitions
                ? '${f.partitionWidth} × ${f.partitionHeight} · ${f.partitionBars}Ø${f.partitionBarDia}'
                : tr('不做 (点此开启)', 'Жоқ (қосу үшін басыңыз)'),
            numeric: f.partitions,
            onTap: () => action('SetFoundation', {'partitions': !f.partitions}))
      ],
    ];
    final kg = barKgPerM;
    final m = unitM, m2 = unitM2, m3 = unitM3;
    final qty = <List<TableCellData>>[
      [
        TableCellData('${tr('主基础长度', 'Негізгі іргетас ұзындығы')} ${f.width}×${f.height}'),
        TableCellData(n1(q.mainLength / 1000), numeric: true),
        TableCellData(m)
      ],
      if (q.partitionLength > 0)
        [
          TableCellData('${tr('隔墙基础长度', 'Қалқа іргетасы ұзындығы')} ${f.partitionWidth}×${f.partitionHeight}'),
          TableCellData(n1(q.partitionLength / 1000), numeric: true),
          TableCellData(m)
        ],
      [
        TableCellData(tr('混凝土', 'Бетон')),
        TableCellData('${n1(q.concrete / 1e9)} (+3% ≈ ${n1(q.concrete * 1.03 / 1e9)})',
            numeric: true),
        TableCellData(m3)
      ],
      [
        TableCellData('${tr('纵筋', 'Бойлық арматура')} Ø${f.barDia}'),
        TableCellData(
            '${n0(q.mainBarLength / 1000)} $m ≈ ${n0(q.mainBarLength / 1000 * kg(f.barDia))} kg',
            numeric: true),
        const TableCellData('')
      ],
      if (q.partitionLength > 0)
        [
          TableCellData('${tr('隔墙纵筋', 'Қалқа арматурасы')} Ø${f.partitionBarDia}'),
          TableCellData(
              '${n0(q.partitionBarLength / 1000)} $m ≈ ${n0(q.partitionBarLength / 1000 * kg(f.partitionBarDia))} kg',
              numeric: true),
          const TableCellData('')
        ],
      [
        TableCellData('${tr('箍筋', 'Қамыт')} Ø${f.stirrupDia}'),
        TableCellData(
            '${q.stirrups} ${tr('个', 'дана')} · ${n0(q.stirrupLength / 1000)} $m ≈ ${n0(q.stirrupLength / 1000 * kg(f.stirrupDia))} kg',
            numeric: true),
        const TableCellData('')
      ],
      [
        TableCellData('${tr('挖土 (沟宽', 'Топырақ қазу (ор ені')} ${dec(((f.width + 600) / 1000).toStringAsFixed(2))})'),
        TableCellData(n1(q.excavation / 1e9), numeric: true),
        TableCellData(m3)
      ],
      [
        TableCellData(tr('砂砾石垫层', 'Құм-қиыршық төсеме')),
        TableCellData(n1(q.cushion / 1e9), numeric: true),
        TableCellData(m3)
      ],
      [
        TableCellData(tr('模板 (两侧)', 'Қалып (екі жағы)')),
        TableCellData(n1(q.formwork / 1e6), numeric: true),
        TableCellData(m2)
      ],
      [
        TableCellData(tr('外侧 XPS 50', 'Сыртқы XPS 50')),
        TableCellData(n1(q.xps / 1e6), numeric: true),
        TableCellData(m2)
      ],
      [
        TableCellData(tr('保温散水 (混凝土 + XPS)', 'Жылы отмостка (бетон + XPS)')),
        TableCellData(n1(q.blinding / 1e6), numeric: true),
        TableCellData(m2)
      ],
      [
        TableCellData(tr('水平防水 (2 层)', 'Көлденең гидрооқшау (2 қабат)')),
        TableCellData(n1(q.waterproofing / 1e6), numeric: true),
        TableCellData(m2)
      ],
      [
        TableCellData(tr('预留套管', 'Гильзалар')),
        TableCellData('${doc.extras.sleeves.length}', numeric: true),
        TableCellData(tr('个', 'дана'))
      ],
    ];
    final labels = {
      'ground': tr('室外地面', 'жер беті'),
      'wall':
          '${tr('外墙', 'Сыртқы қабырға')} ${doc.defaults.outerWallThickness}',
      'damp': tr('水平防水：2 层卷材', 'Көлденең гидрооқшау: 2 қабат'),
      'topBars': '${tr('上部纵筋', 'Үстіңгі арматура')} ${f.topBars}Ø${f.barDia}',
      'floor': tr('地坪（见地坪构造）', 'Еден (еден құрылымын қараңыз)'),
      'stirrups': '${tr('箍筋', 'Қамыт')} Ø${f.stirrupDia} @${f.stirrupStep}',
      'concrete': '${tr('混凝土', 'Бетон')} ${f.concrete}',
      'bottomBars':
          '${tr('下部纵筋', 'Астыңғы арматура')} ${f.bottomBars}Ø${f.barDia}',
      'cover': '${tr('保护层', 'Қорғаныш қабаты')} ${f.cover} $unitMm',
      'cushion': '${tr('砂砾石垫层', 'Құм-қиыршық')} ${f.cushion}',
      'blind': tr('保温散水 1000 · 下铺 XPS 50', 'Жылы отмостка 1000 · астында XPS 50'),
      'xps': tr('XPS 50 + 沥青防水', 'XPS 50 + битум'),
    };
    return InfoCard(
        title:
            '${tr('条形基础', 'Таспалы іргетас')} · ${f.width} × ${f.height}',
        subtitle: tr('参数可以直接点击修改；剖面、用量和平面图“地基”图层会一起更新。',
            'Параметрлерді басып өзгертіңіз; қима, көлем және жоспардағы «Іргетас» қабаты бірге жаңарады.'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: tr('在平面图中查看', 'Жоспардан көру'),
              visualDensity: VisualDensity.compact,
              onPressed: () => update(() {
                    showFoundation = true;
                    floorIndex = 0;
                    derive();
                    tab = 'plan';
                  }),
              icon: const Icon(Icons.layers_outlined, size: 18)),
          IconButton(
              tooltip: tr('恢复默认参数', 'Әдепкі параметрлер'),
              visualDensity: VisualDensity.compact,
              onPressed: () => action('SetFoundation', {'reset': true}),
              icon: const Icon(Icons.restart_alt, size: 18)),
        ]),
        children: [
          const SizedBox(height: 8),
          SectionView(
              painter: FoundationSectionPainter(
                  t, f, doc.defaults.outerWallThickness, labels)),
          const SizedBox(height: 8),
          grid2([
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('参数', 'Параметрлер'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              PlainTable(rows: params),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                  '${tr('材料用量', 'Материал көлемі')} · ${dec((doc.footprint.width / 1000).toString())}×${dec((doc.footprint.depth / 1000).toString())}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              PlainTable(rows: qty),
              Note(tr('钢筋长度含约 8% 搭接和转角附加筋；未计混凝土垫块和绑扎丝。',
                  'Арматура ұзындығына ~8% жалғау мен бұрыш қосымшасы кірді; тірек пен байлау сымы кірмейді.')),
              const SizedBox(height: 6),
              sleevesEditor(),
            ]),
          ]),
          editableNote('foundation', color: t.warn),
        ]);
  }

  Widget sleevesEditor() {
    final t = Tokens.of(context);
    final sleeves = history.present.extras.sleeves;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('预留套管', 'Гильзалар'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      for (final s in sleeves)
        Row(children: [
          Icon(Icons.circle, size: 10, color: t.chk),
          const SizedBox(width: 6),
          Expanded(
              child: Text('${sleeveName(s.kind)} Ø${s.diameter} · (${s.x}, ${s.y})',
                  style: mono(size: 12))),
          IconButton(
              tooltip: tr('删除', 'Жою'),
              visualDensity: VisualDensity.compact,
              onPressed: () => action('DeleteSleeve', {'sleeveId': s.id}),
              icon: const Icon(Icons.close, size: 16)),
        ]),
      Wrap(spacing: 6, children: [
        for (final kind in SleeveKind.values)
          Btn(
              label: '+ ${sleeveName(kind)}',
              onPressed: () async {
                final walls = wallsOf(derived.floors.first.base,
                        history.present.extras.foundation)
                    .where((w) => w.role == WallRole.exterior)
                    .toList();
                if (walls.isEmpty) return;
                final w = walls[(sleeves.length) % walls.length];
                final cx = ((w.rect.left + w.rect.right) / 2).round(),
                    cy = ((w.rect.bottom + w.rect.top) / 2).round();
                final along = (sleeves.length + 1) * 700;
                action('AddSleeve', {
                  'x': w.horizontal
                      ? (w.rect.left + along).clamp(w.rect.left, w.rect.right).round()
                      : cx,
                  'y': w.horizontal
                      ? cy
                      : (w.rect.bottom + along).clamp(w.rect.bottom, w.rect.top).round(),
                  'diameter': kind == SleeveKind.sewer ? 110 : 50,
                  'kind': kind
                });
                update(() => showFoundation = true);
              }),
      ]),
    ]);
  }

  Widget windowsCard() {
    final windows = [
      for (final g in derived.floors)
        for (final p in g.openings)
          if (p.opening.kind != OpeningKind.door) p
    ];
    final d = history.present.defaults;
    return InfoCard(title: tr('窗', 'Терезе'), children: [
      KvGrid([
        Kv('${windows.length} ${tr('扇', 'дана')}',
            tr('窗 / 推拉门', 'Терезе / сырғымалы есік')),
        Kv(
            '${dec((windows.fold(0.0, (s, p) => s + p.opening.width * p.opening.height) / 1e6).toStringAsFixed(2))} $unitM2',
            tr('总窗面积', 'Жалпы терезе ауданы')),
        Kv('${d.windowSill}', tr('常规窗台高 mm', 'Әдеттегі терезе алды, мм'),
            onTap: () async {
          final v = await askMm(tr('默认窗台高度', 'Әдепкі терезе алды'), d.windowSill);
          if (v != null) action('SetDefault', {'field': 'windowSill', 'value': v});
        }),
        Kv('${d.windowWidth} × ${d.windowHeight}', tr('新窗默认 mm', 'Жаңа терезе, мм'),
            onTap: () async {
          final w = await askMm(tr('默认窗宽', 'Әдепкі терезе ені'), d.windowWidth);
          if (w != null) action('SetDefault', {'field': 'windowWidth', 'value': w});
          if (!mounted) return;
          final h = await askMm(tr('默认窗高', 'Әдепкі терезе биіктігі'), d.windowHeight);
          if (h != null) action('SetDefault', {'field': 'windowHeight', 'value': h});
        }),
      ]),
      editableNote('windows'),
    ]);
  }

  Widget doorsCard() {
    final d = history.present.defaults;
    final entrance = [
      for (final g in derived.floors)
        for (final p in g.openings)
          if (p.opening.id == history.present.mainEntranceOpeningId) p
    ].firstOrNull;
    return InfoCard(title: tr('门', 'Есік'), children: [
      KvGrid([
        Kv(
            entrance == null
                ? '—'
                : '${entrance.opening.width} × ${entrance.opening.height}',
            tr('入户门', 'Кіреберіс есігі')),
        Kv('${d.doorWidth} × ${d.doorHeight}', tr('室内门默认', 'Ішкі есік, әдепкі'),
            onTap: () async {
          final w = await askMm(tr('默认门宽', 'Әдепкі есік ені'), d.doorWidth);
          if (w != null) action('SetDefault', {'field': 'doorWidth', 'value': w});
          if (!mounted) return;
          final h = await askMm(tr('默认门高', 'Әдепкі есік биіктігі'), d.doorHeight);
          if (h != null) action('SetDefault', {'field': 'doorHeight', 'value': h});
        }),
        Kv(
            '${[for (final g in derived.floors) ...g.openings].where((p) => p.opening.kind == OpeningKind.door).length}',
            tr('门 总数', 'Есік саны')),
      ]),
      editableNote('doors'),
    ]);
  }

  // ------------------------------------------------------- quantities tab

  Widget quantitiesTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final multi = doc.floors.length > 1;
    var doorNo = 0, windowNo = 0;
    final rows = <List<TableCellData>>[];
    for (var f = 0; f < doc.floors.length; f++) {
      for (final p in derived.floors[f].openings) {
        final o = p.opening;
        final door = o.kind != OpeningKind.window;
        final code = door ? 'M${++doorNo}' : 'C${++windowNo}';
        rows.add([
          TableCellData(code, bold: true),
          if (multi) TableCellData(displayFloorName(doc.floors[f].name), muted: true),
          TableCellData(openingLabel(p, f), onTap: () async {
            final v = await askText(tr('名称 / 位置', 'Атауы / орны'),
                doc.extras.openingLabels[o.id] ?? openingLabel(p, f));
            if (v != null)
              action('SetOpeningLabel', {
                'openingId': o.id,
                'value': v.trim() == openingLabel(p, f) ? '' : v
              });
          }),
          TableCellData('${o.width} × ${o.height}', numeric: true,
              onTap: () async {
            final w = await askMm(tr('宽度', 'Ені'), o.width);
            if (w != null) action('ResizeOpening', {'openingId': o.id, 'width': w});
            if (!mounted) return;
            final h = await askMm(tr('高度', 'Биіктігі'), o.height);
            if (h != null)
              action('ResizeOpening', {'openingId': o.id, 'height': h});
          }),
          TableCellData(o.sill == 0 ? '—' : '${o.sill}', numeric: true,
              onTap: o is DoorOpening
                  ? null
                  : () async {
                      final v = await askMm(tr('窗台高度', 'Терезе алды'), o.sill);
                      if (v != null)
                        action('ResizeOpening', {'openingId': o.id, 'sill': v});
                    }),
          TableCellData(
              switch (o) {
                DoorOpening() => tr('平开门', 'Ашылмалы есік'),
                SlidingOpening() => tr('推拉门', 'Сырғымалы есік'),
                WindowOpening() => tr('窗', 'Терезе'),
              },
              color: p.status == 'ok' ? null : t.crit,
              onTap: () async {
                final kind = await showModalBottomSheet<OpeningKind>(
                    context: context,
                    builder: (context) => SafeArea(
                            child: ListView(shrinkWrap: true, children: [
                          for (final k in OpeningKind.values)
                            ListTile(
                                title: Text(switch (k) {
                                  OpeningKind.door => tr('平开门', 'Ашылмалы есік'),
                                  OpeningKind.sliding =>
                                    tr('推拉门', 'Сырғымалы есік'),
                                  OpeningKind.window => tr('窗', 'Терезе'),
                                }),
                                selected: k == o.kind,
                                onTap: () => Navigator.pop(context, k))
                        ])));
                if (kind != null && kind != o.kind)
                  action('SetOpeningKind', {'openingId': o.id, 'kind': kind});
              }),
        ]);
      }
    }
    // Areas.
    final areaRows = <List<TableCellData>>[];
    var sumCalc = 0.0, sumLabel = 0.0;
    for (var f = 0; f < doc.floors.length; f++) {
      for (final room in doc.floors[f].rooms) {
        final g = derived.floors[f].base.roomGeometry
            .firstWhere((r) => r.id == room.id);
        final a = g.clearArea / 1e6;
        final lab = doc.extras.rooms[room.id]?.labelArea;
        final l = lab == null ? null : lab / 100;
        sumCalc += a;
        sumLabel += l ?? 0;
        final diff = l == null ? null : a - l;
        areaRows.add([
          TableCellData(displayRoomName(room)),
          if (multi) TableCellData(displayFloorName(doc.floors[f].name), muted: true),
          TableCellData(dec(a.toStringAsFixed(1)), numeric: true),
          TableCellData(l == null ? '—' : dec(l.toStringAsFixed(l % 1 == 0 ? 0 : 1)),
              numeric: true, onTap: () async {
            final text = await promptText(context,
                title: tr('图纸标注面积', 'Сызбадағы аудан'),
                initial: l == null ? '' : '$l',
                cancel: tr('取消', 'Болдырмау'),
                ok: tr('确定', 'Жарайды'),
                number: true,
                suffix: unitM2);
            if (text == null) return;
            final v = double.tryParse(text.replaceAll(',', '.'));
            action('SetRoomInfo', {
              'roomId': room.id,
              'labelArea': v == null ? null : (v * 100).round()
            });
          }),
          TableCellData(
              diff == null
                  ? '—'
                  : '${diff > 0 ? '+' : ''}${dec(diff.toStringAsFixed(1))}',
              numeric: true,
              color: diff != null && diff.abs() > 2 ? t.crit : null),
        ]);
      }
    }
    areaRows.add([
      TableCellData(tr('合计', 'Барлығы'), bold: true),
      if (multi) const TableCellData(''),
      TableCellData(dec(sumCalc.toStringAsFixed(1)), numeric: true, bold: true),
      TableCellData(sumLabel == 0 ? '—' : dec(sumLabel.toStringAsFixed(1)),
          numeric: true, bold: true),
      TableCellData(
          sumLabel == 0
              ? '—'
              : '${sumCalc - sumLabel > 0 ? '+' : ''}${dec((sumCalc - sumLabel).toStringAsFixed(1))}',
          numeric: true,
          bold: true),
    ]);
    return page([
      compareCard(),
      InfoCard(title: tr('门窗表', 'Есік-терезе кестесі'), children: [
        const SizedBox(height: 6),
        PlainTable(header: [
          tr('编号', 'Код'),
          if (multi) tr('楼层', 'Қабат'),
          tr('位置', 'Орны'),
          tr('宽 × 高 mm', 'Ені × биіктігі, мм'),
          tr('窗台 mm', 'Терезе алды, мм'),
          tr('类型', 'Түрі'),
        ], rows: rows),
        if (rows.isEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('还没有门窗，到 2D 平面里拖入。', 'Есік-терезе әлі жоқ, 2D жоспарға сүйреп қосыңыз.'),
                  style: TextStyle(color: t.muted))),
      ]),
      InfoCard(title: tr('房间面积对照', 'Бөлме аудандарын салыстыру'), children: [
        const SizedBox(height: 6),
        PlainTable(header: [
          tr('房间', 'Бөлме'),
          if (multi) tr('楼层', 'Қабат'),
          tr('实算 m²', 'Есеп, м²'),
          tr('图纸 m²', 'Сызба, м²'),
          tr('差值', 'Айырма'),
        ], rows: areaRows),
        editableNote('areas'),
      ]),
      InfoCard(title: tr('主要工程量估算', 'Негізгі көлемдерді бағалау'), children: [
        const SizedBox(height: 6),
        PlainTable(header: [
          tr('项目', 'Атауы'),
          tr('算法', 'Есептеу'),
          tr('数量', 'Мөлшері'),
          '',
        ], rows: quantityRows()),
        editableNote('qty'),
      ]),
    ]);
  }

  List<List<TableCellData>> quantityRows() {
    final doc = history.present;
    final fd = foundationTakeoff(doc, derived), wt = wallTakeoff(doc, derived);
    final w = doc.footprint.width / 1000, d = doc.footprint.depth / 1000;
    final t = doc.defaults.outerWallThickness / 1000;
    final h = wt.height / 1000;
    String ds(num v) => dec(v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''));
    final m = unitM, m2 = unitM2, m3 = unitM3;
    final op = tr('洞口', 'ойықтар');
    final f = doc.extras.foundation;
    final rebarT = (fd.mainBarLength / 1000 * barKgPerM(f.barDia) +
            fd.partitionBarLength / 1000 * barKgPerM(f.partitionBarDia) +
            fd.stirrupLength / 1000 * barKgPerM(f.stirrupDia) +
            fd.partitionStirrupLength / 1000 * barKgPerM(f.partitionStirrupDia)) /
        1000;
    List<TableCellData> row(String item, String how, double value, String unit) => [
          TableCellData(item),
          TableCellData(how, muted: true),
          TableCellData(dec(value.toStringAsFixed(1)), numeric: true),
          TableCellData(unit),
        ];
    final slab = doc.defaults.slabThickness / 1000;
    final roof = doc.roof;
    return [
      row(tr('建筑面积', 'Құрылыс ауданы'), '${ds(w)} × ${ds(d)}', w * d, m2),
      row(tr('首层室内地坪', 'Ішкі еден'), '${ds(w - 2 * t)} × ${ds(d - 2 * t)}',
          (w - 2 * t) * (d - 2 * t), m2),
      row(tr('外墙外表面 (毛)', 'Сыртқы қабырға беті (жалпы)'),
          '${ds(2 * (w + d))} × ${ds(h)}', wt.exteriorGross / 1e6, m2),
      row(tr('外墙门窗洞口', 'Сыртқы қабырға ойықтары'), tr('合计', 'жиыны'),
          wt.exteriorOpenings / 1e6, m2),
      row(tr('外墙净面积 (保温/饰面)', 'Сыртқы қабырға таза ауданы'),
          tr('毛 − 洞口', 'жалпы − ойықтар'),
          (wt.exteriorGross - wt.exteriorOpenings) / 1e6, m2),
      row(tr('外墙砌体', 'Сыртқы қабырға қалауы'), '(L × H − $op) × t',
          wt.exteriorVolume / 1e9, m3),
      row(tr('内承重墙砌体', 'Ішкі көтергіш қабырға'),
          '${ds(wt.bearingLength / 1000)} $m × H − $op', wt.bearingVolume / 1e9, m3),
      row(tr('隔墙砌体', 'Қалқа қабырға қалауы'),
          '${ds(wt.partitionLength / 1000)} $m × H − $op',
          wt.partitionVolume / 1e9, m3),
      row(tr('条形基础长度', 'Таспалы іргетас ұзындығы'),
          f.partitions ? tr('含隔墙', 'қалқамен') : tr('外墙 + 承重墙', 'сыртқы + көтергіш'),
          (fd.mainLength + fd.partitionLength) / 1000, m),
      row(tr('基础混凝土', 'Іргетас бетоны'), '${f.width} × ${f.height}',
          fd.concrete / 1e9, m3),
      row(tr('基础钢筋', 'Іргетас арматурасы'), 'Ø${f.barDia} / Ø${f.stirrupDia}',
          rebarT, tr('吨', 'т')),
      row(tr('基础挖土', 'Іргетас үшін қазу'),
          '${ds((f.width + 600) / 1000)} × ${ds((f.height - f.plinth + f.cushion) / 1000)}',
          fd.excavation / 1e9, m3),
      if (roof.type == RoofType.flat) ...[
        row(tr('屋面板混凝土', 'Жабын плитасы бетоны'), '${ds(w)} × ${ds(d)} × ${ds(slab)}',
            w * d * slab, m3),
        row(tr('屋面防水 / 保温', 'Шатыр гидро- / жылу оқшауы'),
            '${ds(w - 2 * t)} × ${ds(d - 2 * t)}', (w - 2 * t) * (d - 2 * t), m2),
        row(tr('女儿墙上翻防水', 'Парапетке көтерілетін гидрооқшау'),
            '${ds(2 * (w + d) - 4 * t)} × 0.3', (2 * (w + d) - 4 * t) * 0.3, m2),
      ] else
        row(
            tr('坡屋面面积', 'Шатыр ауданы'),
            '(${ds(w)} + 2o)(${ds(d)} + 2o) / cos ${roof.pitchDeg}°',
            (w + 2 * roof.overhang! / 1000) *
                (d + 2 * roof.overhang! / 1000) /
                math.cos(roof.pitchDeg! * math.pi / 180),
            m2),
    ];
  }

  // ----------------------------------------------------------- issues tab

  Widget issuesTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final results = runChecks(doc, derived);
    final building =
        constructionChecks(doc, derived, nameOf: displayRoomName);
    const ruleTitles = {
      'R01': ('房间偏窄', 'Бөлме тар'),
      'R02': ('墙占满了空间', 'Қабырға орынды толық алды'),
      'R03': ('面积偏小', 'Аудан аз'),
      'R04': ('房间没有门', 'Бөлменің есігі жоқ'),
      'R05': ('卧室没有窗', 'Жатын бөлмеде терезе жоқ'),
      'R06': ('楼梯放不下', 'Баспалдақ сыймайды'),
      'R07': ('门窗位置无效', 'Есік-терезе орны жарамсыз'),
      'R08': ('主入口', 'Басты кіреберіс'),
      'R09': ('有空间未划分', 'Бөлінбеген орын бар'),
      'R10': ('门窗重叠', 'Есік-терезе қабаттасады'),
    };
    final items = <({
      Level level,
      String title,
      String text,
      String? floorId,
      List<PlanRect> areas,
      bool foundation,
      UserIssue? own
    })>[
      for (final i in doc.extras.issues)
        (
          level: Level.values[i.level.index],
          title: i.title,
          text: i.text,
          floorId: i.floorId,
          areas: [
            for (final a in i.areas)
              PlanRect(a.$1.toDouble(), a.$2.toDouble(), a.$3.toDouble(),
                  a.$4.toDouble())
          ],
          foundation: false,
          own: i
        ),
      for (final r in results)
        (
          level: r.level == 'important' ? Level.crit : Level.warn,
          title:
              '${r.ruleId} · ${tr(ruleTitles[r.ruleId]!.$1, ruleTitles[r.ruleId]!.$2)}',
          text: coreMessage(r.message),
          floorId: r.floorId,
          areas: [if (r.focus != null) r.focus!],
          foundation: false,
          own: null
        ),
      for (final c in building)
        (
          level: Level.values[c.level.index],
          title: tr(c.title.$1, c.title.$2),
          text: tr(c.text.$1, c.text.$2),
          floorId: c.floorId,
          areas: c.areas,
          foundation: c.showFoundation,
          own: null
        ),
    ]..sort((a, b) {
        // The user's own notes first, then by severity.
        final own = (a.own == null ? 1 : 0).compareTo(b.own == null ? 1 : 0);
        return own != 0 ? own : a.level.index.compareTo(b.level.index);
      });
    final shown = issueFilter == null
        ? items
        : items.where((i) => i.level == issueFilter).toList();
    String levelName(Level l) => switch (l) {
          Level.crit => tr('严重', 'Маңызды'),
          Level.warn => tr('建议改', 'Өзгерткен жөн'),
          Level.chk => tr('需确认', 'Тексеру керек'),
          Level.ok => tr('做得好', 'Жақсы шешім'),
        };
    return page([
      Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PillToggle(
                label: '${tr('全部', 'Барлығы')} ${items.length}',
                checkbox: false,
                selected: issueFilter == null,
                onChanged: (_) => update(() => issueFilter = null)),
            for (final l in Level.values)
              PillToggle(
                  label:
                      '${levelName(l)} ${items.where((i) => i.level == l).length}',
                  checkbox: false,
                  selected: issueFilter == l,
                  onChanged: (v) => update(() => issueFilter = v ? l : null)),
            Btn(
                label: tr('添加问题', 'Мәселе қосу'),
                icon: Icons.add,
                primary: true,
                onPressed: () => editIssue(null)),
          ]),
      if (shown.isEmpty)
        InfoCard(children: [
          Text(tr('没有需要处理的提示', 'Өңдейтін ескерту жоқ'),
              style: TextStyle(color: t.muted))
        ]),
      for (final i in shown)
        Sheet(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                  width: 4,
                  decoration: BoxDecoration(
                      color: levelColor(t, i.level),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      TagPill(levelName(i.level), levelColor(t, i.level)),
                      if (i.own != null) ...[
                        const SizedBox(width: 6),
                        TagPill(tr('我的记录', 'Менің жазбам'), t.muted),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(i.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    if (i.text.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(i.text,
                              style: TextStyle(
                                  fontSize: 13, height: 1.5, color: t.muted))),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (i.areas.isNotEmpty)
                        Btn(
                            label: tr('在平面图中定位', 'Жоспардан көрсету'),
                            icon: Icons.my_location,
                            onPressed: () => locate(i.floorId, i.areas,
                                foundation: i.foundation)),
                      if (i.own != null) ...[
                        Btn(
                            label: tr('编辑', 'Өзгерту'),
                            icon: Icons.edit_outlined,
                            onPressed: () => editIssue(i.own)),
                        Btn(
                            label: tr('删除', 'Жою'),
                            icon: Icons.delete_outline,
                            danger: true,
                            onPressed: () =>
                                action('DeleteIssue', {'issueId': i.own!.id})),
                      ],
                    ]),
                  ])),
            ]))),
      Note(tr('这些阈值属于设计建议，不代表当地建筑法规或结构安全的合规结论。',
          'Бұл шектер — жобалау ұсыныстары, жергілікті құрылыс нормасына не конструкция қауіпсіздігіне сәйкестік қорытындысы емес.')),
    ]);
  }

  /// Show [areas] on the plan of [floorId]: zoom there and make them pulse.
  void locate(String? floorId, List<PlanRect> areas, {bool foundation = false}) {
    final index = history.present.floors.indexWhere((f) => f.id == floorId);
    update(() {
      cancelDrag();
      clearWallSelection();
      clearSelection();
      if (index >= 0) floorIndex = index;
      derive();
      if (foundation) showFoundation = true;
      tab = 'plan';
      tool = 'browse';
      browse = true;
      focus = null;
      flash([
        for (final a in areas)
          a.area == 0 ? PlanRect(a.left - 400, a.bottom - 400, a.right + 400, a.top + 400) : a
      ]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || canvasSize.isEmpty || highlights.isEmpty) return;
      var box = highlights.first;
      for (final a in highlights.skip(1))
        box = PlanRect(math.min(box.left, a.left), math.min(box.bottom, a.bottom),
            math.max(box.right, a.right), math.max(box.top, a.top));
      final r = interactionPainter().rectangle(box, canvasSize).inflate(40);
      final scale = math
          .min(canvasSize.width / r.width, canvasSize.height / r.height)
          .clamp(1.0, 3.0);
      final m = Matrix4.identity()
        ..translateByDouble(canvasSize.width / 2, canvasSize.height / 2, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-r.center.dx, -r.center.dy, 0, 1);
      canvasTransform.value = m;
    });
  }

  Future<void> editIssue(UserIssue? issue) async {
    final title = TextEditingController(text: issue?.title ?? ''),
        text = TextEditingController(text: issue?.text ?? '');
    var level = issue?.level ?? IssueLevel.chk;
    String? roomId;
    final rooms = floor.rooms;
    final saved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialog) => AlertDialog(
                    title: Text(issue == null
                        ? tr('添加问题', 'Мәселе қосу')
                        : tr('编辑问题', 'Мәселені өзгерту')),
                    content: SizedBox(
                        width: 460,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              Wrap(spacing: 6, children: [
                                for (final l in IssueLevel.values)
                                  ChoiceChip(
                                      label: Text(switch (l) {
                                        IssueLevel.crit => tr('严重', 'Маңызды'),
                                        IssueLevel.warn => tr('建议改', 'Өзгерткен жөн'),
                                        IssueLevel.chk => tr('需确认', 'Тексеру керек'),
                                        IssueLevel.ok => tr('做得好', 'Жақсы шешім'),
                                      }),
                                      selected: level == l,
                                      onSelected: (_) =>
                                          setDialog(() => level = l)),
                              ]),
                              const SizedBox(height: 10),
                              TextField(
                                  controller: title,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                      labelText: tr('标题', 'Тақырып'))),
                              const SizedBox(height: 10),
                              TextField(
                                  controller: text,
                                  minLines: 3,
                                  maxLines: 8,
                                  decoration: InputDecoration(
                                      labelText: tr('说明', 'Түсіндірме'))),
                              const SizedBox(height: 10),
                              if (rooms.isNotEmpty)
                                DropdownButtonFormField<String?>(
                                    initialValue: roomId,
                                    decoration: InputDecoration(
                                        labelText: tr('在平面上标记的房间 (可选)',
                                            'Жоспарда белгілейтін бөлме (міндетті емес)')),
                                    items: [
                                      DropdownMenuItem(
                                          value: null,
                                          child: Text(issue?.areas.isNotEmpty ?? false
                                              ? tr('保留原区域', 'Бұрынғы аймақ')
                                              : tr('不标记', 'Белгілемеу'))),
                                      for (final r in rooms)
                                        DropdownMenuItem(
                                            value: r.id,
                                            child: Text(displayRoomName(r))),
                                    ],
                                    onChanged: (v) => setDialog(() => roomId = v)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(tr('取消', 'Болдырмау'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(tr('保存', 'Сақтау'))),
                    ])));
    if (saved != true || !mounted) return;
    List<(int, int, int, int)>? areas;
    if (roomId != null) {
      final g = base.roomGeometry.firstWhere((r) => r.id == roomId);
      areas = [
        for (final r in g.clearRects)
          (r.left.round(), r.bottom.round(), r.right.round(), r.top.round())
      ];
    }
    if (issue == null) {
      action('AddIssue', {
        'level': level,
        'title': title.text,
        'text': text.text,
        if (areas != null) 'floorId': floor.id,
        if (areas != null) 'areas': areas,
      });
    } else {
      action('UpdateIssue', {
        'issueId': issue.id,
        'level': level,
        'title': title.text,
        'text': text.text,
        if (areas != null) 'floorId': floor.id,
        if (areas != null) 'areas': areas,
      });
    }
  }
}

class _MaterialSwatch extends CustomPainter {
  const _MaterialSwatch(this.material, this.t);
  final LayerMaterial material;
  final Tokens t;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    paintMaterial(canvas, r, material, t);
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = t.ink
          ..strokeWidth = 0.8);
  }

  @override
  bool shouldRepaint(covariant _MaterialSwatch old) => old.material != material;
}
