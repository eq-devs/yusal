part of '../house_editor.dart';

class HouseHome extends StatefulWidget {
  const HouseHome(
      {super.key,
      this.store,
      this.onFindBuilders,
      this.onPublishPost,
      this.onBackup,
      this.reload,
      this.createRequest});
  final ProjectStore? store;

  /// Platform hooks: publish a demand from a design and back it up. The
  /// design tool works without them.
  final void Function(ProjectEntry entry)? onFindBuilders,
      onPublishPost,
      onBackup;

  /// Fires when designs were added from outside, e.g. restored backups.
  final Listenable? reload;

  /// Fires when another screen asks to start a new design (template picker).
  final Listenable? createRequest;
  @override
  State<HouseHome> createState() => _HouseHomeState();
}

/// Templates: key → (Chinese, Kazakh, size in metres).
const _templateNames = {
  'kz': ('哈萨克乡村住宅', 'Қазақ ауыл үйі', '10 × 13'),
  'three': ('一层三间', 'Бір қабат, үш бөлме', '12 × 10'),
  'five': ('一层五间', 'Бір қабат, бес бөлме', '15 × 10'),
  'two': ('两层住宅', 'Екі қабатты үй', '12 × 10'),
};

/// Common plot-friendly sizes (width × depth, metres) offered when a
/// design starts from its size.
const _sizePresets = [(8, 10), (10, 12), (12, 10), (10, 13), (15, 10)];

/// Room names of the village-house template in the current language.
Map<String, String> kazakhTemplateNames() => isKk
    ? const {
        'b1': 'Жатын бөлме 1',
        'b2': 'Жатын бөлме 2',
        'cor': 'Дәліз',
        'ent': 'Кіреберіс',
        'boil': 'Қазандық',
      }
    : const {
        'b1': '卧室 1',
        'b2': '卧室 2',
        'cor': '走廊',
        'ent': '门厅',
        'boil': '锅炉房',
      };

class _HouseHomeState extends State<HouseHome> {
  late final store =
      widget.store ?? ProjectStore(previewRenderer: renderProjectPreview);
  static const importChannel = MethodChannel('yusal/house_import');
  List<ProjectEntry> projects = [];
  String? error;

  /// The featured template, built once for its preview drawing.
  static HouseDocument? featured;
  static DerivedHouse? featuredDerived;

