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
    final roof = doc.roof.type == RoofType.flat
        ? tr('平屋顶', 'тегіс шатыр')
        : tr('双坡屋顶', 'қос беткейлі шатыр');
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
                  '$w × $d $unitMm · ${doc.floors.length} ${tr('层', 'қабат')} · ${tr('外墙', 'сыртқы қабырға')} ${doc.defaults.outerWallThickness} $unitMm · $roof',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 12, color: t.muted)),
            ]));
    final language = Seg<AppLang>(
        label: 'Тіл / 语言',
        value: app.lang,
        items: const [(AppLang.kk, 'Қазақша'), (AppLang.zh, '中文')],
        onChanged: app.setLang);
    final theme = Seg<ThemeChoice>(
        value: app.theme,
        items: [
          (ThemeChoice.auto, tr('◐ 自动', '◐ Авто')),
          (ThemeChoice.day, tr('☀ 日间', '☀ Күндіз')),
          (ThemeChoice.night, tr('☾ 夜间', '☾ Түн')),
        ],
        onChanged: app.setTheme);
    final floors = Seg<int>(
        label: tr('楼层', 'Қабат'),
        value: floorIndex,
        items: [
          for (var i = 0; i < doc.floors.length; i++) (i, displayFloorName(doc.floors[i].name))
        ],
        onChanged: selectFloor);
    Widget icon(String zh, String kk, IconData data, VoidCallback? onTap,
            {double size = 20}) =>
        IconButton(
            tooltip: zh.trKey(kk),
            onPressed: onTap,
            visualDensity: wide ? null : VisualDensity.compact,
            icon: Icon(data, size: size));
    final floorOps = icon('楼层操作', 'Қабат әрекеттері', Icons.layers_outlined,
        floorOptions);
    final sizeButton = icon('房屋长宽', 'Үйдің ені мен ұзындығы',
        Icons.aspect_ratio, footprintOptions);
    final history_ = Row(mainAxisSize: MainAxisSize.min, children: [
      icon('撤销', 'Болдырмау', Icons.undo, history.canUndo ? undo : null,
          size: 21),
      icon('重做', 'Қайталау', Icons.redo, history.canRedo ? redo : null,
          size: 21),
    ]);
    final saveButton =
        icon('立即保存', 'Қазір сақтау', Icons.save_outlined, save);
    final more = PopupMenuButton<String>(
        tooltip: '更多操作'.trKey('Басқа әрекеттер'),
        onSelected: (value) {
          if (value == 'checks') showTab('iss');
          if (value == 'settings') settings();
          if (value == 'export') export();
          if (value == 'variant') duplicateAsVariant();
          if (value == 'compare') {
            showTab('qty');
            chooseCompare();
          }
        },
        itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'checks', child: Text(tr('设计检查', 'Жобаны тексеру'))),
              PopupMenuItem(
                  value: 'variant',
                  child: Text(tr('复制为新方案', 'Жаңа нұсқа ретінде көшіру'))),
              PopupMenuItem(
                  value: 'compare',
                  child: Text(tr('方案对比', 'Нұсқаларды салыстыру'))),
              PopupMenuItem(
                  value: 'settings', child: Text(tr('设置', 'Баптаулар'))),
              PopupMenuItem(
                  value: 'export',
                  child: Text(tr('导出 .house', '.house файлын шығару')))
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                const SizedBox(width: 8),
                language,
                const SizedBox(width: 8),
                theme,
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
              tooltip: '撤销'.trKey('Болдырмау'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo, size: 20),
              onPressed: history.canUndo ? undo : null),
          IconButton(
              tooltip: '重做'.trKey('Қайталау'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.redo, size: 20),
              onPressed: history.canRedo ? redo : null),
          PopupMenuButton<String>(
              tooltip: '更多操作'.trKey('Басқа әрекеттер'),
              onSelected: (value) {
                if (value == 'checks') showTab('iss');
                if (value == 'settings') settings();
                if (value == 'export') export();
                if (value == 'variant') duplicateAsVariant();
                if (value == 'compare') {
                  showTab('qty');
                  chooseCompare();
                }
                if (value == 'save') save();
                if (value == 'size') footprintOptions();
                if (value == 'floors') floorOptions();
                if (value == 'lang')
                  app.setLang(app.lang == AppLang.kk ? AppLang.zh : AppLang.kk);
                if (value == 'theme')
                  app.setTheme(ThemeChoice
                      .values[(app.theme.index + 1) % ThemeChoice.values.length]);
              },
              itemBuilder: (context) => [
                    PopupMenuItem(
                        value: 'checks',
                        child: Text(tr('设计检查', 'Жобаны тексеру'))),
                    PopupMenuItem(
                        value: 'variant',
                        child: Text(tr('复制为新方案', 'Жаңа нұсқа ретінде көшіру'))),
                    PopupMenuItem(
                        value: 'compare',
                        child: Text(tr('方案对比', 'Нұсқаларды салыстыру'))),
                    PopupMenuItem(
                        value: 'settings', child: Text(tr('设置', 'Баптаулар'))),
                    PopupMenuItem(
                        value: 'export',
                        child: Text(tr('导出 .house', '.house файлын шығару'))),
                    PopupMenuItem(
                        value: 'lang',
                        child: Text(app.lang == AppLang.kk ? '中文' : 'Қазақша')),
                    PopupMenuItem(
                        value: 'theme',
                        child: Text(switch (app.theme) {
                          ThemeChoice.auto => tr('☀ 日间', '☀ Күндіз'),
                          ThemeChoice.day => tr('☾ 夜间', '☾ Түн'),
                          ThemeChoice.night => tr('◐ 自动', '◐ Авто'),
                        })),
                  ]),
        ]));
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
        title: tr('设计名称', 'Жоба атауы'),
        initial: history.present.meta.name,
        cancel: tr('取消', 'Болдырмау'),
        ok: tr('确定', 'Жарайды'));
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
  String trKey(String kk) => isKk ? kk : this;
}
