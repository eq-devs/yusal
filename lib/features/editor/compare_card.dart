part of '../house_editor.dart';

/// Schemes side by side, after the drafting page's layout comparison: save
/// a variant of this design, pick any other design, compare the figures.
extension _CompareCard on _HouseEditorState {
  Future<void> loadCompare(String id) async {
    try {
      final doc = await widget.store.openProject(id);
      if (mounted)
        update(() {
          compareId = id;
          compareDoc = doc;
        });
    } catch (_) {
      notify(tr3('这个设计无法打开，请检查文件', 'Жобаны ашу мүмкін емес, файлды тексеріңіз', 'Не удалось открыть проект, проверьте файл'));
    }
  }

  Future<void> chooseCompare() async {
    List<ProjectEntry> others;
    try {
      others = (await widget.store.listProjects())
          .where((p) => p.id != widget.entry.id)
          .toList();
    } catch (_) {
      others = [];
    }
    if (!mounted) return;
    if (others.isEmpty) {
      notify(tr3('还没有其他设计，可以先“复制为新方案”',
          'Басқа жоба жоқ, алдымен «Жаңа нұсқа ретінде көшіру»', 'Других проектов пока нет, сначала выберите «Копировать как новый вариант»'));
      return;
    }
    final id = await showMotionSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final p in others)
                ListTile(
                    title: Text(p.document.meta.name),
                    subtitle: Text(
                        '${dec((p.document.footprint.width / 1000).toString())} × ${dec((p.document.footprint.depth / 1000).toString())} $unitM'),
                    onTap: () => Navigator.pop(context, p.id))
            ])));
    if (id != null) await loadCompare(id);
  }

  /// Save a copy of this design as a new scheme and continue in it, with
  /// the original set up for comparison.
  Future<void> duplicateAsVariant() async {
    await save();
    final meta = history.present.meta;
    final existing = await widget.store
        .listProjects()
        .then((l) => l.map((p) => p.document.meta.name).toSet())
        .catchError((_) => <String>{});
    var n = 2;
    String name() => '${meta.name} · ${tr3('方案', 'нұсқа', 'вариант')} $n';
    while (existing.contains(name())) n++;
    final now = DateTime.now().toUtc().toIso8601String();
    final copy = composeDocument(
        Meta(name: name(), createdAt: now, updatedAt: now),
        extractDesignState(history.present));
    try {
      final id = await widget.store.createProject(copy);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => HouseEditor(
              entry: ProjectEntry(id, copy),
              store: widget.store,
              compareWithId: widget.entry.id)));
    } catch (_) {
      notify(tr3('无法创建，请检查存储空间', 'Жасау мүмкін емес, жадты тексеріңіз', 'Не удалось создать, проверьте свободное место'));
    }
  }

  Future<void> openCompared() async {
    final id = compareId, doc = compareDoc;
    if (id == null || doc == null) return;
    await save();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => HouseEditor(
            entry: ProjectEntry(id, doc),
            store: widget.store,
            compareWithId: widget.entry.id)));
  }

  Widget compareCard() {
    final other = compareDoc;
    final actions = Wrap(spacing: 8, runSpacing: 8, children: [
      Btn(
          label: tr3('复制为新方案', 'Жаңа нұсқа ретінде көшіру', 'Копировать как новый вариант'),
          icon: Icons.copy_all_outlined,
          onPressed: duplicateAsVariant),
      Btn(
          label: other == null
              ? tr3('选择要对比的设计', 'Салыстыратын жобаны таңдау', 'Выбрать проект для сравнения')
              : tr3('换一个', 'Басқасын таңдау', 'Выбрать другой'),
          icon: Icons.compare_arrows,
          onPressed: chooseCompare),
      if (other != null)
        Btn(
            label: tr3('打开它', 'Соны ашу', 'Открыть его'),
            icon: Icons.open_in_new,
            onPressed: openCompared),
    ]);
    if (other == null)
      return InfoCard(
          title: tr3('方案对比', 'Нұсқаларды салыстыру', 'Сравнение вариантов'),
          subtitle: tr3('把这个设计复制成新方案修改，再和原来的并排比较面宽、面积、跨度和房间。',
              'Жобаны жаңа нұсқа етіп көшіріп өзгертіңіз, сосын ені, ауданы, аралықтары мен бөлмелерін қатар салыстырыңыз.', 'Скопируйте проект как новый вариант и измените его, затем сравните рядом ширину, площадь, пролёты и комнаты.'),
          children: [const SizedBox(height: 10), actions]);
    final a = summarizeDesign(history.present, derived,
        nameOf: displayRoomName, floorName: (f) => displayFloorName(f.name));
    final b = summarizeDesign(other, deriveHouse(other),
        nameOf: displayRoomName, floorName: (f) => displayFloorName(f.name));
    String m(double mm) => dec((mm / 1000).toStringAsFixed(mm % 1000 == 0 ? 0 : 1));
    String m2(double mm2) => '${dec((mm2 / 1e6).toStringAsFixed(1))} $unitM2';
    String list(List<String> names) =>
        names.isEmpty ? '—' : names.join(isKk ? ', ' : '、');
    String spans(List<double> s) => s.isEmpty
        ? '—'
        : '${s.map((x) => dec((x / 1000).toStringAsFixed(1))).join(' / ')} $unitM';
    final rooms = <String>{...a.roomAreas.keys, ...b.roomAreas.keys}.toList();
    TableCellData cell(String v, {bool numeric = true}) =>
        TableCellData(v, numeric: numeric);
    final rows = <List<TableCellData>>[
      [
        TableCellData(tr3('入口一侧面宽', 'Кіреберіс жақтағы ені', 'Ширина со стороны входа')),
        cell('${m(a.frontWidth)} $unitM'),
        cell('${m(b.frontWidth)} $unitM'),
      ],
      [
        TableCellData(tr3('地块最小宽度（两侧各留 3 m）', 'Учаскенің ең аз ені (екі жақтан 3 м)', 'Минимальная ширина участка (по 3 м с каждой стороны)')),
        cell('${m(a.frontWidth + 6000)} $unitM'),
        cell('${m(b.frontWidth + 6000)} $unitM'),
      ],
      [
        TableCellData(tr3('建筑面积 / 外墙长度', 'Құрылыс ауданы / сыртқы қабырға', 'Общая площадь / наружные стены')),
        cell('${m2(a.buildingArea)} / ${m(a.exteriorLength)} $unitM'),
        cell('${m2(b.buildingArea)} / ${m(b.exteriorLength)} $unitM'),
      ],
      for (final r in rooms)
        [
          TableCellData(r),
          cell(a.roomAreas[r] == null ? '—' : m2(a.roomAreas[r]!)),
          cell(b.roomAreas[r] == null ? '—' : m2(b.roomAreas[r]!)),
        ],
      [
        TableCellData(tr3('屋面板跨度', 'Жабын плитасының аралығы', 'Пролёт плиты покрытия')),
        cell(spans(a.spans)),
        cell(spans(b.spans)),
      ],
      [
        TableCellData(tr3('卧室怎么进', 'Жатын бөлмеге кіру', 'Вход в спальни')),
        cell(
            a.bedroomsThroughLiving.isEmpty
                ? tr3('全部不穿过客厅', 'Қонақ бөлме арқылы емес', 'Не через гостиную')
                : '${list(a.bedroomsThroughLiving)} ${tr3('要穿过客厅', '— қонақ бөлме арқылы', '— через гостиную')}',
            numeric: false),
        cell(
            b.bedroomsThroughLiving.isEmpty
                ? tr3('全部不穿过客厅', 'Қонақ бөлме арқылы емес', 'Не через гостиную')
                : '${list(b.bedroomsThroughLiving)} ${tr3('要穿过客厅', '— қонақ бөлме арқылы', '— через гостиную')}',
            numeric: false),
      ],
      [
        TableCellData(tr3('朝后院 / 露台的房间', 'Аула / террасаға қарайтын бөлмелер', 'Комнаты с окнами на задний двор / террасу')),
        cell(list(a.backRooms), numeric: false),
        cell(list(b.backRooms), numeric: false),
      ],
      [
        TableCellData(tr3('临街立面', 'Көше жақ қасбет', 'Уличный фасад')),
        cell(list(a.frontRooms), numeric: false),
        cell(list(b.frontRooms), numeric: false),
      ],
    ];
    return InfoCard(
        title: tr3('方案对比', 'Нұсқаларды салыстыру', 'Сравнение вариантов'),
        subtitle: tr3('左列是正在编辑的设计；改动会立刻反映在表里。',
            'Сол бағанда — қазір өзгертіліп жатқан жоба; өзгерістер кестеде бірден көрінеді.', 'В левом столбце — проект, который вы сейчас редактируете; изменения сразу отражаются в таблице.'),
        children: [
          const SizedBox(height: 8),
          PlainTable(
              header: [
                '',
                history.present.meta.name,
                other.meta.name,
              ],
              highlightColumn: 1,
              rows: rows),
          Note(tr3('造价主要取决于建筑面积和外墙长度。地块够宽、后院朝南时，让卧室和客厅朝后院；地块窄时选面宽小的方案。',
              'Құны негізінен құрылыс ауданы мен сыртқы қабырға ұзындығына байланысты. Учаске кең әрі аула оңтүстікте болса, жатын бөлмелер мен қонақ бөлмені аулаға қаратыңыз; учаске тар болса, ені кішісін таңдаңыз.', 'Стоимость в основном зависит от общей площади и длины наружных стен. Если участок широкий, а задний двор выходит на юг, сориентируйте спальни и гостиную на задний двор; если участок узкий, выберите вариант с меньшей шириной.')),
          const SizedBox(height: 10),
          actions,
        ]);
  }
}