  @override
  void initState() {
    super.initState();
    widget.reload?.addListener(refresh);
    widget.createRequest?.addListener(_onCreateRequest);
    refresh().then((_) => reopenLast());
    if (!kIsWeb) {
      importChannel.setMethodCallHandler((call) async {
        if (call.method == 'importFile') await receiveFile(call.arguments);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final pending =
              await importChannel.invokeListMethod<Object?>('getPending');
          for (final file in pending ?? <Object?>[]) {
            await receiveFile(file);
          }
        } on MissingPluginException {
          /* Widget tests and unsupported desktop platforms. */
        }
      });
    }
  }

  @override
  void dispose() {
    widget.reload?.removeListener(refresh);
    widget.createRequest?.removeListener(_onCreateRequest);
    if (!kIsWeb) importChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)),
          snackBarAnimationStyle: Motion.toastStyle);
  }

  Future<void> receiveFile(Object? payload) async {
    if (!mounted || payload is! Map) return;
    if (payload['bytes'] is! Uint8List) {
      message(payload['error'] == 'FILE_TOO_LARGE'
          ? tr('文件超过 10 MiB，无法打开', 'Файл 10 MiB-тан үлкен, ашу мүмкін емес')
          : tr('无法读取设计文件', 'Жоба файлын оқу мүмкін емес'));
      return;
    }
    final loaded = loadHouse(payload['bytes'] as Uint8List);
    if (!loaded.isSuccess) {
      message(tr('这个文件的内容有误，无法打开', 'Файлдың мазмұны қате, ашу мүмкін емес'));
      return;
    }
    try {
      final id = await store.createProject(loaded.document!);
      if (mounted) await open(ProjectEntry(id, loaded.document!));
    } catch (_) {
      message(tr('无法保存导入的设计', 'Импортталған жобаны сақтау мүмкін емес'));
    }
  }

  /// After a reload or restart, go straight back to the design that was
  /// being edited.
  Future<void> reopenLast() async {
    final id = await LastOpenProject.read();
    if (id == null || !mounted) return;
    final entry = projects.where((p) => p.id == id).firstOrNull;
    if (entry == null) {
      await LastOpenProject.write(null);
      return;
    }
    await open(entry);
  }

  Future<void> refresh() async {
    try {
      final list = await store.listProjects();
      if (mounted)
        setState(() {
          projects = list;
          error = store.indexWarning == null
              ? null
              : tr3(
                  '设计已保留，项目索引暂时无法更新；可继续编辑或导出。',
                  'Жобалар сақталған, индекс жаңартылмады.',
                  'Проекты сохранены, индекс не обновлён. Можно редактировать или экспортировать.');
        });
    } catch (_) {
      if (mounted)
        setState(() => error = tr('暂时无法读取设计，请稍后重试',
            'Жобаларды оқу мүмкін болмады, кейін қайталаңыз'));
    }
  }

  void _onCreateRequest() {
    if (mounted) createFromTemplate();
  }

  Future<void> open(ProjectEntry entry) async {
    try {
      final document = await store.openProject(entry.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HouseEditor(
              entry: ProjectEntry(entry.id, document), store: store)));
      await refresh();
    } catch (_) {
      message(
          tr('这个设计无法打开，请检查文件', 'Жобаны ашу мүмкін емес, файлды тексеріңіз'));
    }
  }

  HouseDocument buildTemplate(String key) {
    final now = DateTime.now().toUtc().toIso8601String();
    if (key == 'kz')
      return createKazakhTemplate(now, () => const Uuid().v4(),
          name: tr('哈萨克乡村住宅', 'Қазақ ауыл үйі'), names: kazakhTemplateNames());
    return createTemplate(key, now, () => const Uuid().v4());
  }

  /// Template drawings for the start sheet, built once.
  static final _templatePreviews = <String, (HouseDocument, DerivedHouse)>{};

  Widget templatePreview(String key) {
    final t = Tokens.of(context);
    try {
      final (doc, derived) = _templatePreviews.putIfAbsent(key, () {
        final d = key == 'kz'
            ? createKazakhTemplate('2026-01-01T00:00:00Z',
                () => 'preview${_featuredIds++}',
                names: kazakhTemplateNames())
            : createTemplate(
                key, '2026-01-01T00:00:00Z', () => 'preview${_featuredIds++}');
        return (d, deriveHouse(d));
      });
      return CustomPaint(
          painter: FloorPlanPainter(derived.floors.first.base,
              {for (final r in doc.floors.first.rooms) r.id: ''}, const {},
              openings: derived.floors.first.openings,
              tokens: t,
              showDimensions: false,
              showLabels: false,
              viewportInsets: const EdgeInsets.all(6)));
    } catch (_) {
      return Icon(Icons.other_houses_outlined, color: t.muted);
    }
  }

  /// How to start: from a size, by sketching the outline, or from a
  /// template shown as its plan (Planner 5D, Floorplanner and 酷家乐 all
  /// open with this choice instead of a blank sheet or a bare list).
  Future<void> createFromTemplate([String? chosen]) async {
    final key = chosen ??
        await showMotionSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (context) {
              final t = Tokens.of(context);
              Widget way(String key, IconData icon, String title, String sub) =>
                  Material(
                      color: t.panel,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: t.line)),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(context, key),
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Icon(icon, color: t.accent),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(title,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      Text(sub,
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              color: t.muted)),
                                    ])),
                                Icon(Icons.chevron_right, color: t.muted),
                              ]))));
              Widget template(MapEntry<String, (String, String, String)> e) =>
                  Material(
                      color: t.panel,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: t.line)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                          onTap: () => Navigator.pop(context, e.key),
                          child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AspectRatio(
                                        aspectRatio: 1.25,
                                        child: templatePreview(e.key)),
                                    const SizedBox(height: 6),
                                    Text(tr(e.value.$1, e.value.$2),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text('${e.value.$3} $unitM',
                                        style: mono(size: 12, color: t.muted)),
                                  ]))));
              return SafeArea(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.88),
                      child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            Text(tr('怎么开始？', 'Қалай бастаймыз?'),
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                tr('都可以随时改：墙、房间、门窗都能拖动调整。',
                                    'Кейін бәрін өзгертуге болады.'),
                                style: TextStyle(color: t.muted)),
                            const SizedBox(height: 12),
                            way(
                                'blank',
                                Icons.crop_square,
                                tr('按长宽新建', 'Өлшеммен бастау'),
                                tr('输入面宽和进深，得到一个空房子',
                                    'Ені мен ұзындығын енгізіңіз')),
                            const SizedBox(height: 8),
                            way(
                                'sketch',
                                Icons.gesture,
                                tr('在画布上拖出外形', 'Пішінді сызып беру'),
                                tr('用手指拉出房子的大小',
                                    'Үйдің өлшемін саусақпен тартыңыз')),
                            const SizedBox(height: 16),
                            Text(tr('或者从模板改', 'Немесе үлгіден'),
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            LayoutBuilder(builder: (context, c) {
                              final columns =
                                  math.max(2, (c.maxWidth / 220).floor());
                              final w =
                                  (c.maxWidth - 10 * (columns - 1)) / columns;
                              return Wrap(spacing: 10, runSpacing: 10, children: [
                                for (final e in _templateNames.entries)
                                  SizedBox(width: w, child: template(e)),
                              ]);
                            }),
                          ])));
            });
    if (key == null) return;
    if (key == 'blank') return create();
    if (key == 'sketch') return create(sketch: true);
    try {
      final doc = buildTemplate(key);
      final id = await store.createProject(doc);
      if (mounted) await open(ProjectEntry(id, doc));
    } catch (_) {
      message(tr('无法创建，请检查存储空间', 'Жасау мүмкін емес, жадты тексеріңіз'));
    }
  }

  Future<void> create({bool sketch = false}) async {
    final name = TextEditingController(text: tr('我的房屋', 'Менің үйім')),
        width = TextEditingController(text: '12'),
        depth = TextEditingController(text: '10');
    const columns = 1, rows = 1;
    String? validation;
    var sketchRequested = sketch;
    double? parse(TextEditingController c) {
      final v = double.tryParse(c.text.replaceAll(',', '.'));
      return v == null || !v.isFinite ? null : v;
    }

    var doc = sketch
        ? null
        : await showDialog<HouseDocument>(
            context: context,
            builder: (context) => StatefulBuilder(builder: (context, setDialog) {
                  final t = Tokens.of(context);
                  final w = parse(width), d = parse(depth);
                  Widget size(TextEditingController c, String label) =>
                      TextField(
                          controller: c,
                          onChanged: (_) => setDialog(() => validation = null),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: label, suffixText: unitM));
                  return AlertDialog(
                      title: Text(tr('新建设计', 'Жаңа жоба')),
                      content: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            TextField(
                                controller: name,
                                decoration: InputDecoration(
                                    labelText: tr('设计名称', 'Жоба атауы'))),
                            const SizedBox(height: 12),
                            // Live outline: the numbers become a shape.
                            Center(
                                child: SizedBox(
                                    width: 150,
                                    height: 110,
                                    child: CustomPaint(
                                        painter: _SizePreviewPainter(
                                            w, d, t.accent, t.ink, t.muted)))),
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final (pw, pd) in _sizePresets)
                                ChoiceChip(
                                    label: Text('$pw×$pd'),
                                    visualDensity: VisualDensity.compact,
                                    selected: w == pw && d == pd,
                                    onSelected: (_) => setDialog(() {
                                          width.text = '$pw';
                                          depth.text = '$pd';
                                          validation = null;
                                        })),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: size(width,
                                      tr('面宽（左右）', 'Ені (солдан оңға)'))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: size(depth,
                                      tr('进深（上下）', 'Ұзындығы (жоғары-төмен)'))),
                            ]),
                            Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                    tr('进去后，从墙上的 ＋ 拖出隔墙。',
                                        'Ішке кірген соң қабырғадағы ＋ белгісінен ішкі қабырға тартыңыз.'),
                                    style: TextStyle(
                                        fontSize: 12.5, color: t.muted))),
                            if (validation != null)
                              Text(validation!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error))
                          ])),
                      actions: [
                        TextButton.icon(
                            onPressed: () {
                              sketchRequested = true;
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.gesture),
                            label: Text(tr('在画布上拖出外形', 'Пішінді сызып беру'))),
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr('取消', 'Болдырмау'))),
                        FilledButton(
                            onPressed: () {
                              final w = parse(width), d = parse(depth);
                              if (w == null ||
                                  d == null ||
                                  w < 3 ||
                                  w > 100 ||
                                  d < 3 ||
                                  d > 100 ||
                                  w * 1000 / columns < 300 ||
                                  d * 1000 / rows < 300) {
                                setDialog(() => validation = tr(
                                    '宽和长都要在 3 到 100 米之间',
                                    'Ені мен ұзындығы 3–100 м аралығында болуы керек'));
                                return;
                              }
                              Navigator.pop(
                                  context,
                                  createHouse(
                                      name: name.text,
                                      width: (w * 1000).round(),
                                      depth: (d * 1000).round(),
                                      columns: columns,
                                      rows: rows,
                                      initialRoom: true,
                                      timestamp: DateTime.now()
                                          .toUtc()
                                          .toIso8601String(),
                                      newId: () => const Uuid().v4()));
                            },
                            child: Text(tr('开始设计', 'Бастау')))
                      ]);
                }));
    // The controllers stay alive until the dialog exit animation completes.
    if (sketchRequested && mounted) {
      final dimensions = await Navigator.of(context).push<FootprintDimensions>(
          MaterialPageRoute(builder: (_) => const FootprintSketch()));
      if (dimensions == null) return;
      doc = createHouse(
          name: name.text,
          width: dimensions.width,
          depth: dimensions.depth,
          columns: 1,
          rows: 1,
          initialRoom: true,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          newId: () => const Uuid().v4());
    }
    if (doc == null) return;
    try {
      final id = await store.createProject(doc);
      if (mounted) await open(ProjectEntry(id, doc));
    } catch (_) {
      message(tr('无法创建，请检查存储空间', 'Жасау мүмкін емес, жадты тексеріңіз'));
    }
  }

  Future<void> import() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        XTypeGroup(
            label: tr('房屋设计', 'Үй жобасы'),
            extensions: const ['house'],
            uniformTypeIdentifiers: const ['public.data'])
      ]);
      if (file == null) return;
      if (await file.length() > maxHouseBytes) {
        message(
            tr('文件超过 10 MiB，无法打开', 'Файл 10 MiB-тан үлкен, ашу мүмкін емес'));
        return;
      }
      final loaded = await loadHouseStream(file.openRead(0, maxHouseBytes + 1),
          length: await file.length());
      if (!loaded.isSuccess) {
        message(tr('这个文件的内容有误，无法打开', 'Файлдың мазмұны қате, ашу мүмкін емес'));
        return;
      }
      final id = await store.createProject(loaded.document!);
      if (mounted) await open(ProjectEntry(id, loaded.document!));
    } catch (_) {
      message(tr('无法导入设计', 'Жобаны импорттау мүмкін емес'));
    }
  }

  Future<bool> confirmDelete(String title, String name) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(name), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr('取消', 'Болдырмау'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr('删除', 'Жою')))
              ])) ==
      true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final t = Tokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    // Inside the platform's "My houses" tab, language and theme live in
    // "Me"; the header only names the list and offers import.
    final embedded = widget.onFindBuilders != null;
    final header = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 16,
        runSpacing: 10,
        children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    embedded
                        ? tr('我的设计', 'Жобаларым')
                        : tr('自建房设计工具', 'Үй жобалау құралы'),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                if (!embedded)
                  Text(
                      tr('定长宽 · 拖出隔墙 · 放门窗 · 看 3D',
                          'өлшем · қабырға · есік-терезе · 3D'),
                      style: mono(size: 12, color: t.muted)),
              ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!embedded)
              Seg<AppLang>(
                  label: 'Тіл / 语言',
                  value: app.lang,
                  items: const [
                    (AppLang.kk, 'Қазақша'),
                    (AppLang.ru, 'Русский'),
                    (AppLang.zh, '中文')
                  ],
                  onChanged: app.setLang),
            if (!embedded)
              Seg<ThemeChoice>(
                  value: app.theme,
                  items: [
                    (ThemeChoice.auto, tr('◐ 自动', '◐ Авто')),
                    (ThemeChoice.day, tr('☀ 日间', '☀ Күндіз')),
                    (ThemeChoice.night, tr('☾ 夜间', '☾ Түн')),
                  ],
                  onChanged: app.setTheme),
            Btn(
                label: tr('导入', 'Импорт'),
                icon: Icons.file_open_outlined,
                tooltip: tr('导入 .house', '.house файлын ашу'),
                onPressed: import),
          ]),
        ]);
    final hero = Sheet(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('从长宽开始，设计你的家', 'Өлшемнен бастап, үйіңізді жобалаңыз'),
              style: TextStyle(
                  fontSize: width < 420 ? 22 : 28,
                  fontWeight: FontWeight.w700,
                  height: 1.25)),
          const SizedBox(height: 8),
          Text(
              tr('定长宽 · 拖出隔墙 · 放门窗与家具 · 看 3D 与室内漫游 · 构造与工程量',
                  'Өлшем · қабырға · есік-терезе мен жиһаз · 3D және ішкі серуен · құрылым мен көлем'),
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add),
                label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(tr('新建设计', 'Жаңа жоба')))),
            OutlinedButton.icon(
                onPressed: createFromTemplate,
                icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(tr('也可以从示例开始', 'Үлгіден бастау')))),
          ]),
        ]));
    return Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                        children: [
                          header,
                          const SizedBox(height: 16),
                          hero,
                          // Newcomers see the example first; returning users
                          // their own designs.
                          if (projects.isEmpty) ...[
                            const SizedBox(height: 12),
                            featuredCard(width),
                          ],
                          const SizedBox(height: 24),
                          Text(tr('最近设计', 'Соңғы жобалар'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          if (error != null)
                            Text(error!, style: TextStyle(color: t.crit)),
                          if (projects.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                    tr('还没有设计，创建你的第一栋房屋。',
                                        'Әзірге жоба жоқ, алғашқы үйіңізді жасаңыз.'),
                                    style: TextStyle(color: t.muted))),
                          for (final entry in store.corruptProjects.entries)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Sheet(
                                    child: ListTile(
                                        leading: Icon(Icons.error_outline,
                                            color: t.crit),
                                        title: Text(entry.key),
                                        subtitle: Text(entry.value),
                                        trailing: IconButton(
                                            tooltip: tr('删除损坏的设计',
                                                'Бүлінген жобаны жою'),
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            onPressed: () async {
                                              if (await confirmDelete(
                                                  tr('删除无法打开的设计？',
                                                      'Ашылмайтын жобаны жою керек пе?'),
                                                  entry.key)) {
                                                await store
                                                    .deleteProject(entry.key);
                                                await refresh();
                                              }
                                            })))),
                          LayoutBuilder(builder: (context, c) {
                            final columns =
                                math.max(1, (c.maxWidth / 280).floor());
                            final w =
                                (c.maxWidth - 12 * (columns - 1)) / columns;
                            return Wrap(spacing: 12, runSpacing: 12, children: [
                              for (final entry in projects)
                                SizedBox(width: w, child: projectCard(entry)),
                            ]);
                          }),
                          if (projects.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            featuredCard(width),
                          ],
                        ])))));
  }

  Widget projectCard(ProjectEntry entry) {
    final t = Tokens.of(context);
    final doc = entry.document;
    String m(int mm) => dec((mm / 1000).toString());
    return Sheet(
        child: InkWell(
            onTap: () => open(entry),
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          color: t.room,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: t.line)),
                      clipBehavior: Clip.antiAlias,
                      child: entry.preview == null
                          ? Icon(Icons.other_houses_outlined, color: t.muted)
                          : Image.memory(Uint8List.fromList(entry.preview!),
                              fit: BoxFit.contain)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(doc.meta.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                            '${m(doc.footprint.width)} × ${m(doc.footprint.depth)} $unitM · ${doc.floors.length} ${tr3('层', 'қабат', 'эт.')}\n${tr3('更新于', 'Жаңартылды', 'Обновлён')} ${doc.meta.updatedAt.split('T').first}',
                            style: mono(size: 12, color: t.muted)),
                      ])),
                  PopupMenuButton<String>(
                    tooltip:
                        tr3('项目操作', 'Жоба әрекеттері', 'Действия с проектом'),
                    onSelected: (action) async {
                      switch (action) {
                        case 'edit':
                          await open(entry);
                        case 'post':
                          widget.onPublishPost?.call(entry);
                        case 'builders':
                          widget.onFindBuilders?.call(entry);
                        case 'backup':
                          widget.onBackup?.call(entry);
                        case 'export':
                          final text = encodeHouse(doc);
                          final name = doc.meta.name
                              .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '')
                              .trim();
                          final filename =
                              '${name.isEmpty ? 'house' : name}.house';
                          final file = XFile.fromData(
                              Uint8List.fromList(utf8.encode(text)),
                              mimeType: 'application/json',
                              name: filename);
                          try {
                            if (kIsWeb) {
                              await file.saveTo(filename);
                            } else {
                              final box =
                                  context.findRenderObject() as RenderBox?;
                              await SharePlus.instance.share(ShareParams(
                                  files: [file],
                                  sharePositionOrigin: box == null
                                      ? null
                                      : box.localToGlobal(Offset.zero) &
                                          box.size));
                            }
                          } catch (_) {
                            message(tr3(
                                '导出失败，请重试',
                                'Экспорт сәтсіз, қайталаңыз',
                                'Не удалось экспортировать. Повторите.'));
                          }
                        case 'delete':
                          if (await confirmDelete(
                              tr3('删除这个设计？', 'Бұл жобаны жою керек пе?',
                                  'Удалить проект?'),
                              doc.meta.name)) {
                            try {
                              await store.deleteProject(entry.id);
                              await refresh();
                            } catch (_) {
                              message(tr3('删除失败，请重试', 'Жою сәтсіз',
                                  'Не удалось удалить'));
                            }
                          }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'edit',
                          child: Text(
                              tr3('编辑设计', 'Жобаны өңдеу', 'Редактировать'))),
                      if (widget.onPublishPost != null)
                        PopupMenuItem(
                            value: 'post',
                            child: Text(tr3('发布作品', 'Жобаны жариялау',
                                'Опубликовать проект'))),
                      if (widget.onFindBuilders != null)
                        PopupMenuItem(
                            value: 'builders',
                            child: Text(tr3(
                                '找施工方', 'Мердігер табу', 'Найти подрядчика'))),
                      PopupMenuItem(
                          value: 'export',
                          child: Text(tr3('导出设计文件', 'Жоба файлын экспорттау',
                              'Экспорт файла проекта'))),
                      if (widget.onBackup != null)
                        PopupMenuItem(
                            value: 'backup',
                            child: Text(tr3(
                                '备份', 'Сақтық көшірме', 'Резервная копия'))),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text(
                              tr3('删除设计', 'Жобаны жою', 'Удалить проект'))),
                    ],
                  ),
                ]))));
  }

  /// The drafting page's own house, ready to open and edit.
  Widget featuredCard(double width) {
    final t = Tokens.of(context);
    try {
      featured ??= createKazakhTemplate(
          '2026-01-01T00:00:00Z', () => 'featured${_featuredIds++}',
          names: kazakhTemplateNames());
      featuredDerived ??= deriveHouse(featured!);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final doc = featured!, derived = featuredDerived!;
    final narrow = width < 560;
    final preview = SizedBox(
        width: narrow ? double.infinity : 210,
        height: narrow ? 170 : 230,
        child: CustomPaint(
            painter: FloorPlanPainter(derived.floors.first.base,
                {for (final r in doc.floors.first.rooms) r.id: ''}, const {},
                openings: derived.floors.first.openings,
                tokens: t,
                furniture: doc.extras.furniture,
                showDimensions: false,
                showLabels: false,
                viewportInsets: const EdgeInsets.all(8))));
    final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TagPill(tr('示例', 'Үлгі'), t.accent),
          const SizedBox(height: 6),
          Text(tr('哈萨克乡村住宅 10×13', 'Қазақ ауыл үйі 10×13'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              tr('一层 · 外墙 400 mm · 平屋顶 · 8 个房间。已布置地毯、挂毯、矮圆桌、木箱和褥垫，带条形基础、预留套管和构造做法。打开后每一处都可以修改。',
                  'Бір қабат · сыртқы қабырға 400 мм · тегіс шатыр · 8 бөлме. Кілем, тұскиіз, дөңгелек үстел, сандық пен көрпеше қойылған; таспалы іргетас, гильзалар мен құрылым шешімдері бар. Ашқан соң бәрін өзгертуге болады.'),
              style: TextStyle(color: t.muted, height: 1.5)),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () => createFromTemplate('kz'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(tr('打开这个示例', 'Үлгіні ашу'))),
        ]);
    return Sheet(
        padding: const EdgeInsets.all(14),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [preview, const SizedBox(height: 12), text])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                preview,
                const SizedBox(width: 18),
                Expanded(child: text),
              ]));
  }
}

