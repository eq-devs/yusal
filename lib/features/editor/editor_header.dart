part of '../house_editor.dart';

/// Page header after the drafting-table layout: the design's name and size,
/// a monospace summary, and the switches (language, theme, floor, history).
extension _EditorHeader on _HouseEditorState {
  Widget editorHeader(bool wide) {
    final t = Tokens.of(context);
    final app = AppScope.watch(context);
    final doc = history.present;
    final w = doc.footprint.width, d = doc.footprint.depth;
    String meters(int mm) => dec((mm / 1000).toStringAsFixed(
        mm % 1000 == 0 ? 0 : (mm % 100 == 0 ? 1 : 2)));
    final roof = switch (doc.roof.type) {
      RoofType.flat => tr3('平屋顶', 'тегіс шатыр', 'плоская крыша'),
      RoofType.gable => tr3('双坡屋顶', 'қос беткейлі шатыр', 'двускатная крыша'),
      RoofType.hip => tr3('四坡屋顶', 'төрт беткейлі шатыр', 'вальмовая крыша'),
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
                  '$w × $d $unitMm · ${doc.floors.length} ${tr3('层', 'қабат', 'этаж')} · ${tr3('外墙', 'сыртқы қабырға', 'наружная стена')} ${doc.defaults.outerWallThickness} $unitMm · $roof',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 12, color: t.muted)),
            ]));
    final language = Seg<AppLang>(
        label: 'Тіл / 语言',
        value: app.lang,
        items: const [
          (AppLang.kk, 'Қазақша'),
          (AppLang.ru, 'Русский'),
          (AppLang.zh, '中文')
        ],
        onChanged: app.setLang);
    final theme = Seg<ThemeChoice>(
        value: app.theme,
        items: [
          (ThemeChoice.auto, tr3('◐ 自动', '◐ Авто', '◐ Авто')),
          (ThemeChoice.day, tr3('☀ 日间', '☀ Күндіз', '☀ День')),
          (ThemeChoice.night, tr3('☾ 夜间', '☾ Түн', '☾ Ночь')),
        ],
        onChanged: app.setTheme);
    final floors = Seg<int>(
        label: tr3('楼层', 'Қабат', 'Этаж'),
        value: floorIndex,
        items: [
          for (var i = 0; i < doc.floors.length; i++) (i, displayFloorName(doc.floors[i].name))
        ],
        onChanged: selectFloor);
    Widget icon(String zh, String kk, String ru, IconData data,
            VoidCallback? onTap,
            {double size = 20}) =>
        IconButton(
            tooltip: zh.trKey(kk, ru),
            onPressed: onTap,
            visualDensity: wide ? null : VisualDensity.compact,
            icon: Icon(data, size: size));
    final floorOps = icon('楼层操作', 'Қабат әрекеттері', 'Действия с этажом',
        Icons.layers_outlined,
        floorOptions);
    final sizeButton = icon('房屋长宽', 'Үйдің ені мен ұзындығы', 'Ширина и длина дома',
        Icons.aspect_ratio, footprintOptions);
    final history_ = Row(mainAxisSize: MainAxisSize.min, children: [
      icon('撤销', 'Болдырмау', 'Отменить', Icons.undo, history.canUndo ? undo : null,
          size: 21),
      icon('重做', 'Қайталау', 'Повторить', Icons.redo, history.canRedo ? redo : null,
          size: 21),
    ]);
    final saveButton =
        icon('立即保存', 'Қазір сақтау', 'Сохранить сейчас',
        Icons.save_outlined, save);
    final more = PopupMenuButton<String>(
        tooltip: '更多操作'.trKey('Басқа әрекеттер', 'Другие действия'),
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
          if (value == 'theme')
            app.setTheme(ThemeChoice
                .values[(app.theme.index + 1) % ThemeChoice.values.length]);
        },
        itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'roof', child: Text(tr3('屋顶样式', 'Шатыр түрі', 'Тип крыши'))),
              PopupMenuItem(
                  value: 'checks', child: Text(tr3('设计检查', 'Жобаны тексеру', 'Проверка проекта'))),
              PopupMenuItem(
                  value: 'variant',
                  child: Text(tr3('复制为新方案', 'Жаңа нұсқа ретінде көшіру', 'Копировать как новый вариант'))),
              PopupMenuItem(
                  value: 'compare',
                  child: Text(tr3('方案对比', 'Нұсқаларды салыстыру', 'Сравнение вариантов'))),
              PopupMenuItem(
                  value: 'settings', child: Text(tr3('设置', 'Баптаулар', 'Настройки'))),
              PopupMenuItem(
                  value: 'pdf',
                  child: Text(tr3('导出图纸 PDF', 'Сызбаларды PDF ету', 'Экспорт чертежей в PDF'))),
              PopupMenuItem(
                  value: 'png',
                  child: Text(tr3('导出本层平面图 PNG', 'Қабат жоспарын PNG ету', 'Экспорт плана этажа в PNG'))),
              PopupMenuItem(
                  value: 'export',
                  child: Text(tr3('导出 .house', '.house файлын шығару', 'Экспорт .house'))),
              // On phones language and theme live here, not in the header,
              // so the drawing gets the room.
              if (!wide) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: 'lang', child: Text('Тіл / Язык / 语言')),
                PopupMenuItem(
                    value: 'theme',
                    child: Text(switch (app.theme) {
                      ThemeChoice.auto => tr3('☀ 日间', '☀ Күндіз', '☀ День'),
                      ThemeChoice.day => tr3('☾ 夜间', '☾ Түн', '☾ Ночь'),
                      ThemeChoice.night => tr3('◐ 自动', '◐ Авто', '◐ Авто'),
                    })),
              ],
            ]);
    final back = BackButton(color: t.ink);
    if (wide)
      return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
          child: Row(children: [
            back,
            Expanded(child: title),
            const SizedBox(width: 12),
            floors,
            floorOps,
            sizeButton,
            history_,
            saveButton,
            saveIndicator(),
            more,
            const SizedBox(width: 8),
            language,
            const SizedBox(width: 8),
            theme,
          ]));
    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 4, 0),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [back, Expanded(child: title), history_, more]),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 4),
              child: Row(children: [
                floors,
                floorOps,
                sizeButton,
                saveButton,
                saveIndicator(),
              ])),
        ]));
  }

  /// One bar for short screens: back, name, page tabs, history, menu.
  Widget compactBar() {
    final t = Tokens.of(context);
    final app = AppScope.watch(context);
    return Container(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.line))),
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
              child: TabStrip(
                  tabs: editorTabs, current: tab, onSelect: showTab)),
          IconButton(
              tooltip: '撤销'.trKey('Болдырмау', 'Отменить'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo, size: 20),
              onPressed: history.canUndo ? undo : null),
          IconButton(
              tooltip: '重做'.trKey('Қайталау', 'Повторить'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.redo, size: 20),
              onPressed: history.canRedo ? redo : null),
          PopupMenuButton<String>(
              tooltip: '更多操作'.trKey('Басқа әрекеттер', 'Другие действия'),
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
                if (value == 'theme')
                  app.setTheme(ThemeChoice
                      .values[(app.theme.index + 1) % ThemeChoice.values.length]);
              },
              itemBuilder: (context) => [
                    PopupMenuItem(
                        value: 'roof',
                        child: Text(tr3('屋顶样式', 'Шатыр түрі', 'Тип крыши'))),
                    PopupMenuItem(
                        value: 'checks',
                        child: Text(tr3('设计检查', 'Жобаны тексеру', 'Проверка проекта'))),
                    PopupMenuItem(
                        value: 'variant',
                        child: Text(tr3('复制为新方案', 'Жаңа нұсқа ретінде көшіру', 'Копировать как новый вариант'))),
                    PopupMenuItem(
                        value: 'compare',
                        child: Text(tr3('方案对比', 'Нұсқаларды салыстыру', 'Сравнение вариантов'))),
                    PopupMenuItem(
                        value: 'settings', child: Text(tr3('设置', 'Баптаулар', 'Настройки'))),
                    PopupMenuItem(
                        value: 'pdf',
                        child: Text(tr3('导出图纸 PDF', 'Сызбаларды PDF ету', 'Экспорт чертежей в PDF'))),
                    PopupMenuItem(
                        value: 'png',
                        child: Text(tr3('导出本层平面图 PNG', 'Қабат жоспарын PNG ету', 'Экспорт плана этажа в PNG'))),
                    PopupMenuItem(
                        value: 'export',
                        child: Text(tr3('导出 .house', '.house файлын шығару', 'Экспорт .house'))),
                    PopupMenuItem(
                        value: 'lang',
                        child: const Text('Тіл / Язык / 语言')),
                    PopupMenuItem(
                        value: 'theme',
                        child: Text(switch (app.theme) {
                          ThemeChoice.auto => tr3('☀ 日间', '☀ Күндіз', '☀ День'),
                          ThemeChoice.day => tr3('☾ 夜间', '☾ Түн', '☾ Ночь'),
                          ThemeChoice.night => tr3('◐ 自动', '◐ Авто', '◐ Авто'),
                        })),
                  ]),
        ]));
  }

  Future<void> chooseLanguage() async {
    final app = AppSettings.instance;
    final lang = await showMotionSheet<AppLang>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (value, label) in const [
                (AppLang.kk, 'Қазақша'),
                (AppLang.ru, 'Русский'),
                (AppLang.zh, '中文')
              ])
                ListTile(
                    title: Text(label),
                    trailing: value == app.lang ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, value)),
            ])));
    if (lang != null) app.setLang(lang);
  }

  void selectFloor(int value) => update(() {
        cancelDrag();
        clearWallSelection();
        clearSelection();
        floorIndex = value;
        tool = 'browse';
        browse = true;
        selectedWall = null;
        drawingOrigin = null;
        drawingEnd = null;
        measurePoints = [];
        derive();
      });

  Future<void> renameProject() async {
    final value = await promptText(context,
        title: tr3('设计名称', 'Жоба атауы', 'Название проекта'),
        initial: history.present.meta.name,
        cancel: tr3('取消', 'Болдырмау', 'Отмена'),
        ok: tr3('确定', 'Жарайды', 'ОК'));
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
      status = '未保存';
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 1500), save);
    });
  }
}

extension _KeyText on String {
  /// Chinese tooltip kept as the stable key; Kazakh shown when chosen.
  String trKey(String kk, [String? ru]) => tr3(this, kk, ru ?? kk);
}
