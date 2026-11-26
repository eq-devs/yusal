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
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
          top: topBar,
          bottom: main ? _PhoneLayout.bottomBar : 0,
          child: FadeOnChange(
              value: tab,
              child: tab == 'plan' ? phonePlan(card != null) : tabBody(false))),
      Positioned(
          top: -up,
          left: 0,
          right: 0,
          height: topBar + up,
          child: phoneTopBar()),
      if (main && card == null)
        Positioned(
            left: 0,
            right: 0,
            bottom: -down,
            height: _PhoneLayout.bottomBar + down,
            child: phoneBottomBar()),
      if (card != null)
        Positioned(
            left: 0,
            right: 0,
            bottom: -down,
            child: Column(
                key: barsKey,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The assistant rides on the card, never under it.
                  const Padding(
                      padding: EdgeInsets.only(right: 12, bottom: 8),
                      child: VoiceSlot()),
                  // Rises in for each new selection, with the click of a
                  // choice.
                  RiseIn(
                      key: ValueKey(selectionIdentity),
                      haptic: true,
                      child: card),
                ])),
    ]);
  }

  /// The plan with nothing around it: no frame, no zoom buttons, no rows.
  Widget phonePlan(bool selected) {
    final hint = selected ? null : phoneHint();
    return Stack(key: planSheetKey, clipBehavior: Clip.none, children: [
      Positioned.fill(child: planCanvas()),
      Positioned(top: 8, left: 12, right: 12, child: statusChip()),
      if (!selected)
        Positioned(right: 14, bottom: 10, child: layersButton()),
      if (hint != null) Positioned(left: 12, right: 68, bottom: 10, child: hint),
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

  Widget phoneBottomBar() {
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
    return frostedBar(
        top: false,
        child: Padding(
            key: barsKey,
            padding: EdgeInsets.fromLTRB(12, 0, 12, safeInsets.bottom),
            child: Row(children: [
              views,
              const Spacer(),
              // The one accent on the page: everything that can be put
              // into the house starts here.
              if (flat)
                Tooltip(
                    message: addLabel,
                    child: addFits
                        ? FilledButton.icon(
                            key: const Key('plan-add'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20)),
                            onPressed: moreTools,
                            icon: const Icon(Icons.add, size: 20),
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
                                child: const Icon(Icons.add, size: 22)))),
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
  Widget addTile(BuildContext sheet, String key, IconData icon, String label,
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
                onTap: () => Navigator.pop(sheet, 'tool:$key'),
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
}