var _featuredIds = 0;

/// The house outline at scale with its two sizes and the floor area.
class _SizePreviewPainter extends CustomPainter {
  const _SizePreviewPainter(this.w, this.d, this.accent, this.ink, this.muted);
  final double? w, d;
  final Color accent, ink, muted;

  @override
  void paint(Canvas canvas, Size size) {
    final w = this.w, d = this.d;
    if (w == null || d == null || w <= 0 || d <= 0) return;
    const pad = 22.0;
    final k = math.min((size.width - pad * 2) / w, (size.height - pad * 2) / d);
    final rect = Rect.fromCenter(
        center: size.center(Offset.zero) + const Offset(6, -4),
        width: w * k,
        height: d * k);
    canvas.drawRect(rect, Paint()..color = accent.withValues(alpha: 0.12));
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ink);
    void label(String text, Offset at, {bool vertical = false, double size = 11}) {
      final tp = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(fontSize: size, color: vertical || size < 12 ? muted : ink)),
          textDirection: TextDirection.ltr)
        ..layout();
      canvas.save();
      canvas.translate(at.dx, at.dy);
      if (vertical) canvas.rotate(-math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    String m(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    label('${m(w)} m', Offset(rect.center.dx, rect.top - 9));
    label('${m(d)} m', Offset(rect.left - 10, rect.center.dy), vertical: true);
    label('${(w * d).toStringAsFixed(0)} m²', rect.center, size: 13);
  }

  @override
  bool shouldRepaint(covariant _SizePreviewPainter old) =>
      old.w != w || old.d != d || old.accent != accent;
}
