part of '../page.dart';

/// Page header after the drafting-table layout: the design's name and size,
/// a monospace summary, and the switches (language, theme, floor, history).
extension _EditorHeader on _HouseEditorState {
  Widget editorHeader(bool wide) {
    final t = Tokens.of(context);
    final app = ref.watch(settingsProvider);
    final choose = ref.read(settingsProvider.notifier);
    final doc = history.present;
    final w = doc.footprint.width;
    final d = doc.footprint.depth;
    String meters(int mm) => dec((mm / 1000)
        .toStringAsFixed(mm % 1000 == 0 ? 0 : (mm % 100 == 0 ? 1 : 2)));
    final roof = switch (doc.roof.type) {
      RoofType.flat => tr3('平屋顶', 'тегіс шатыр', 'плоская крыша', 'flat roof', ky: 'жалпак чатыр', uz: 'tekis tom'),
      RoofType.gable => tr3('双坡屋顶', 'қос беткейлі шатыр', 'двускатная крыша', 'gable roof', ky: 'эки капталдуу чатыр', uz: 'ikki nishabli tom'),
      RoofType.hip => tr3('四坡屋顶', 'төрт беткейлі шатыр', 'вальмовая крыша', 'hip roof', ky: 'төрт капталдуу чатыр', uz: 'toʻrt nishabli tom'),
    };
    final title = InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: renameProject,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                    child: Text(doc.meta.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: wide ? 22 : 18,
                            fontWeight: FontWeight.w700,
                            color: t.ink))),
                Flexible(
                    child: Text(' ${meters(w)}×${meters(d)}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            fontSize: wide ? 22 : 18,
                            fontWeight: FontWeight.w700,
                            color: t.ink))),
              ]),
              Text(
                  '$w × $d $unitMm · ${doc.floors.length} ${tr3('层', 'қабат', 'этаж', 'floor', ky: 'кабат', uz: 'qavat')} · ${tr3('外墙', 'сыртқы қабырға', 'наружная стена', 'outer wall', ky: 'сырткы дубал', uz: 'tashqi devor')} ${doc.defaults.outerWallThickness} $unitMm · $roof',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 12, color: t.muted)),
            ]));
    final language = Seg<AppLang>(
        label: 'Тіл / 语言 / Language',
        value: app.lang,
        items: languageNames,
        onChanged: choose.setLang);
    final theme = Seg<ThemeChoice>(
        value: app.theme,
        items: [
          (ThemeChoice.auto, tr3('◐ 自动', '◐ Авто', '◐ Авто', '◐ Auto', ky: '◐ Авто', uz: '◐ Avto')),
          (ThemeChoice.day, tr3('☀ 日间', '☀ Күндіз', '☀ День', '☀ Day', ky: '☀ Күндүз', uz: '☀ Kunduzi')),
          (ThemeChoice.night, tr3('☾ 夜间', '☾ Түн', '☾ Ночь', '☾ Night', ky: '☾ Түн', uz: '☾ Tun')),
        ],
        onChanged: choose.setTheme);
    final floors = Seg<int>(
        label: tr3('楼层', 'Қабат', 'Этаж', 'Floor', ky: 'Кабат', uz: 'Qavat'),
        value: floorIndex,
        items: [
          for (var i = 0; i < doc.floors.length; i++)
            (i, displayFloorName(doc.floors[i].name))
        ],
        onChanged: selectFloor);
    Widget icon(String zh, String kk, String ru, String en, IconData data,
            VoidCallback? onTap,
            {double size = 20, String? ky, String? uz}) =>
        IconButton(
            tooltip: zh.trKey(kk, ru, en, ky, uz),
            onPressed: onTap,
            visualDensity: wide ? null : VisualDensity.compact,
            icon: Icon(data, size: size));
    // The wide header has no room for words; there a pointer shows the
    // tooltip.
    final addFloor = wide
        ? IconButton(
            key: const Key('add-floor'),
            tooltip: '加一层'.trKey('Қабат қосу', 'Добавить этаж', 'Add a floor', 'Кабат кошуу', 'Qavat qoʻshish'),
            onPressed: addFloorAbove,
            icon: const Icon(Icons.add, size: 20))
        : Padding(
            padding: const EdgeInsets.only(left: 6),
            child: OutlinedButton.icon(
                key: const Key('add-floor'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                onPressed: addFloorAbove,
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr3('加一层', 'Қабат қосу', 'Этаж', 'Floor', ky: 'Кабат', uz: 'Qavat'))));
    final floorOps = icon('楼层操作', 'Қабат әрекеттері', 'Действия с этажом',
        'Floor actions', Icons.layers_outlined, floorOptions, ky: 'Кабат боюнча аракеттер', uz: 'Qavat amallari');
    final sizeButton = icon('房屋长宽', 'Үйдің ені мен ұзындығы',
        'Ширина и длина дома', 'House width and length', Icons.aspect_ratio, footprintOptions, ky: 'Үйдүн туурасы жана узундугу', uz: 'Uy eni va uzunligi');
    final history_ = Row(mainAxisSize: MainAxisSize.min, children: [
      icon('撤销', 'Болдырмау', 'Отменить', 'Undo', Icons.undo,
          history.canUndo ? undo : null,
          size: 21, ky: 'Артка кайтаруу', uz: 'Bekor qilish'),
      icon('重做', 'Қайталау', 'Повторить', 'Redo', Icons.redo,
          history.canRedo ? redo : null,
          size: 21, ky: 'Кайра аткаруу', uz: 'Qaytarish'),
    ]);
    final saveButton = icon(
        '立即保存', 'Қазір сақтау', 'Сохранить сейчас', 'Save now',
        Icons.save_outlined, save, ky: 'Азыр сактоо', uz: 'Hozir saqlash');
    final more = PopupMenuButton<String>(
        tooltip: '更多操作'.trKey('Басқа әрекеттер', 'Другие действия', 'More actions', 'Дагы аракеттер', 'Boshqa amallar'),
        onSelected: (value) {
          if (value == 'checks') showTab('iss');
          if (value == 'roof') chooseRoof();
          if (value == 'settings') settings();
          if (value == 'export') export();
          if (value == 'pdf') exportDrawings();
          if (value == 'png') exportDrawings(png: true);
          if (value == 'variant') duplicateAsVariant();
          if (value == 'compare') {
            showTab('qty');
            chooseCompare();
          }
          if (value == 'lang') chooseLanguage();
          if (value == 'theme') {
            choose.setTheme(ThemeChoice
                .values[(app.theme.index + 1) % ThemeChoice.values.length]);
          }
        },
        itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'roof',
                  child: Text(tr3('屋顶样式', 'Шатыр түрі', 'Тип крыши', 'Roof type', ky: 'Чатырдын түрү', uz: 'Tom turi'))),
              PopupMenuItem(
                  value: 'checks',
                  child:
                      Text(tr3('设计检查', 'Жобаны тексеру', 'Проверка проекта', 'Design check', ky: 'Долбоорду текшерүү', uz: 'Loyihani tekshirish'))),
              PopupMenuItem(
                  value: 'variant',
                  child: Text(tr3('复制为新方案', 'Жаңа нұсқа ретінде көшіру',
                      'Копировать как новый вариант',
                      'Copy as a new option', ky: 'Жаңы вариант катары көчүрүү', uz: 'Yangi variant sifatida nusxalash'))),
              PopupMenuItem(
                  value: 'compare',
                  child: Text(tr3(
                      '方案对比', 'Нұсқаларды салыстыру', 'Сравнение вариантов', 'Compare options', ky: 'Варианттарды салыштыруу', uz: 'Variantlarni solishtirish'))),
              PopupMenuItem(
                  value: 'settings',
                  child: Text(tr3('设置', 'Баптаулар', 'Настройки', 'Settings', ky: 'Жөндөөлөр', uz: 'Sozlamalar'))),
              PopupMenuItem(
                  value: 'pdf',
                  child: Text(tr3('导出图纸 PDF', 'Сызбаларды PDF ету',
                      'Экспорт чертежей в PDF',
                      'Export drawings to PDF', ky: 'Чиймелерди PDF форматына экспорттоо', uz: 'Chizmalarni PDF ga eksport qilish'))),
              PopupMenuItem(
                  value: 'png',
                  child: Text(tr3('导出本层平面图 PNG', 'Қабат жоспарын PNG ету',
                      'Экспорт плана этажа в PNG',
                      'Export floor plan to PNG', ky: 'Кабат планын PNG форматына экспорттоо', uz: 'Qavat rejasini PNG ga eksport qilish'))),
              PopupMenuItem(
                  value: 'export',
                  child: Text(tr3(
                      '导出 .house', '.house файлын шығару', 'Экспорт .house', 'Export .house', ky: '.house экспорттоо', uz: '.house eksport qilish'))),
              // On phones language and theme live here, not in the header,
              // so the drawing gets the room.
              if (!wide) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'lang', child: Text('Тіл / Язык / 语言 / Language')),
                PopupMenuItem(
                    value: 'theme',
                    child: Text(switch (app.theme) {
                      ThemeChoice.auto => tr3('☀ 日间', '☀ Күндіз', '☀ День', '☀ Day', ky: '☀ Күндүз', uz: '☀ Kunduzi'),
                      ThemeChoice.day => tr3('☾ 夜间', '☾ Түн', '☾ Ночь', '☾ Night', ky: '☾ Түн', uz: '☾ Tun'),
                      ThemeChoice.night => tr3('◐ 自动', '◐ Авто', '◐ Авто', '◐ Auto', ky: '◐ Авто', uz: '◐ Avto'),
                    })),
              ],
            ]);
    final back = BackButton(color: t.ink);
    if (wide) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
          child: Row(children: [
            back,
            Expanded(child: title),
            const SizedBox(width: 12),
            floors,
            addFloor,
            floorOps,
            sizeButton,
            history_,
            saveButton,
            saveIndicator(),
            more,
            const SizedBox(width: 8),
            // Four languages: on a narrower desktop the switch shrinks
            // rather than pushing the row off the screen.
            Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, child: language)),
            const SizedBox(width: 8),
            theme,
          ]));
    }
    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 4, 0),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [back, Expanded(child: title), history_, more]),
              // The buttons scroll; whether the design is saved stays in
              // sight at the end of the row, whatever the language's length.
              Row(children: [
                Expanded(
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 2, 4, 4),
                        child: Row(children: [
                          floors,
                          addFloor,
                          floorOps,
                          sizeButton,
                          saveButton,
                        ]))),
                Padding(
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    child: saveIndicator()),
              ]),
            ]));
  }

  /// Three groups on top, the pages of the open group under them, and
  /// one button between the drawing and the 3D view.
  Widget groupedTabs() {
    final t = Tokens.of(context);
    final labels = {for (final (key, label) in editorTabs) key: label};
    final group = tabGroup;
    Widget segment(String key, String label) => Expanded(
        child: Semantics(
            button: true,
            selected: key == group,
            child: Material(
                // The thumb behind the row carries the selection.
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                    key: ValueKey('group-$key'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => showTab(lastInGroup[key] ??
                        _HouseEditorState.tabGroups[key]!.first),
                    child: SizedBox(
                        height: 38,
                        child: Center(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: key == group ? t.ink : t.muted,
                                    fontWeight: key == group
                                        ? FontWeight.w700
                                        : FontWeight.w400))))))));
    Widget page(String key) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Semantics(
            button: true,
            selected: key == tab,
            child: Material(
                color:
                    key == tab ? Tokens.mix(t.accent, 0.14, t.panel) : t.panel,
                shape: StadiumBorder(
                    side: BorderSide(
                        color: key == tab ? t.accent : t.line,
                        width: key == tab ? 1.5 : 1)),
                child: InkWell(
                    key: ValueKey('tab-$key'),
                    customBorder: const StadiumBorder(),
                    onTap: () => showTab(key),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        child: Text(labels[key]!,
                            style: TextStyle(
                                fontSize: 13,
                                color: key == tab ? t.accent : t.ink,
                                fontWeight: key == tab
                                    ? FontWeight.w700
                                    : FontWeight.w400)))))));
    final flat = tab == 'plan';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          margin: const EdgeInsets.fromLTRB(12, 2, 12, 0),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              color: Tokens.mix(t.line, 0.55, t.bg),
              borderRadius: BorderRadius.circular(10)),
          child: Stack(children: [
            // One thumb that slides to the open group, as an iOS segmented
            // control does, instead of two fills swapping.
            Positioned.fill(
                child: AnimatedAlign(
                    alignment: Alignment(
                        const {'draw': -1.0, 'view': 0.0, 'build': 1.0}[group]!,
                        0),
                    duration:
                        Motion.reduced(context) ? Duration.zero : Motion.base,
                    curve: Motion.settle,
                    child: FractionallySizedBox(
                        widthFactor: 1 / 3,
                        heightFactor: 1,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: t.panel,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                              BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: t.dark ? 0.3 : 0.08),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1))
                            ]))))),
            Row(children: [
            segment('draw', tr3('画图', 'Сызу', 'Чертёж', 'Drawing', ky: 'Чийме', uz: 'Chizma')),
            segment('view', tr3('看效果', 'Көрініс', 'Вид', 'View', ky: 'Көрүнүш', uz: 'Koʻrinish')),
            segment('build', tr3('造价与施工', 'Смета, құрылыс', 'Смета и стройка', 'Estimate and build', ky: 'Смета жана курулуш', uz: 'Smeta va qurilish')),
          ])])),
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(children: [
            Expanded(
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final key in _HouseEditorState.tabGroups[group]!)
                        page(key)
                    ]))),
            // Drawing and looking are one tap apart, either way.
            if (group != 'build')
              FilledButton.tonalIcon(
                  key: ValueKey(
                      flat || group == 'draw' ? 'quick-3d' : 'quick-2d'),
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: () => showTab(group == 'draw' ? 'ext' : 'plan'),
                  icon: Icon(
                      group == 'draw'
                          ? Icons.view_in_ar_outlined
                          : Icons.grid_on_outlined,
                      size: 16),
                  label: Text(group == 'draw'
                      ? tr3('看 3D', '3D көру', 'В 3D', 'To 3D', ky: '3D көрүнүшкө', uz: '3D ga')
                      : tr3('回平面', 'Жоспарға', 'К плану', 'To the plan', ky: 'Планга', uz: 'Rejaga'))),
          ])),
      Divider(height: 1, color: t.line),
    ]);
  }

  /// One bar for short screens: back, name, page tabs, history, menu.
  Widget compactBar() {
    final t = Tokens.of(context);
    final app = ref.watch(settingsProvider);
    final choose = ref.read(settingsProvider.notifier);
    return Container(
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        padding: const EdgeInsets.fromLTRB(0, 2, 4, 0),
        child: Row(children: [
          BackButton(color: t.ink),
          InkWell(
              onTap: renameProject,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(history.present.meta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)))),
          const SizedBox(width: 8),
          Expanded(
              child:
                  TabStrip(tabs: editorTabs, current: tab, onSelect: showTab)),
          const VoiceSlot(size: 40),
          IconButton(
              tooltip: '撤销'.trKey('Болдырмау', 'Отменить', 'Undo', 'Артка кайтаруу', 'Bekor qilish'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo, size: 20),
              onPressed: history.canUndo ? undo : null),
          IconButton(
              tooltip: '重做'.trKey('Қайталау', 'Повторить', 'Redo', 'Кайра аткаруу', 'Qaytarish'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.redo, size: 20),
              onPressed: history.canRedo ? redo : null),
          PopupMenuButton<String>(
              tooltip: '更多操作'.trKey('Басқа әрекеттер', 'Другие действия', 'More actions', 'Дагы аракеттер', 'Boshqa amallar'),
              onSelected: (value) {
                if (value == 'checks') showTab('iss');
                if (value == 'roof') chooseRoof();
                if (value == 'settings') settings();
                if (value == 'export') export();
                if (value == 'pdf') exportDrawings();
                if (value == 'png') exportDrawings(png: true);
                if (value == 'variant') duplicateAsVariant();
                if (value == 'compare') {
                  showTab('qty');
                  chooseCompare();
                }
                if (value == 'save') save();
                if (value == 'size') footprintOptions();
                if (value == 'floors') floorOptions();
                // All three languages; the old toggle skipped Russian.
                if (value == 'lang') chooseLanguage();
                if (value == 'theme') {
                  choose.setTheme(ThemeChoice.values[
                      (app.theme.index + 1) % ThemeChoice.values.length]);
                }
              },
              itemBuilder: (context) => [
                    PopupMenuItem(
                        value: 'roof',
                        child: Text(tr3('屋顶样式', 'Шатыр түрі', 'Тип крыши', 'Roof type', ky: 'Чатырдын түрү', uz: 'Tom turi'))),
                    PopupMenuItem(
                        value: 'checks',
                        child: Text(
                            tr3('设计检查', 'Жобаны тексеру', 'Проверка проекта', 'Design check', ky: 'Долбоорду текшерүү', uz: 'Loyihani tekshirish'))),
                    PopupMenuItem(
                        value: 'variant',
                        child: Text(tr3('复制为新方案', 'Жаңа нұсқа ретінде көшіру',
                            'Копировать как новый вариант',
                            'Copy as a new option', ky: 'Жаңы вариант катары көчүрүү', uz: 'Yangi variant sifatida nusxalash'))),
                    PopupMenuItem(
                        value: 'compare',
                        child: Text(tr3('方案对比', 'Нұсқаларды салыстыру',
                            'Сравнение вариантов',
                            'Compare options', ky: 'Варианттарды салыштыруу', uz: 'Variantlarni solishtirish'))),
                    PopupMenuItem(
                        value: 'settings',
                        child: Text(tr3('设置', 'Баптаулар', 'Настройки', 'Settings', ky: 'Жөндөөлөр', uz: 'Sozlamalar'))),
                    PopupMenuItem(
                        value: 'pdf',
                        child: Text(tr3('导出图纸 PDF', 'Сызбаларды PDF ету',
                            'Экспорт чертежей в PDF',
                            'Export drawings to PDF', ky: 'Чиймелерди PDF форматына экспорттоо', uz: 'Chizmalarni PDF ga eksport qilish'))),
                    PopupMenuItem(
                        value: 'png',
                        child: Text(tr3('导出本层平面图 PNG', 'Қабат жоспарын PNG ету',
                            'Экспорт плана этажа в PNG',
                            'Export floor plan to PNG', ky: 'Кабат планын PNG форматына экспорттоо', uz: 'Qavat rejasini PNG ga eksport qilish'))),
                    PopupMenuItem(
                        value: 'export',
                        child: Text(tr3('导出 .house', '.house файлын шығару',
                            'Экспорт .house',
                            'Export .house', ky: '.house экспорттоо', uz: '.house eksport qilish'))),
                    const PopupMenuItem(
                        value: 'lang', child: Text('Тіл / Язык / 语言 / Language')),
                    PopupMenuItem(
                        value: 'theme',
                        child: Text(switch (app.theme) {
                          ThemeChoice.auto => tr3('☀ 日间', '☀ Күндіз', '☀ День', '☀ Day', ky: '☀ Күндүз', uz: '☀ Kunduzi'),
                          ThemeChoice.day => tr3('☾ 夜间', '☾ Түн', '☾ Ночь', '☾ Night', ky: '☾ Түн', uz: '☾ Tun'),
                          ThemeChoice.night => tr3('◐ 自动', '◐ Авто', '◐ Авто', '◐ Auto', ky: '◐ Авто', uz: '◐ Avto'),
                        })),
                  ]),
        ]));
  }

  Future<void> chooseLanguage() async {
    final app = ref.read(settingsProvider);
    final choose = ref.read(settingsProvider.notifier);
    final lang = await showMotionSheet<AppLang>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (value, label) in languageNames)
                ListTile(
                    title: Text(label),
                    trailing:
                        value == app.lang ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, value)),
            ])));
    if (lang != null) choose.setLang(lang);
  }

  void selectFloor(int value) => update(() {
        cancelDrag();
        clearWallSelection();
        clearSelection();
        floorIndex = value;
        tool = EditorTool.browse;
        selectedWall = null;
        drawingOrigin = null;
        drawingEnd = null;
        measurePoints = [];
        derive();
      });

  Future<void> renameProject() async {
    final value = await promptText(context,
        title: tr3('设计名称', 'Жоба атауы', 'Название проекта', 'Design name', ky: 'Долбоордун аталышы', uz: 'Loyiha nomi'),
        initial: history.present.meta.name,
        cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'));
    if (value == null || value.trim().isEmpty || !mounted) return;
    final meta = history.present.meta;
    update(() {
      history.present = composeDocument(
          Meta(
              name: value.trim(),
              createdAt: meta.createdAt,
              updatedAt: DateTime.now().toUtc().toIso8601String()),
          extractDesignState(history.present));
      dirty = true;
      status = _SaveStatus.unsaved;
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 1500), save);
    });
  }
}

extension _KeyText on String {
  /// Chinese tooltip kept as the stable key; Kazakh shown when chosen.
  String trKey(String kk, [String? ru, String? en, String? ky, String? uz]) =>
      tr3(this, kk, ru ?? kk, en, ky: ky, uz: uz);
}
