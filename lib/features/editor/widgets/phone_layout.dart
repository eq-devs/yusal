part of '../page.dart';

/// The phone layout: the drawing fills the page; a frosted bar on top
/// (back, name and floor, history, more) and one at the bottom (plan or
/// 3D, the one "add" button, the assistant) float over it. Everything
/// else is one tap away on a sheet, and the other pages open over the
/// drawing with a way back.
extension _PhoneLayout on _HouseEditorState {
  static const bottomBar = 68.0;

  /// Taller with large text, so the name and the floor both fit.
  double get topBar =>
      math.max(56, MediaQuery.textScalerOf(context).scale(40) + 8);

  /// The drawing and its two views; any other page opens over them.
  bool get mainTab => tab == 'plan' || tab == 'ext' || tab == 'walk';
  bool get phonePage => phone && !mainTab;

  Widget phoneBody() {
    final main = mainTab;
    final card = tab == 'plan' ? selectionCard() : null;
    final up = safeInsets.top;
    final down = safeInsets.bottom;
    // A new selection takes the sheet over; when it is let go, the sheet
    // is back at its bar, not where the tools were left.
    if (card != null) {
      dockDetent = DockDetent.small;
      dockPage = 'add';
    }
    return LayoutBuilder(
        builder: (context, c) => Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  top: topBar,
                  bottom: main ? _PhoneLayout.bottomBar : 0,
                  child: FadeOnChange(
                      value: tab,
                      child: tab == 'plan' ? phonePlan() : tabBody(false))),
              Positioned(
                  top: -up,
                  left: 0,
                  right: 0,
                  height: topBar + up,
                  child: phoneTopBar()),
              if (main)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: -down,
                    child: phoneDock(card, c.maxHeight - topBar + down)),
            ]));
  }

  /// The one sheet at the bottom of the drawing. It stays: its bar (plan or
  /// 3D, add, the assistant) rises to show the tools, the card of the
  /// selection takes its place, and neither ever dims or blocks the plan.
  Widget phoneDock(Widget? card, double room) {
    final t = Tokens.of(context);
    final down = safeInsets.bottom;
    final parts = card is DockParts ? card : null;
    final selected = parts != null;
    final detent = selected
        ? (panelCollapsed
            ? DockDetent.small
            : panelFull
                ? DockDetent.large
                : DockDetent.medium)
        : dockDetent;
    final hint = tab == 'plan' && !selected ? phoneHint() : null;
    // What rides on top of the sheet, as a map's buttons ride on its
    // sheet: the assistant over a card, the hint and the layers over the
    // bar. Out of the way at the top stop.
    final Widget? above = detent == DockDetent.large
        ? null
        : selected
            ? const Padding(
                padding: EdgeInsets.only(right: 12, bottom: 8),
                child: Align(
                    alignment: Alignment.centerRight, child: VoiceSlot()))
            : tab == 'plan'
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 14, 10),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: hint ?? const SizedBox.shrink()),
                          const SizedBox(width: 12),
                          layersButton(),
                        ]))
                : null;
    final sheet = DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: t.dark ? 0.32 : 0.1),
                  blurRadius: 18,
                  offset: const Offset(0, -2))
            ]),
        child: DockSheet(
            contentKey: selected ? 'sel:$selectionIdentity' : 'bar:$tab',
            gripKey: Key(selected ? 'selection-grip' : 'dock-grip'),
            detent: detent,
            maxHeight: math.max(200, room),
            bottomPadding: down,
            color: t.panel,
            gripColor: t.line,
            reduceMotion: Motion.reduced(context),
            onDetent: (d) => update(() {
                  if (selected) {
                    panelCollapsed = d == DockDetent.small;
                    panelFull = d == DockDetent.large;
                  } else {
                    dockDetent = d;
                    if (d == DockDetent.small) dockPage = 'add';
                  }
                }),
            header: selected ? parts.header : phoneToolbar(),
            body: selected
                ? parts.body
                : tab == 'plan'
                    ? addPanel()
                    : null));
    return Column(
        key: barsKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Motion.reduced(context))
            above ?? const SizedBox.shrink()
          else
            AnimatedSwitcher(
                duration: Motion.fast,
                child: above ?? const SizedBox.shrink()),
          sheet,
        ]);
  }

  /// The plan with nothing around it: no frame, no zoom buttons, no rows.
  Widget phonePlan() {
    return Stack(key: planSheetKey, clipBehavior: Clip.none, children: [
      Positioned.fill(child: planCanvas()),
      Positioned(top: 8, left: 12, right: 12, child: statusChip()),
      if (wallMenuCard() case final menu?) menu,
      if (loupe() case final l?) l,
    ]);
  }

  Widget frostedBar({required Widget child, required bool top}) {
    final t = Tokens.of(context);
    return ClipRect(
        child: Frost(
            sigma: 18,
            child: DecoratedBox(
                decoration:
                    BoxDecoration(color: t.bg.withValues(alpha: 0.86)),
                child: child)));
  }

  Widget phoneTopBar() {
    final t = Tokens.of(context);
    final doc = history.present;
    final labels = {for (final (key, label) in editorTabs) key: label};
    Widget icon(String tip, IconData data, VoidCallback? onTap, {Key? key}) =>
        IconButton(
        key: key,
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(data, size: 21));
    final title = mainTab
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: renameProject,
                    child: Text(doc.meta.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: t.ink))),
                const SizedBox(height: 2),
                Row(children: [
                  // The floor being drawn; a tap lists the floors.
                  Material(
                      color: softFill(t),
                      shape: const StadiumBorder(),
                      child: InkWell(
                          key: const Key('floor-pill'),
                          customBorder: const StadiumBorder(),
                          onTap: floorOptions,
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(9, 2, 4, 2),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: 110),
                                        child: Text(
                                            displayFloorName(floor.name),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: t.ink))),
                                    Icon(Icons.expand_more,
                                        size: 16, color: t.muted)
                                  ])))),
                  const SizedBox(width: 8),
                  Flexible(
                      child: DefaultTextStyle.merge(
                          style: TextStyle(color: t.muted),
                          child: IconTheme.merge(
                              data: IconThemeData(color: t.muted),
                              child: saveIndicator()))),
                ]),
              ])
        : Text(labels[tab] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: t.ink));
    return frostedBar(
        top: true,
        child: Padding(
            padding: EdgeInsets.only(right: 4, top: safeInsets.top),
            child: Row(children: [
              BackButton(color: t.ink),
              Expanded(child: title),
              icon(
                  '撤销'.trKey('Болдырмау', 'Отменить', 'Undo', 'Артка кайтаруу', 'Bekor qilish'),
                  Icons.undo,
                  history.canUndo ? undo : null),
              icon(
                  '重做'.trKey('Қайталау', 'Повторить', 'Redo', 'Кайра аткаруу', 'Qaytarish'),
                  Icons.redo,
                  history.canRedo ? redo : null),
              icon(
                  '更多操作'.trKey('Басқа әрекеттер', 'Другие действия', 'More actions', 'Дагы аракеттер', 'Boshqa amallar'),
                  Icons.more_horiz,
                  phoneMore,
                  key: const Key('editor-more')),
            ])));
  }

  /// The sheet's bar: plan or 3D, the one "add" button, the assistant.
  Widget phoneToolbar() {
    final t = Tokens.of(context);
    final flat = tab == 'plan';
    Widget segment(String key, String label, bool on, String to,
            {IconData? icon, VoidCallback? go}) =>
        Semantics(
        button: true,
        selected: on,
        label: icon == null ? null : label,
        child: AnimatedContainer(
            duration: Motion.reduced(context) ? Duration.zero : Motion.fast,
            decoration: BoxDecoration(
                color: on ? t.panel : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: on
                    ? [
                        BoxShadow(
                            color: Colors.black
                                .withValues(alpha: t.dark ? 0.3 : 0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1))
                      ]
                    : null),
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    key: ValueKey(key),
                    customBorder: const StadiumBorder(),
                    onTap: on ? null : go ?? () => showTab(to),
                    child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: icon == null ? 14 : 12,
                            vertical: icon == null ? 9 : 7),
                        child: icon != null
                            ? Tooltip(
                                message: label,
                                excludeFromSemantics: true,
                                child: Icon(icon,
                                    size: 21, color: on ? t.ink : t.muted))
                            : Text(label,
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 1.2,
                                    color: on ? t.ink : t.muted,
                                    fontWeight: on
                                        ? FontWeight.w700
                                        : FontWeight.w500)))))));
    final views = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: softFill(t), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          segment('quick-2d',
              tr3('平面', 'Жоспар', 'План', 'Plan', ky: 'План', uz: 'Reja'), flat, 'plan'),
          segment('quick-3d', '3D', tab == 'ext', 'ext'),
          // Inside the house: the walk-through, one tap away like the
          // other two views.
          segment(
              'quick-walk',
              tr3('室内漫游', 'Ішкі серуен', 'Прогулка по дому',
                  'Walk through the house',
                  ky: 'Үйдүн ичин кыдыруу', uz: 'Uy ichini aylanish'),
              tab == 'walk',
              'walk',
              icon: Icons.directions_walk,
              go: walkHere),
        ]));
    final addLabel = tr3('添加', 'Қосу', 'Добавить', 'Add', ky: 'Кошуу', uz: 'Qoʻshish');
    final open = flat && dockDetent != DockDetent.small;
    // Three views, "add" and the assistant share one row: in a long
    // language, with large text or on a small phone "add" keeps only its
    // plus sign rather than push the row off the screen.
    final scaler = MediaQuery.textScalerOf(context);
    double textWidth(String text) => (TextPainter(
            text: TextSpan(
                text: text,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1)
          ..layout())
        .width;
    final viewsWidth = 6 +
        textWidth(tr3('平面', 'Жоспар', 'План', 'Plan', ky: 'План', uz: 'Reja')) +
        28 +
        textWidth('3D') +
        28 +
        21 +
        24;
    final addWidth = 40 + 20 + 8 + textWidth(addLabel);
    final addFits = 24 + viewsWidth + addWidth + 44 + 24 <=
        MediaQuery.sizeOf(context).width;
    return SizedBox(
        height: _PhoneLayout.bottomBar - 18,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(children: [
              views,
              const Spacer(),
              // The one accent on the page: everything that can be put
              // into the house starts here.
              if (flat)
                Tooltip(
                    message: addLabel,
                    // Open, the same button puts the tools away.
                    child: Builder(builder: (context) {
                      final plus = AnimatedRotation(
                          turns: open ? 0.125 : 0,
                          duration:
                              Motion.reduced(context) ? Duration.zero : Motion.fast,
                          child: Icon(Icons.add, size: addFits ? 20 : 22));
                      return addFits
                          ? FilledButton.icon(
                              key: const Key('plan-add'),
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20)),
                              onPressed: moreTools,
                              icon: plus,
                              label: Text(addLabel))
                          : Semantics(
                              label: addLabel,
                              button: true,
                              excludeSemantics: true,
                              child: FilledButton(
                                  key: const Key('plan-add'),
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size(46, 46),
                                      padding: EdgeInsets.zero,
                                      shape: const CircleBorder()),
                                  onPressed: moreTools,
                                  child: plus));
                    })),
              const Spacer(),
              const VoiceSlot(),
            ])));
  }

  /// What the tool in hand wants next, with its own buttons; while just
  /// looking, only what the checks found and what the house would cost.
  Widget? phoneHint() {
    final t = Tokens.of(context);
    final coach = !view3d && coachText != null && placementHint == null;
    final idle = browse && !coach && placementHint == null;
    var children = hintChildren(t, coach);
    if (idle) children = [for (final c in children) if (c is! Expanded) c];
    if (children.isEmpty) return null;
    return Align(
        alignment: Alignment.bottomLeft,
        child: Material(
            color: t.panel.withValues(alpha: 0.96),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(idle ? 999 : 18)),
            child: Padding(
                padding: EdgeInsets.fromLTRB(idle ? 4 : 14, 2, 4, 2),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    // Two long chips in a long language scroll, never
                    // overflow.
                    child: idle
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: children))
                        : Row(children: children)))));
  }

  Widget layersButton() {
    final t = Tokens.of(context);
    final tip = tr3('图层', 'Қабаттар', 'Слои', 'Layers', ky: 'Катмарлар', uz: 'Qatlamlar');
    return Material(
        color: t.panel.withValues(alpha: 0.96),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: IconButton(
            key: const Key('plan-layers'),
            tooltip: tip,
            onPressed: layersSheet,
            icon: const Icon(Icons.layers_outlined, size: 22)));
  }

  /// What the plan shows, the ruler, and the key to the drawing.
  Future<void> layersSheet() async {
    final t = Tokens.of(context);
    final choice = await showMotionSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
            builder: (context, refresh) => SafeArea(
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                      sheetTitle(tr3('图层', 'Қабаттар', 'Слои', 'Layers', ky: 'Катмарлар', uz: 'Qatlamlar')),
                      for (final (label, on, set) in layerToggles())
                        SwitchListTile(
                            contentPadding: tilePad,
                            title: Text(label),
                            value: on,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              set(v);
                              refresh(() {});
                            }),
                      Divider(height: 17, indent: 20, endIndent: 20, color: t.line),
                      ListTile(
                          contentPadding: tilePad,
                          leading: const Icon(Icons.straighten),
                          title: Text(measureLabel),
                          onTap: () => Navigator.pop(context, 'measure')),
                      ListTile(
                          contentPadding: tilePad,
                          leading: const Icon(Icons.fit_screen_outlined),
                          title: Text(tr3('恢复画布视角', 'Көріністі қалпына келтіру', 'Сбросить вид', 'Reset view', ky: 'Көрүнүштү баштапкы абалга келтирүү', uz: 'Koʻrinishni asliga qaytarish')),
                          onTap: () => Navigator.pop(context, 'fit')),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: legend()),
                    ])))));
    if (!mounted) return;
    if (choice == 'measure') toggleMeasure(true);
    if (choice == 'fit') canvasTransform.value = Matrix4.identity();
  }

  Widget sheetTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)));

  /// Everything that used to sit in the header and the page tabs, in
  /// groups: the other pages, the house, copies and files, the app.
  Future<void> phoneMore() async {
    final t = Tokens.of(context);
    final app = ref.read(settingsProvider);
    final labels = {for (final (key, label) in editorTabs) key: label};
    const pageIcons = {
      'site': Icons.landscape_outlined,
      'iss': Icons.fact_check_outlined,
      'walk': Icons.directions_walk,
      'cost': Icons.payments_outlined,
      'qty': Icons.table_rows_outlined,
      'build': Icons.event_note_outlined,
      'det': Icons.architecture,
      'heat': Icons.thermostat_outlined,
    };
    final choice = await showMotionSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          Widget group(String name) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(name,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.muted)));
          Widget row(String value, IconData icon, String text) => ListTile(
              key: value.startsWith('tab:')
                  ? ValueKey('tab-${value.substring(4)}')
                  : ValueKey('more-$value'),
              contentPadding: tilePad,
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(icon, size: 22),
              title: Text(text, style: const TextStyle(fontSize: 15)),
              onTap: () => Navigator.pop(context, value));
          return SafeArea(
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.82),
                  // Not built lazily: the last rows are as real as the first.
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                    group(tr3('页面', 'Беттер', 'Страницы', 'Pages', ky: 'Барактар', uz: 'Sahifalar')),
                    for (final key in pageIcons.keys)
                      row('tab:$key', pageIcons[key]!, labels[key]!),
                    group(tr3('房屋', 'Үй', 'Дом', 'House', ky: 'Үй', uz: 'Uy')),
                    row('roof', Icons.roofing,
                        tr3('屋顶样式', 'Шатыр түрі', 'Тип крыши', 'Roof type', ky: 'Чатырдын түрү', uz: 'Tom turi')),
                    row('size', Icons.aspect_ratio,
                        tr3('房屋长宽', 'Үйдің ені мен ұзындығы', 'Ширина и длина дома', 'House width and length', ky: 'Үйдүн туурасы жана узундугу', uz: 'Uy eni va uzunligi')),
                    row('settings', Icons.tune,
                        tr3('设置', 'Баптаулар', 'Настройки', 'Settings', ky: 'Жөндөөлөр', uz: 'Sozlamalar')),
                    group(tr3('方案与导出', 'Нұсқалар мен экспорт', 'Варианты и экспорт', 'Options and export', ky: 'Варианттар жана экспорт', uz: 'Variantlar va eksport')),
                    row('variant', Icons.copy_all_outlined,
                        tr3('复制为新方案', 'Жаңа нұсқа ретінде көшіру', 'Копировать как новый вариант', 'Copy as a new option', ky: 'Жаңы вариант катары көчүрүү', uz: 'Yangi variant sifatida nusxalash')),
                    row('compare', Icons.compare_arrows,
                        tr3('方案对比', 'Нұсқаларды салыстыру', 'Сравнение вариантов', 'Compare options', ky: 'Варианттарды салыштыруу', uz: 'Variantlarni solishtirish')),
                    row('pdf', Icons.picture_as_pdf_outlined,
                        tr3('导出图纸 PDF', 'Сызбаларды PDF ету', 'Экспорт чертежей в PDF', 'Export drawings to PDF', ky: 'Чиймелерди PDF форматына экспорттоо', uz: 'Chizmalarni PDF ga eksport qilish')),
                    row('png', Icons.image_outlined,
                        tr3('导出本层平面图 PNG', 'Қабат жоспарын PNG ету', 'Экспорт плана этажа в PNG', 'Export floor plan to PNG', ky: 'Кабат планын PNG форматына экспорттоо', uz: 'Qavat rejasini PNG ga eksport qilish')),
                    row('export', Icons.ios_share,
                        tr3('导出 .house', '.house файлын шығару', 'Экспорт .house', 'Export .house', ky: '.house экспорттоо', uz: '.house eksport qilish')),
                    group(tr3('应用', 'Қолданба', 'Приложение', 'App', ky: 'Колдонмо', uz: 'Ilova')),
                    row('lang', Icons.language, 'Тіл / Язык / 语言 / Language'),
                    row(
                        'theme',
                        Icons.brightness_6_outlined,
                        switch (app.theme) {
                          ThemeChoice.auto => tr3('☀ 日间', '☀ Күндіз', '☀ День', '☀ Day', ky: '☀ Күндүз', uz: '☀ Kunduzi'),
                          ThemeChoice.day => tr3('☾ 夜间', '☾ Түн', '☾ Ночь', '☾ Night', ky: '☾ Түн', uz: '☾ Tun'),
                          ThemeChoice.night => tr3('◐ 自动', '◐ Авто', '◐ Авто', '◐ Auto', ky: '◐ Авто', uz: '◐ Avto'),
                        }),
                    const SizedBox(height: 8),
                  ]))));
        });
    if (choice == null || !mounted) return;
    menuAction(choice);
  }

  /// One thing to put into the house, on the "add" sheet.
  Widget addTile(String key, IconData icon, String label,
      {bool on = false, double? width}) {
    final t = Tokens.of(context);
    return Tooltip(
        message: toolTip(label),
        child: Material(
            color: on ? t.ink : softFill(t),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: InkWell(
                key: ValueKey('add-$key'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => dockChoice('tool:$key'),
                child: SizedBox(
                    width: width,
                    height: 76,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 24, color: on ? t.panel : t.ink),
                          const SizedBox(height: 6),
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(toolLabel(label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: on ? t.panel : t.ink)))
                        ])))));
  }

  /// Something picked on the sheet's tools: the sheet goes back down to
  /// its bar and the tool is in hand. Furniture first shows what to place.
  void dockChoice(String choice) {
    if (choice == 'tool:furniture') {
      HapticFeedback.selectionClick();
      update(() {
        dockPage = 'furniture';
        if (dockDetent == DockDetent.small) dockDetent = DockDetent.medium;
      });
      return;
    }
    update(() => dockDetent = DockDetent.small);
    applyAddChoice(choice);
  }

  /// What the sheet shows as it rises over its bar: the tools, or the
  /// furniture once furniture was picked.
  Widget addPanel() {
    final t = Tokens.of(context);
    Widget label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: t.muted)));
    Widget grid(List<Widget Function(double)> tiles) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 20) / 3;
          return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final tile in tiles) tile(w)]);
        }));
    final tools = Column(
        key: const ValueKey('dock-tools'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          grid([
            (w) => addTile('room', Icons.add_home_outlined, '加房间',
                on: stamping && !stampStair, width: w),
            (w) => addTile('wall', Icons.add_outlined, '墙体',
                on: tool == EditorTool.drawWall, width: w),
            (w) => addTile('door', Icons.door_front_door_outlined, '拖入门',
                on: tool == EditorTool.placeOpening &&
                    placingOpening == OpeningKind.door,
                width: w),
            (w) => addTile('window', Icons.window_outlined, '拖入窗',
                on: tool == EditorTool.placeOpening &&
                    placingOpening == OpeningKind.window,
                width: w),
            (w) => addTile('furniture', Icons.chair_outlined, '家具',
                on: tool == EditorTool.placeFurniture, width: w),
            (w) => addTile(
                'stair',
                Icons.stairs_outlined,
                tr3('楼梯', 'Баспалдақ', 'Лестница', 'Stairs', ky: 'Тепкич', uz: 'Zinapoya'),
                on: stairStamping,
                width: w),
          ]),
          label(tr3('更多工具', 'Басқа құралдар', 'Другие инструменты', 'More tools', ky: 'Дагы аспаптар', uz: 'Boshqa asboblar')),
          grid([
            (w) => addTile('split', Icons.vertical_split_outlined, '拉线分房',
                on: tool == EditorTool.split, width: w),
            (w) => addTile('box', Icons.crop_square, '拖动划房',
                on: tool == EditorTool.box && !stamping, width: w),
            (w) => addTile(
                'utility', Icons.electrical_services_outlined, '水电',
                on: tool == EditorTool.placeUtility, width: w),
            (w) => addTile('selectWall', Icons.view_week_outlined, '墙体调整',
                on: tool == EditorTool.selectWall ||
                    tool == EditorTool.editWall,
                width: w),
            (w) => addTile('resize', Icons.open_in_full, '房屋尺寸',
                on: tool == EditorTool.resize, width: w),
            (w) => addTile('measure', Icons.straighten, measureLabel,
                on: tool == EditorTool.measure, width: w),
          ]),
          const SizedBox(height: 8),
          for (final entry in addChoices.entries)
            ListTile(
                contentPadding: tilePad,
                title: Text(entry.value),
                onTap: () => dockChoice(entry.key)),
          const SizedBox(height: 8),
        ]);
    final furniture = Padding(
        key: const ValueKey('dock-furniture'),
        padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
        child: furniturePalette(
            (kind) {
              HapticFeedback.selectionClick();
              update(() {
                dockPage = 'add';
                dockDetent = DockDetent.small;
              });
              resetInteraction(to: tool);
              startFurniture(kind);
            },
            // A page past the tools, with the way back to them, as in
            // any iOS sheet.
            title: Row(children: [
              IconButton(
                  key: const Key('dock-back'),
                  tooltip: tr3('返回', 'Артқа', 'Назад', 'Back', ky: 'Артка', uz: 'Orqaga'),
                  onPressed: () => update(() => dockPage = 'add'),
                  icon: const Icon(Icons.chevron_left, size: 26)),
              Text(
                  tr3('选择家具', 'Жиһаз таңдау', 'Выбрать мебель',
                      'Pick furniture',
                      ky: 'Эмерек тандоо', uz: 'Mebel tanlash'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ])));
    final page = dockPage == 'furniture' ? furniture : tools;
    if (Motion.reduced(context)) return page;
    return AnimatedSwitcher(
        duration: Motion.fast,
        layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current]),
        child: page);
  }
}
