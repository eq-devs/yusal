part of '../page.dart';

/// What a page that draws its own list of designs needs from [HouseHome]:
/// the designs and everything that can be done with them. [HouseHome]
/// keeps the logic (storage, import, templates, export) in one place.
abstract interface class DesignList {
  /// False until the first read of the store has finished.
  bool get loaded;
  List<ProjectEntry> get projects;

  /// Files that could not be read: id → reason.
  Map<String, String> get corruptProjects;
  String? get error;

  /// Starts a design from its size (or, with [sketch], by drawing it).
  Future<void> create({bool sketch = false});

  /// Opens the "how to start" sheet, or starts from template [key].
  Future<void> createFromTemplate([String? key]);
  Future<void> import();
  Future<void> open(ProjectEntry entry);

  /// [anchor] is where the share sheet points on a tablet.
  Future<void> export(ProjectEntry entry, BuildContext anchor);
  Future<void> delete(ProjectEntry entry);
  Future<void> deleteCorrupt(String id);

  /// The example house's plan, for an empty state or a template row,
  /// drawn with the palette found at [context].
  Widget examplePreview(BuildContext context);
}

class HouseHome extends ConsumerStatefulWidget {
  const HouseHome(
      {super.key,
      this.store,
      this.onFindBuilders,
      this.onPublishPost,
      this.onBackup,
      this.reload,
      this.createRequest,
      this.builder});
  final ProjectStore? store;

  /// Draws the list instead of the drafting-table page; the platform's
  /// "My houses" tab uses it to show the designs in its own look.
  final Widget Function(BuildContext context, DesignList list)? builder;

  /// Platform hooks: publish a demand from a design and back it up. The
  /// design tool works without them.
  final void Function(ProjectEntry entry)? onFindBuilders;
  final void Function(ProjectEntry entry)? onPublishPost;
  final void Function(ProjectEntry entry)? onBackup;

  /// Fires when designs were added from outside, e.g. restored backups.
  final Listenable? reload;

