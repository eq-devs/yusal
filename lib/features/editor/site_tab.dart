part of '../house_editor.dart';

/// The plot: where the house stands, the fence and gate, outbuildings,
/// the garden and the well, with the usual distances checked. Tap to
/// select, drag to move; the card edits sizes and names.
extension _SiteTab on _HouseEditorState {
  /// The plot as drawn, with the piece being dragged moved.
  SitePlan displaySite(SitePlan site) {
    final draft = siteDraft;
    if (draft == null) return site;
    if (selectedSiteId == '@house')
      return site.copyWith(houseX: draft.x, houseY: draft.y);
    return site.copyWith(items: [
      for (final i in site.items)
        i.id == selectedSiteId ? i.copyWith(x: draft.x, y: draft.y) : i
    ]);
  }

  String siteItemName(SiteItem i) => i.label ?? siteName(i.kind);

  /// The house or item under [p] (canvas pixels), buildings before areas.
  String? siteHit(SiteView v, Offset p) {
    final site = v.site;
    final w = v.world(p);
    final ordered = [...site.items]..sort((a, b) =>
        (siteBuildings.contains(b.kind) || b.kind == SiteKind.gate ? 1 : 0)
            .compareTo(siteBuildings.contains(a.kind) || a.kind == SiteKind.gate
                ? 1
                : 0));
    final grow = 10 / v.scale;
    for (final i in ordered)
      if (w.dx >= i.x - grow &&
          w.dx <= i.right + grow &&
          w.dy >= i.y - grow &&
          w.dy <= i.top + grow &&
          (siteBuildings.contains(i.kind) || i.kind == SiteKind.gate))
        return i.id;
    final house = houseOnPlot(history.present, site);
    if (house.contains(w.dx, w.dy)) return '@house';
    for (final i in ordered)
      if (itemRect(i).contains(w.dx, w.dy)) return i.id;
    return null;
  }

  Future<void> addSiteItem() async {
    final kind = await showMotionSheet<SiteKind>(
        context: context,
        builder: (context) => SafeArea(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('添加到院子', 'Аулаға қосу'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final k in SiteKind.values)
                        Btn(
                            label: siteName(k),
                            icon: siteIcon(k),
                            onPressed: () => Navigator.pop(context, k)),
                    ]),
                  ]),
            )));
    if (kind == null || !mounted) return;
    final doc = history.present;
    final site = doc.extras.site ??
        defaultSitePlan(doc.footprint.width, doc.footprint.depth);
    final size = siteDefaults[kind]!;
    final house = houseOnPlot(doc, site);
    // Gates go on the street; the rest behind the house, at the advised
    // distance when there is one, else staggered so they do not stack.
    final gap = houseGaps[kind];
    final x = kind == SiteKind.gate
        ? (house.left + house.right) / 2 - size.$1 / 2 + 3000
        : (site.width - size.$1) / 2;
    final y = kind == SiteKind.gate
        ? 0.0
        : math.min(
            site.depth - size.$2 - 1000.0,
            house.top +
                (gap?.toDouble() ?? 3000 + 2500.0 * (site.items.length % 4)));
    final id = const Uuid().v4();
    action('AddSiteItem', {
      'id': id,
      'kind': kind,
      'x': (x / 100).round() * 100,
      'y': (math.max(0.0, y) / 100).round() * 100,
    });
    update(() => selectedSiteId = id);
  }

  Widget siteTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final saved = doc.extras.site;
    if (saved == null)
      return page([
        InfoCard(
            title: tr('宅基地与院子', 'Учаске және аула'),
            subtitle: tr('画出宅基地、院墙和大门，摆放牲畜棚、澡堂、厕所、水井、菜园等，并检查常见的间距要求。',
                'Учаскені, қоршау мен қақпаны сызып, мал қорасы, монша, дәретхана, құдық, бақша т.б. орналастырыңыз; әдеттегі арақашықтық талаптары тексеріледі.'),
            children: [
              const SizedBox(height: 12),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Btn(
                      label: tr('设置宅基地', 'Учаскені баптау'),
                      icon: Icons.fence_outlined,
                      primary: true,
                      onPressed: () async {
                        final d = defaultSitePlan(
                            doc.footprint.width, doc.footprint.depth);
                        final w = await length(tr('宅基地宽 (临街)', 'Учаске ені (көше жақ)'), d.width);
                        if (w == null || !mounted) return;
                        final dd = await length(tr('宅基地进深', 'Учаске тереңдігі'), d.depth);
                        if (dd == null) return;
                        action('SetSite', {
                          'width': w,
                          'depth': dd,
                          'houseX': math.max(0, ((w - doc.footprint.width) / 2).round()),
                          'houseY': math.min(5000, math.max(0, dd - doc.footprint.depth)),
                        });
                      })),
            ]),
      ]);
    final site = displaySite(saved);
    final checks = siteChecks(doc, nameOf: siteItemName);
    Widget sized(Widget child) => wide
        ? SizedBox(
            height: math.max(420.0, MediaQuery.sizeOf(context).height - 190),
            child: child)
        : AspectRatio(aspectRatio: 0.92, child: child);
    final canvas = Sheet(
        child: sized(LayoutBuilder(builder: (context, c) {
              final size = Size(c.maxWidth, c.maxHeight);
              final view = SiteView(site, size);
              return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => update(() {
                        selectedSiteId = siteHit(view, d.localPosition);
                        siteHighlights = [];
                      }),
                  onPanStart: (d) {
                    final hit = siteHit(view, d.localPosition);
                    if (hit == null) return;
                    final w = view.world(d.localPosition);
                    final at = hit == '@house'
                        ? Offset(saved.houseX.toDouble(), saved.houseY.toDouble())
                        : saved.items
                            .where((i) => i.id == hit)
                            .map((i) => Offset(i.x.toDouble(), i.y.toDouble()))
                            .first;
                    update(() {
                      selectedSiteId = hit;
                      siteDown = w - at;
                      siteDraft = null;
                    });
                  },
                  onPanUpdate: (d) {
                    final grab = siteDown;
                    if (grab == null) return;
                    final w = view.world(d.localPosition) - grab;
                    update(() => siteDraft = (
                          x: (w.dx / 100).round() * 100,
                          y: (w.dy / 100).round() * 100
                        ));
                  },
                  onPanEnd: (_) {
                    final draft = siteDraft, id = selectedSiteId;
                    update(() {
                      siteDraft = null;
                      siteDown = null;
                    });
                    if (draft == null || id == null) return;
                    if (id == '@house') {
                      action('SetSite', {'houseX': draft.x, 'houseY': draft.y});
                    } else {
                      action('UpdateSiteItem',
                          {'siteItemId': id, 'x': draft.x, 'y': draft.y});
                    }
                  },
                  child: CustomPaint(
                      size: size,
                      painter: SitePlanPainter(
                          doc: doc,
                          site: site,
                          tokens: t,
                          selected: selectedSiteId,
                          highlights: siteHighlights,
                          pulse: pulse)));
        })));
    final selectedItem =
        saved.items.where((i) => i.id == selectedSiteId).firstOrNull;
    Widget itemCard(SiteItem i) => InfoCard(
            titleWidget: Row(children: [
              Icon(siteIcon(i.kind), size: 18, color: t.accent),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(siteItemName(i),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            trailing: IconButton(
                tooltip: tr('关闭', 'Жабу'),
                visualDensity: VisualDensity.compact,
                onPressed: () => update(() => selectedSiteId = null),
                icon: const Icon(Icons.close, size: 18)),
            children: [
              KvGrid([
                Kv('${m2dp(i.width)} × ${m2dp(i.depth)}', tr('宽 × 深 (米)', 'Ені × тереңдігі (м)'),
                    onTap: () async {
                  final w = await length(tr('宽', 'Ені'), i.width);
                  if (w == null || !mounted) return;
                  final d = await length(tr('深', 'Тереңдігі'), i.depth);
                  if (d == null) return;
                  action('UpdateSiteItem',
                      {'siteItemId': i.id, 'width': w, 'depth': d});
                }),
                Kv('${dec((i.width * i.depth / 1e6).toStringAsFixed(1))} $unitM2', tr('面积', 'Аудан')),
                Kv('${m2dp(i.x)}, ${m2dp(i.y)}', tr('离左边界、离街道 (米)', 'Сол шекарадан, көшеден (м)'),
                    onTap: () async {
                  final x = await length(tr('离左边界', 'Сол шекарадан'), i.x);
                  if (x == null || !mounted) return;
                  final y = await length(tr('离街道', 'Көшеден'), i.y);
                  if (y == null) return;
                  action('UpdateSiteItem', {'siteItemId': i.id, 'x': x, 'y': y});
                }),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Btn(
                    label: tr('转 90°', '90° бұру'),
                    icon: Icons.rotate_90_degrees_ccw,
                    onPressed: () =>
                        action('RotateSiteItem', {'siteItemId': i.id})),
                Btn(
                    label: tr('名称', 'Атауы'),
                    icon: Icons.edit_outlined,
                    onPressed: () async {
                      final v = await askText(tr('名称', 'Атауы'), siteItemName(i));
                      if (v != null)
                        action('UpdateSiteItem', {
                          'siteItemId': i.id,
                          'label': v.trim() == siteName(i.kind) ? '' : v.trim()
                        });
                    }),
                Btn(
                    label: tr('删除', 'Жою'),
                    icon: Icons.delete_outline,
                    danger: true,
                    onPressed: () {
                      update(() => selectedSiteId = null);
                      action('DeleteSiteItem', {'siteItemId': i.id});
                    }),
              ]),
            ]);
    final house = houseOnPlot(doc, saved);
    final plotCard = InfoCard(
        title: tr('宅基地', 'Учаске'),
        trailing: IconButton(
            tooltip: tr('删除宅基地', 'Учаскені жою'),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                          content: Text(tr('删除宅基地和院子里的全部设施？可以撤销。',
                              'Учаске мен ауладағы барлық нысанды жою керек пе? Болдырмауға болады.')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(tr('取消', 'Болдырмау'))),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(tr('删除', 'Жою'))),
                          ]));
              if (ok == true) {
                update(() => selectedSiteId = null);
                action('ClearSite', {});
              }
            },
            icon: const Icon(Icons.delete_outline, size: 18)),
        children: [
          KvGrid([
            Kv('${m2dp(saved.width)} × ${m2dp(saved.depth)}', tr('宽 × 进深 (米)', 'Ені × тереңдігі (м)'),
                onTap: () async {
              final w = await length(tr('宅基地宽 (临街)', 'Учаске ені (көше жақ)'), saved.width);
              if (w == null || !mounted) return;
              final d = await length(tr('宅基地进深', 'Учаске тереңдігі'), saved.depth);
              if (d == null) return;
              action('SetSite', {'width': w, 'depth': d});
            }),
            Kv('${dec((saved.width * saved.depth / 1e6).toStringAsFixed(0))} $unitM2 · ${dec((saved.width * saved.depth / 1e6 / 666.7).toStringAsFixed(2))} ${tr('亩', 'му')}',
                tr('占地', 'Аудан')),
            Kv('${m2dp(house.left)}, ${m2dp(house.bottom)}', tr('房子离左边界、离街道 (米)', 'Үй сол шекарадан, көшеден (м)'),
                onTap: () async {
              final x = await length(tr('房子离左边界', 'Үй сол шекарадан'), saved.houseX);
              if (x == null || !mounted) return;
              final y = await length(tr('房子离街道', 'Үй көшеден'), saved.houseY);
              if (y == null) return;
              action('SetSite', {'houseX': x, 'houseY': y});
            }),
            Kv(
                '${dec((siteBuildings.fold(0.0, (s, k) => s + (siteAreas(saved)[k] ?? 0))).toStringAsFixed(1))} $unitM2',
                tr('附属建筑面积', 'Қосалқы құрылыс ауданы')),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('添加设施', 'Нысан қосу'),
                icon: Icons.add,
                primary: true,
                onPressed: addSiteItem),
            PillToggle(
                label: tr('院墙', 'Қоршау'),
                selected: saved.fence,
                onChanged: (v) => action('SetSite', {'fence': v})),
          ]),
        ]);
    final checkCard = InfoCard(
        title: '${tr('院子检查', 'Аула тексеруі')} · ${checks.length}',
        children: [
          if (checks.isEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('没有发现问题', 'Мәселе табылмады'),
                    style: TextStyle(color: t.muted))),
          for (final c in checks)
            InkWell(
                onTap: () {
                  update(() => siteHighlights = c.areas);
                  pulse
                    ..value = 0
                    ..repeat(reverse: true, count: 6);
                },
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 4,
                              height: 36,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                  color: levelColor(t, Level.values[c.level.index]),
                                  borderRadius: BorderRadius.circular(2))),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(tr(c.title.$1, c.title.$2),
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600)),
                                Text(tr(c.text.$1, c.text.$2),
                                    style: TextStyle(
                                        fontSize: 12, height: 1.45, color: t.muted)),
                              ])),
                        ]))),
          Note(tr('间距是乡村宅基地的常见建议 (厕所离房子 12 m、澡堂 8 m、水井离厕所和化粪池 20 m 等)，不代表当地审批要求。',
              'Арақашықтықтар — ауыл учаскесіне әдеттегі ұсыныс (дәретхана үйден 12 м, монша 8 м, құдық дәретхана мен септиктен 20 м т.б.), жергілікті рұқсат талабы емес.')),
        ]);
    final side = [
      if (selectedItem != null) itemCard(selectedItem),
      if (selectedSiteId == '@house')
        InfoCard(
            title: doc.meta.name,
            subtitle: tr('拖动房子可在宅基地上移动，或点位置输入。',
                'Үйді сүйреп жылжытыңыз немесе орнын басып енгізіңіз.'),
            children: const []),
      plotCard,
      checkCard,
    ];
    if (!wide)
      return page([
        canvas,
        Text(tr('点选房子或设施，拖动移动。', 'Үйді не нысанды таңдап, сүйреп жылжытыңыз.'),
            style: TextStyle(fontSize: 12, color: t.muted)),
        ...side
      ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
        canvas,
        const SizedBox(height: 8),
        Text(tr('点选房子或设施，拖动移动。', 'Үйді не нысанды таңдап, сүйреп жылжытыңыз.'),
            style: TextStyle(fontSize: 12, color: t.muted)),
      ])),
      SizedBox(
          width: 380,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final w in side) ...[w, const SizedBox(height: 12)]
          ])),
    ]);
  }
}