  /// Fires when another screen asks to start a new design (template picker).
  final Listenable? createRequest;
  @override
  ConsumerState<HouseHome> createState() => _HouseHomeState();
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
Map<String, String> kazakhTemplateNames() => isKy
    ? const {
        'b1': 'Уктоочу бөлмө 1',
        'b2': 'Уктоочу бөлмө 2',
        'cor': 'Коридор',
        'ent': 'Кире бериш',
        'boil': 'Казандык',
      }
    : isUz
    ? const {
        'b1': 'Yotoqxona 1',
        'b2': 'Yotoqxona 2',
        'cor': 'Koridor',
        'ent': 'Dahliz',
        'boil': 'Qozonxona',
      }
    : isEn
    ? const {
        'b1': 'Bedroom 1',
        'b2': 'Bedroom 2',
        'cor': 'Corridor',
        'ent': 'Hallway',
        'boil': 'Boiler room',
      }
    : isRu
    ? const {
        'b1': 'Спальня 1',
        'b2': 'Спальня 2',
        'cor': 'Коридор',
        'ent': 'Прихожая',
        'boil': 'Котельная',
      }
    : appLang == AppLang.kk
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

class _HouseHomeState extends ConsumerState<HouseHome>
    implements DesignList, HouseLibrary {
  late final store =
      widget.store ?? ProjectStore(previewRenderer: renderProjectPreview);
  static const importChannel = MethodChannel('yusal/house_import');
  @override
  List<ProjectEntry> projects = [];
  @override
  String? error;
  @override
  bool loaded = false;
  @override
  Map<String, String> get corruptProjects => store.corruptProjects;

  /// The featured template, built once for its preview drawing.
  static HouseDocument? featured;
  static DerivedHouse? featuredDerived;

  @override
  void initState() {
    super.initState();
    HouseLibrary.instance = this;
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
    if (identical(HouseLibrary.instance, this)) HouseLibrary.instance = null;
    widget.reload?.removeListener(refresh);
    widget.createRequest?.removeListener(_onCreateRequest);
    if (!kIsWeb) importChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)),
          snackBarAnimationStyle: Motion.toastStyle);
    }
  }

  Future<void> receiveFile(Object? payload) async {
    if (!mounted || payload is! Map) return;
    if (payload['bytes'] is! Uint8List) {
      message(payload['error'] == 'FILE_TOO_LARGE'
          ? tr3('文件超过 10 MiB，无法打开', 'Файл 10 MiB-тан үлкен, ашу мүмкін емес',
              'Файл больше 10 МиБ, открыть нельзя',
              "The file is over 10 MiB and can't be opened", ky: 'Файл 10 MiB ашык, аны ачуу мүмкүн эмес', uz: 'Fayl 10 MiB dan katta, uni ochib boʻlmaydi')
          : tr3('无法读取设计文件', 'Жоба файлын оқу мүмкін емес',
              'Не удалось прочитать файл проекта',
              "Couldn't read the design file", ky: 'Долбоор файлын окуу мүмкүн болбоду', uz: 'Loyiha faylini oʻqib boʻlmadi'));
      return;
    }
    final loaded = loadHouse(payload['bytes'] as Uint8List);
    if (!loaded.isSuccess) {
      message(tr3('这个文件的内容有误，无法打开', 'Файлдың мазмұны қате, ашу мүмкін емес',
          'Файл повреждён, открыть нельзя',
          "The file is damaged and can't be opened", ky: 'Файл бузулган, аны ачуу мүмкүн эмес', uz: 'Fayl buzilgan, uni ochib boʻlmaydi'));
      return;
    }
    try {
      final id = await store.createProject(loaded.document!);
      if (mounted) await open(ProjectEntry(id, loaded.document!));
    } catch (_) {
      message(tr3('无法保存导入的设计', 'Импортталған жобаны сақтау мүмкін емес',
          'Не удалось сохранить импортированный проект',
          "Couldn't save the imported design", ky: 'Импорттолгон долбоорду сактоо мүмкүн болбоду', uz: 'Import qilingan loyihani saqlab boʻlmadi'));
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
      if (mounted) {
        setState(() {
          loaded = true;
          projects = list;
          error = store.indexWarning == null
              ? null
              : tr3(
                  '设计已保留，项目索引暂时无法更新；可继续编辑或导出。',
                  'Жобалар сақталған, индекс жаңартылмады.',
                  'Проекты сохранены, индекс не обновлён. Можно редактировать или экспортировать.',
                  'Designs saved, index not updated. You can edit or export them.', ky: 'Долбоорлор сакталды, индекс жаңыланган жок. Аларды түзөтүп же экспорттосоңуз болот.', uz: 'Loyihalar saqlandi, indeks yangilanmadi. Ularni tahrirlash yoki eksport qilish mumkin.');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          error = tr3(
              '暂时无法读取设计，请稍后重试',
              'Жобаларды оқу мүмкін болмады, кейін қайталаңыз',
              'Не удалось прочитать проекты, попробуйте позже',
              "Couldn't read the designs; try again later", ky: 'Долбоорлорду окуу мүмкүн болбоду; кийинчерээк кайталаңыз', uz: 'Loyihalarni oʻqib boʻlmadi; keyinroq qayta urining');
        });
      }
    }
  }

  /// "＋ → 从零画" opens the size dialog straight away: one step to a
  /// house, not two choosers in a row.
  void _onCreateRequest() {
    if (mounted) create();
  }

  @override
  Future<void> open(ProjectEntry entry) async {
    try {
      final document = await store.openProject(entry.id);
      if (!mounted) return;
      // From a touched card the editor grows out of that card.
      await Navigator.of(context).push(ZoomPageRoute<void>(
          builder: (_) => HouseEditor(
              entry: ProjectEntry(entry.id, document), store: store)));
      await refresh();
    } catch (_) {
      message(tr3('这个设计无法打开，请检查文件', 'Жобаны ашу мүмкін емес, файлды тексеріңіз',
          'Не удалось открыть проект, проверьте файл',
          "Couldn't open the design; check the file", ky: 'Долбоорду ачуу мүмкүн болбоду; файлды текшериңиз', uz: 'Loyihani ochib boʻlmadi; faylni tekshiring'));
    }
  }

  @override
  List<({String id, String name})> get designs =>
      [for (final p in projects) (id: p.id, name: p.document.meta.name)];

  /// Closes an open editor, saving it first, so a design opened by voice
  /// is not stacked on top of another.
  Future<void> _closeEditor() async {
    for (final s in VoiceScreens.mounted.toList()) {
      if (s is DesignHost) await (s as DesignHost).saveNow();
    }
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    await refresh();
  }

  @override
  Future<void> openDesign(String id) async {
    await _closeEditor();
    final entry = projects.where((p) => p.id == id).firstOrNull;
    // Not awaited: it completes when the editor closes.
    if (entry != null && mounted) open(entry);
  }

  @override
  Future<void> addDesign(HouseDocument doc) async {
    await _closeEditor();
    final id = await store.createProject(doc);
    if (mounted) open(ProjectEntry(id, doc));
  }

  @override
  HouseDocument newDesign(String template,
      {String? name, int? width, int? depth}) {
    var doc = template == 'blank'
        ? withRoof(
            createHouse(
                name: tr3('我的房屋', 'Менің үйім', 'Мой дом', 'My house', ky: 'Менин үйүм', uz: 'Mening uyim'),
                width: width ?? 12000,
                depth: depth ?? 10000,
                columns: 1,
                rows: 1,
                initialRoom: true,
                timestamp: DateTime.now().toUtc().toIso8601String(),
                newId: () => const Uuid().v4()),
            'gable')
        : buildTemplate(template);
    if (name != null && name.trim().isNotEmpty) {
      doc = composeDocument(
          Meta(
              name: name.trim(),
              createdAt: doc.meta.createdAt,
              updatedAt: doc.meta.updatedAt),
          extractDesignState(doc));
    }
    return doc;
  }

  HouseDocument buildTemplate(String key) {
    final now = DateTime.now().toUtc().toIso8601String();
    if (key == 'kz') {
      return createKazakhTemplate(now, () => const Uuid().v4(),
          name: tr3('哈萨克乡村住宅', 'Қазақ ауыл үйі', 'Казахский сельский дом', 'Kazakh village house', ky: 'Казак айылындагы үй', uz: 'Qozoq qishlogʻidagi uy'),
          names: kazakhTemplateNames());
    }
    return createTemplate(key, now, () => const Uuid().v4());
  }

  /// Template drawings for the start sheet, built once.
  static final _templatePreviews = <String, (HouseDocument, DerivedHouse)>{};

  Widget templatePreview(String key) {
    final t = Tokens.of(context);
    try {
      final (doc, derived) = _templatePreviews.putIfAbsent(key, () {
        final d = key == 'kz'
            ? createKazakhTemplate(
                '2026-01-01T00:00:00Z', () => 'preview${_featuredIds++}',
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
      return Icon(YIcons.home, color: t.muted);
    }
  }

  /// How to start: from a size, by sketching the outline, or from a
  /// template shown as its plan (Planner 5D, Floorplanner and 酷家乐 all
  /// open with this choice instead of a blank sheet or a bare list).
  @override
  Future<void> createFromTemplate([String? chosen]) async {
    final picked = chosen ??
        await showMotionSheet<Object>(
            context: context,
            isScrollControlled: true,
            builder: (context) => _StartSheet(ways: (context, toSize) {
              final t = Tokens.of(context);
              Widget way(String key, IconData icon, String title, String sub) =>
                  Material(
                      color: t.panel,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: t.line)),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          // The size form is the next page of this sheet.
                          onTap: () => key == 'blank'
                              ? toSize()
                              : Navigator.pop(context, key),
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Icon(icon, color: t.ink),
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
                                              fontSize: 12.5, color: t.muted)),
                                    ])),
                                Icon(YIcons.chevronRight, color: t.muted),
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
              return ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            Text(
                                tr3('怎么开始？', 'Қалай бастаймыз?',
                                    'С чего начнём?',
                                    'Where shall we start?', ky: 'Эмнеден баштайбыз?', uz: 'Nimadan boshlaymiz?'),
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                tr3(
                                    '都可以随时改：墙、房间、门窗都能拖动调整。',
                                    'Кейін бәрін өзгертуге болады.',
                                    'Потом всё можно изменить: стены, комнаты, окна и двери двигаются.',
                                    'You can change everything later: walls, rooms, windows and doors all move.', ky: 'Кийин баарын өзгөртсөңүз болот: дубалдар, бөлмөлөр, терезе-эшиктер баары жылат.', uz: 'Keyin hammasini oʻzgartirishingiz mumkin: devorlar, xonalar, deraza va eshiklar hammasi suriladi.'),
                                style: TextStyle(color: t.muted)),
                            const SizedBox(height: 12),
                            // The questions come first: most people know how
                            // many rooms they want before any size of wall.
                            way(
                                'wizard',
                                YIcons.ai,
                                tr3(
                                    '回答几个问题，帮我出一套',
                                    'Сұрақтарға жауап беріп, жоба алу',
                                    'Ответить на вопросы и получить проект',
                                    'Answer questions and get a design', ky: 'Суроолорго жооп берип, долбоор алыңыз', uz: 'Savollarga javob bering va loyiha oling'),
                                VoiceSession.current != null
                                    ? tr3(
                                        '选好大小、层数和房间，助手画出第一版',
                                        'Өлшемін, қабатын, бөлмелерін таңдаңыз — көмекші сызады',
                                        'Выберите размер, этажи и комнаты — помощник начертит',
                                        'Choose the size, floors and rooms and the assistant draws it', ky: 'Өлчөмдү, кабаттарды жана бөлмөлөрдү тандаңыз, жардамчы чийип берет', uz: 'Oʻlcham, qavatlar va xonalarni tanlang, yordamchi chizib beradi')
                                    : tr3(
                                        '选好大小、层数和房间，马上画出第一版',
                                        'Өлшемін, қабатын, бөлмелерін таңдаңыз — бірден сызылады',
                                        'Выберите размер, этажи и комнаты — сразу начертим',
                                        'Choose the size, floors and rooms and we draw it right away', ky: 'Өлчөмдү, кабаттарды жана бөлмөлөрдү тандаңыз, биз дароо чийип беребиз', uz: 'Oʻlcham, qavatlar va xonalarni tanlang, darhol chizib beramiz')),
                            const SizedBox(height: 8),
                            way(
                                'blank',
                                YIcons.room,
                                tr3('按长宽新建', 'Өлшеммен бастау',
                                    'Начать с размеров',
                                    'Start from dimensions', ky: 'Өлчөмдөрдөн баштоо', uz: 'Oʻlchamlardan boshlash'),
                                tr3(
                                    '输入面宽和进深，得到一个空房子',
                                    'Ені мен ұзындығын енгізіңіз',
                                    'Введите ширину и длину — получите пустой дом',
                                    'Enter the width and length to get an empty house', ky: 'Бош үй алуу үчүн туурасын жана узундугун киргизиңиз', uz: 'Boʻsh uy olish uchun eni va uzunligini kiriting')),
                            const SizedBox(height: 8),
                            way(
                                'sketch',
                                Icons.gesture,
                                tr3('在画布上拖出外形', 'Пішінді сызып беру',
                                    'Нарисовать контур',
                                    'Draw the outline', ky: 'Контурду чийүү', uz: 'Konturni chizish'),
                                tr3(
                                    '用手指拉出房子的大小',
                                    'Үйдің өлшемін саусақпен тартыңыз',
                                    'Растяните размер дома пальцем',
                                    'Stretch the house size with your finger', ky: 'Үйдүн өлчөмүн манжаңыз менен созуңуз', uz: 'Uy oʻlchamini barmogʻingiz bilan choʻzing')),
                            const SizedBox(height: 16),
                            Text(
                                tr3('或者从模板改', 'Немесе үлгіден',
                                    'Или с шаблона',
                                    'Or from a template', ky: 'Же үлгүдөн', uz: 'Yoki namunadan'),
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            LayoutBuilder(builder: (context, c) {
                              final columns =
                                  math.max(2, (c.maxWidth / 220).floor());
                              final w =
                                  (c.maxWidth - 10 * (columns - 1)) / columns;
                              return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final e in _templateNames.entries)
                                      SizedBox(width: w, child: template(e)),
                                  ]);
                            }),
                          ]);
            }));
    if (picked == null || !mounted) return;
    if (picked is _NewDesign) return _createFrom(picked);
    final key = picked as String;
    if (key == 'blank') return create();
    if (key == 'sketch') return create(sketch: true);
    if (key == 'wizard') {
      final assistant = VoiceSession.current;
      final wish = await showHouseWizard(context, draft: assistant == null);
      if (wish == null) return;
      if (assistant != null) {
        assistant.say(wish.sentence(), spoken: false);
        return;
      }
      // No assistant: the first version is drawn here, at once.
      final plans = housePlans(wish.brief,
          name: tr3('我的房屋', 'Менің үйім', 'Мой дом', 'My house', ky: 'Менин үйүм', uz: 'Mening uyim'),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          newId: () => const Uuid().v4(),
          names: wishRoomNames());
      if (plans.isEmpty) {
        message(tr3(
            '这套要求画不出来，换个大小或少几间试试',
            'Бұл талаппен сызу мүмкін болмады, өлшемін не бөлме санын өзгертіп көріңіз',
            'По этим пожеланиям начертить не удалось, измените размер или число комнат',
            "Couldn't draw with these wishes; change the size or the number of rooms", ky: 'Бул каалоолор менен чийүү мүмкүн болбоду; өлчөмдү же бөлмөлөрдүн санын өзгөртүңүз', uz: 'Bu istaklar bilan chizib boʻlmadi; oʻlcham yoki xonalar sonini oʻzgartiring'));
        return;
      }
      if (!mounted) return;
      // Several ways to lay it out: the user picks.
      final plan = plans.length == 1
          ? plans.single
          : await showHousePlans(context, plans);
      if (plan == null) return;
      final doc = plan.document;
      try {
        final id = await store.createProject(doc);
        if (mounted) await open(ProjectEntry(id, doc));
      } catch (_) {
        message(tr3('无法创建，请检查存储空间', 'Жасау мүмкін емес, жадты тексеріңіз',
            'Не удалось создать, проверьте свободное место',
            "Couldn't create it; check free storage", ky: 'Түзүү мүмкүн болбоду; бош эстутумду текшериңиз', uz: 'Yaratib boʻlmadi; boʻsh xotirani tekshiring'));
      }
      return;
    }
    try {
      final doc = buildTemplate(key);
      final id = await store.createProject(doc);
      if (mounted) await open(ProjectEntry(id, doc));
    } catch (_) {
      message(tr3('无法创建，请检查存储空间', 'Жасау мүмкін емес, жадты тексеріңіз',
          'Не удалось создать, проверьте свободное место',
          "Couldn't create it; check free storage", ky: 'Түзүү мүмкүн болбоду; бош эстутумду текшериңиз', uz: 'Yaratib boʻlmadi; boʻsh xotirani tekshiring'));
    }
  }

  @override
  Future<void> create({bool sketch = false}) async {
    final design = sketch
        ? (
            name: _defaultHouseName(),
            width: 0,
            depth: 0,
            roof: 'gable',
            sketch: true
          )
        : await showMotionSheet<_NewDesign>(
            context: context,
            isScrollControlled: true,
            builder: (context) => const _StartSheet());
    if (design == null || !mounted) return;
    return _createFrom(design);
  }

  /// Makes the house the size form asked for, or lets it be sketched first,
  /// and opens it.
  Future<void> _createFrom(_NewDesign design) async {
    var width = design.width;
    var depth = design.depth;
    if (design.sketch) {
      final dimensions = await Navigator.of(context).push<FootprintDimensions>(
          MaterialPageRoute(builder: (_) => const FootprintSketch()));
      if (dimensions == null) return;
      width = dimensions.width;
      depth = dimensions.depth;
    }
    final doc = withRoof(
        createHouse(
            name: design.name,
            width: width,
            depth: depth,
            columns: 1,
            rows: 1,
            initialRoom: true,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            newId: () => const Uuid().v4()),
        design.roof);
    try {
      final id = await store.createProject(doc);
      if (mounted) await open(ProjectEntry(id, doc));
    } catch (_) {
      message(tr3('无法创建，请检查存储空间', 'Жасау мүмкін емес, жадты тексеріңіз',
          'Не удалось создать, проверьте свободное место',
          "Couldn't create it; check free storage", ky: 'Түзүү мүмкүн болбоду; бош эстутумду текшериңиз', uz: 'Yaratib boʻlmadi; boʻsh xotirani tekshiring'));
    }
  }

  @override
  Future<void> import() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        XTypeGroup(
            label: tr3('房屋设计', 'Үй жобасы', 'Проект дома', 'House design', ky: 'Үй долбоору', uz: 'Uy loyihasi'),
            extensions: const ['house'],
            uniformTypeIdentifiers: const ['public.data'])
      ]);
      if (file == null) return;
      if (await file.length() > maxHouseBytes) {
        message(tr3(
            '文件超过 10 MiB，无法打开',
            'Файл 10 MiB-тан үлкен, ашу мүмкін емес',
            'Файл больше 10 МиБ, открыть нельзя',
            "The file is over 10 MiB and can't be opened", ky: 'Файл 10 MiB ашык, аны ачуу мүмкүн эмес', uz: 'Fayl 10 MiB dan katta, uni ochib boʻlmaydi'));
        return;
      }
      final loaded = await loadHouseStream(file.openRead(0, maxHouseBytes + 1),
          length: await file.length());
      if (!loaded.isSuccess) {
        message(tr3('这个文件的内容有误，无法打开', 'Файлдың мазмұны қате, ашу мүмкін емес',
            'Файл повреждён, открыть нельзя',
            "The file is damaged and can't be opened", ky: 'Файл бузулган, аны ачуу мүмкүн эмес', uz: 'Fayl buzilgan, uni ochib boʻlmaydi'));
        return;
      }
      final id = await store.createProject(loaded.document!);
      if (mounted) await open(ProjectEntry(id, loaded.document!));
    } catch (_) {
      message(tr3('无法导入设计', 'Жобаны импорттау мүмкін емес',
          'Не удалось импортировать проект',
          "Couldn't import the design", ky: 'Долбоорду импорттоо мүмкүн болбоду', uz: 'Loyihani import qilib boʻlmadi'));
    }
  }

  Future<bool> confirmDelete(String title, String name) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(name), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr3('删除', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish')))
              ])) ==
      true;

  @override
  Future<void> export(ProjectEntry entry, BuildContext anchor) async {
    final doc = entry.document;
    final text = encodeHouse(doc);
    final name =
        doc.meta.name.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '').trim();
    final filename = '${name.isEmpty ? 'house' : name}.house';
    final file = XFile.fromData(Uint8List.fromList(utf8.encode(text)),
        mimeType: 'application/json', name: filename);
    try {
      if (kIsWeb) {
        await file.saveTo(filename);
      } else {
        final box = anchor.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
            files: [file],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size));
      }
    } catch (_) {
      message(tr3('导出失败，请重试', 'Экспорт сәтсіз, қайталаңыз',
          'Не удалось экспортировать. Повторите.',
          "Couldn't export. Try again.", ky: 'Экспорттоо мүмкүн болбоду. Кайра аракет кылыңыз.', uz: 'Eksport qilib boʻlmadi. Qayta urining.'));
    }
  }

  @override
  Future<void> delete(ProjectEntry entry) async {
    if (!await confirmDelete(
        tr3('删除这个设计？', 'Бұл жобаны жою керек пе?', 'Удалить проект?', 'Delete the design?', ky: 'Долбоорду өчүрөсүзбү?', uz: 'Loyiha oʻchirilsinmi?'),
        entry.document.meta.name)) {
      return;
    }
    try {
      await store.deleteProject(entry.id);
      await refresh();
    } catch (_) {
      message(tr3('删除失败，请重试', 'Жою сәтсіз', 'Не удалось удалить', "Couldn't delete", ky: 'Өчүрүү мүмкүн болбоду', uz: 'Oʻchirib boʻlmadi'));
    }
  }

  @override
  Future<void> deleteCorrupt(String id) async {
    if (!await confirmDelete(
        tr3('删除无法打开的设计？', 'Ашылмайтын жобаны жою керек пе?',
            'Удалить проект, который не открывается?',
            "Delete the design that won't open?", ky: 'Ачылбаган долбоорду өчүрөсүзбү?', uz: 'Ochilmaydigan loyiha oʻchirilsinmi?'),
        id)) {
      return;
    }
    await store.deleteProject(id);
    await refresh();
  }

  @override
  Widget examplePreview(BuildContext context) {
    final t = Tokens.of(context);
    try {
      featured ??= createKazakhTemplate(
          '2026-01-01T00:00:00Z', () => 'featured${_featuredIds++}',
          names: kazakhTemplateNames());
      featuredDerived ??= deriveHouse(featured!);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final doc = featured!;
    final derived = featuredDerived!;
    return CustomPaint(
        painter: FloorPlanPainter(derived.floors.first.base,
            {for (final r in doc.floors.first.rooms) r.id: ''}, const {},
            openings: derived.floors.first.openings,
            tokens: t,
            furniture: doc.extras.furniture,
            showDimensions: false,
            showLabels: false,
            viewportInsets: const EdgeInsets.all(8)));
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(settingsProvider);
    final choose = ref.read(settingsProvider.notifier);
    if (widget.builder != null) return widget.builder!(context, this);
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
                        ? tr3('我的设计', 'Жобаларым', 'Мои проекты', 'My designs', ky: 'Менин долбоорлорум', uz: 'Mening loyihalarim')
                        : tr3('自建房设计工具', 'Үй жобалау құралы',
                            'Проектирование дома',
                            'House design', ky: 'Үй долбоору', uz: 'Uy loyihasi'),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                if (!embedded)
                  Text(
                      tr3(
                          '定长宽 · 拖出隔墙 · 放门窗 · 看 3D',
                          'өлшем · қабырға · есік-терезе · 3D',
                          'размеры · стены · окна и двери · 3D',
                          'dimensions · walls · windows and doors · 3D', ky: 'өлчөмдөр · дубалдар · терезе-эшиктер · 3D', uz: 'oʻlchamlar · devorlar · deraza va eshiklar · 3D'),
                      style: mono(size: 12, color: t.muted)),
              ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!embedded)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Seg<AppLang>(
                  label: 'Тіл / 语言 / Language',
                  value: app.lang,
                  items: languageNames,
                  onChanged: choose.setLang)),
            if (!embedded)
              Seg<ThemeChoice>(
                  value: app.theme,
                  items: [
                    (ThemeChoice.auto, tr3('◐ 自动', '◐ Авто', '◐ Авто', '◐ Auto', ky: '◐ Авто', uz: '◐ Avto')),
                    (ThemeChoice.day, tr3('☀ 日间', '☀ Күндіз', '☀ День', '☀ Day', ky: '☀ Күндүз', uz: '☀ Kunduzi')),
                    (ThemeChoice.night, tr3('☾ 夜间', '☾ Түн', '☾ Ночь', '☾ Night', ky: '☾ Түн', uz: '☾ Tun')),
                  ],
                  onChanged: choose.setTheme),
            Btn(
                label: tr3('导入', 'Импорт', 'Импорт', 'Import', ky: 'Импорт', uz: 'Import'),
                icon: YIcons.doc,
                tooltip: tr3(
                    '导入 .house', '.house файлын ашу', 'Открыть файл .house', 'Open a .house file', ky: '.house файлын ачуу', uz: '.house faylini ochish'),
                onPressed: import),
          ]),
        ]);
    final hero = Sheet(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              tr3('从长宽开始，设计你的家', 'Өлшемнен бастап, үйіңізді жобалаңыз',
                  'Начните с размеров и спроектируйте свой дом',
                  'Start with dimensions and design your house', ky: 'Өлчөмдөрдөн баштап, үйүңүздү долбоорлоңуз', uz: 'Oʻlchamlardan boshlab uyingizni loyihalang'),
              style: TextStyle(
                  fontSize: width < 420 ? 22 : 28,
                  fontWeight: FontWeight.w700,
                  height: 1.25)),
          const SizedBox(height: 8),
          Text(
              tr3(
                  '定长宽 · 拖出隔墙 · 放门窗与家具 · 看 3D 与室内漫游 · 构造与工程量',
                  'Өлшем · қабырға · есік-терезе мен жиһаз · 3D және ішкі серуен · құрылым мен көлем',
                  'Размеры · стены · окна, двери и мебель · 3D и прогулка внутри · конструкции и объёмы',
                  'Dimensions · walls · windows, doors and furniture · 3D and walk-through · structure and quantities', ky: 'Өлчөмдөр · дубалдар · терезе, эшик жана эмерек · 3D жана кыдыруу · конструкция жана көлөмдөр', uz: 'Oʻlchamlar · devorlar · deraza, eshik va mebel · 3D va aylanish · konstruksiya va miqdorlar'),
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            // A new design starts from the choice of how: a few questions,
            // a size, a sketch or a template.
            FilledButton.icon(
                onPressed: createFromTemplate,
                icon: const Icon(YIcons.add),
                label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(tr3('新建设计', 'Жаңа жоба', 'Новый проект', 'New design', ky: 'Жаңы долбоор', uz: 'Yangi loyiha')))),
            OutlinedButton.icon(
                onPressed: createFromTemplate,
                icon: const Icon(YIcons.grid),
                label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(tr3(
                        '也可以从示例开始', 'Үлгіден бастау', 'Начать с примера', 'Start from an example', ky: 'Мисалдан баштоо', uz: 'Namunadan boshlash')))),
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
                          Text(tr3('最近设计', 'Соңғы жобалар', 'Недавние проекты', 'Recent designs', ky: 'Акыркы долбоорлор', uz: 'Soʻnggi loyihalar'),
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
                                    tr3(
                                        '还没有设计，创建你的第一栋房屋。',
                                        'Әзірге жоба жоқ, алғашқы үйіңізді жасаңыз.',
                                        'Проектов пока нет. Создайте свой первый дом.',
                                        'No designs yet. Create your first house.', ky: 'Азырынча долбоор жок. Биринчи үйүңүздү түзүңүз.', uz: 'Hozircha loyiha yoʻq. Birinchi uyingizni yarating.'),
                                    style: TextStyle(color: t.muted))),
                          for (final entry in store.corruptProjects.entries)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Sheet(
                                    child: ListTile(contentPadding: tilePad, 
                                        leading: Icon(YIcons.alert,
                                            color: t.crit),
                                        title: Text(entry.key),
                                        subtitle: Text(entry.value),
                                        trailing: IconButton(
                                            tooltip: tr3(
                                                '删除损坏的设计',
                                                'Бүлінген жобаны жою',
                                                'Удалить повреждённый проект',
                                                'Delete the damaged design', ky: 'Бузулган долбоорду өчүрүү', uz: 'Buzilgan loyihani oʻchirish'),
                                            icon: const Icon(
                                                YIcons.delete),
                                            onPressed: () =>
                                                deleteCorrupt(entry.key))))),
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
                          ? Icon(YIcons.home, color: t.muted)
                          // Same bytes every build: decoded once, then
                          // cached, and only at the tile's size.
                          : Image.memory(imageBytes(entry.preview!),
                              cacheWidth:
                                  (64 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
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
                            '${m(doc.footprint.width)} × ${m(doc.footprint.depth)} $unitM · ${doc.floors.length} ${tr3('层', 'қабат', 'эт.', 'fl.', ky: 'каб.', uz: 'qav.')}\n${tr3('更新于', 'Жаңартылды', 'Обновлён', 'Updated', ky: 'Жаңыланды', uz: 'Yangilandi')} ${doc.meta.updatedAt.split('T').first}',
                            style: mono(size: 12, color: t.muted)),
                      ])),
                  PopupMenuButton<String>(
                    tooltip:
                        tr3('项目操作', 'Жоба әрекеттері', 'Действия с проектом', 'Design actions', ky: 'Долбоор боюнча аракеттер', uz: 'Loyiha amallari'),
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
                          await export(entry, context);
                        case 'delete':
                          await delete(entry);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'edit',
                          child: Text(
                              tr3('编辑设计', 'Жобаны өңдеу', 'Редактировать', 'Edit', ky: 'Түзөтүү', uz: 'Tahrirlash'))),
                      if (widget.onPublishPost != null)
                        PopupMenuItem(
                            value: 'post',
                            child: Text(tr3('发布作品', 'Жобаны жариялау',
                                'Опубликовать проект',
                                'Publish the design', ky: 'Долбоорду жарыялоо', uz: 'Loyihani eʼlon qilish'))),
                      if (widget.onFindBuilders != null)
                        PopupMenuItem(
                            value: 'builders',
                            child: Text(tr3(
                                '找施工方', 'Мердігер табу', 'Найти подрядчика', 'Find a contractor', ky: 'Подрядчы табуу', uz: 'Pudratchi topish'))),
                      PopupMenuItem(
                          value: 'export',
                          child: Text(tr3('导出设计文件', 'Жоба файлын экспорттау',
                              'Экспорт файла проекта',
                              'Export the design file', ky: 'Долбоор файлын экспорттоо', uz: 'Loyiha faylini eksport qilish'))),
                      if (widget.onBackup != null)
                        PopupMenuItem(
                            value: 'backup',
                            child: Text(tr3(
                                '备份', 'Сақтық көшірме', 'Резервная копия', 'Backup', ky: 'Резервдик көчүрмө', uz: 'Zaxira nusxa'))),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text(
                              tr3('删除设计', 'Жобаны жою', 'Удалить проект', 'Delete the design', ky: 'Долбоорду өчүрүү', uz: 'Loyihani oʻchirish'))),
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
    final doc = featured!;
    final derived = featuredDerived!;
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
          TagPill(tr3('示例', 'Үлгі', 'Пример', 'Example', ky: 'Мисал', uz: 'Namuna'), t.accent),
          const SizedBox(height: 6),
          Text(
              tr3('哈萨克乡村住宅 10×13', 'Қазақ ауыл үйі 10×13',
                  'Казахский сельский дом 10×13',
                  'Kazakh village house 10×13', ky: 'Казак айылындагы үй 10×13', uz: 'Qozoq qishlogʻidagi uy 10×13'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              tr3(
                  '一层 · 外墙 400 mm · 平屋顶 · 8 个房间。已布置地毯、挂毯、矮圆桌、木箱和褥垫，带条形基础、预留套管和构造做法。打开后每一处都可以修改。',
                  'Бір қабат · сыртқы қабырға 400 мм · тегіс шатыр · 8 бөлме. Кілем, тұскиіз, дөңгелек үстел, сандық пен көрпеше қойылған; таспалы іргетас, гильзалар мен құрылым шешімдері бар. Ашқан соң бәрін өзгертуге болады.',
                  'Один этаж · наружные стены 400 мм · плоская крыша · 8 комнат. Расставлены ковёр, тускииз, круглый стол, сундук и корпе; есть ленточный фундамент, гильзы и конструктивные решения. После открытия всё можно менять.',
                  'One floor · 400 mm outer walls · flat roof · 8 rooms. Carpet, tus kiiz, round table, chest and korpe are placed; it has a strip foundation, sleeves and construction details. You can change everything after opening it.', ky: 'Бир кабат · 400 мм сырткы дубалдар · жалпак чатыр · 8 бөлмө. Килем, туш кийиз, тегерек стол, сандык жана төшөк коюлган; тасма пайдубалы, гильзалары жана конструкция деталдары бар. Ачкандан кийин баарын өзгөртсөңүз болот.', uz: 'Bir qavat · 400 mm tashqi devorlar · tekis tom · 8 xona. Gilam, devor gilami, dumaloq stol, sandiq va koʻrpa joylangan; lentali poydevor, gilzalar va konstruksiya tafsilotlari bor. Ochgandan keyin hammasini oʻzgartirishingiz mumkin.'),
              style: TextStyle(color: t.muted, height: 1.5)),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () => createFromTemplate('kz'),
              icon: const Icon(YIcons.openExternal, size: 18),
              label: Text(tr3('打开这个示例', 'Үлгіні ашу', 'Открыть пример', 'Open the example', ky: 'Мисалды ачуу', uz: 'Namunani ochish'))),
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
  final double? w;
  final double? d;
  final Color accent;
  final Color ink;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final w = this.w;
    final d = this.d;
    if (w == null || d == null || w <= 0 || d <= 0) return;
    const pad = 22.0;
    final k = math.min((size.width - pad * 2) / w, (size.height - pad * 2) / d);
    final rect = Rect.fromCenter(
        center: size.center(Offset.zero) + const Offset(6, -4),
        width: w * k,
        height: d * k);
    canvas
      ..drawRect(rect, Paint()..color = accent.withValues(alpha: 0.12))
      ..drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = ink);
    void label(String text, Offset at,
        {bool vertical = false, double size = 11}) {
      final tp = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(
                  fontSize: size, color: vertical || size < 12 ? muted : ink)),
          textDirection: TextDirection.ltr)
        ..layout();
      canvas
        ..save()
        ..translate(at.dx, at.dy);
      if (vertical) canvas.rotate(-math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      tp.dispose();
    }

    String m(double v) =>
        v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    label('${m(w)} m', Offset(rect.center.dx, rect.top - 9));
    label('${m(d)} m', Offset(rect.left - 10, rect.center.dy), vertical: true);
    label('${(w * d).toStringAsFixed(0)} m²', rect.center, size: 13);
  }

  @override
  bool shouldRepaint(covariant _SizePreviewPainter old) =>
      old.w != w || old.d != d || old.accent != accent;
}
