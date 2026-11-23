import 'package:flutter/material.dart';
import 'package:yusal/constant/tokens.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/backup/page.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/features/home/pages/post.dart';
import 'package:yusal/features/home/pages/publish_post.dart';
import 'package:yusal/features/demand/pages/from_design.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/shared/ui/house_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/houses/model/my_house.dart';
import 'package:yusal/features/houses/state/my_houses.dart';
import 'package:yusal/features/projects/state/projects.dart';
import 'package:yusal/features/houses/widgets/my_jobs.dart';
import 'package:yusal/features/houses/page.dart';
import 'package:yusal/features/shared/motion/motion.dart';

/// Second tab, "我的房子": where each of my houses stands. One title, then
/// what needs me (to-dos and houses with platform activity), then my
/// designs with their two main actions in view. People with a pro card
/// also get "我接的活".
class ProjectsPage extends StatelessWidget {
  const ProjectsPage(
      {super.key,
      required this.drafting,
      required this.reload,
      this.createRequest});

  /// The design tool keeps its own drafting look.
  final ThemeData drafting;
  final Listenable reload;

  /// "＋ → draw from scratch" opens the template picker.
  final Listenable? createRequest;

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final title = Text(tr3('我的房子', 'Үйлерім', 'Мои дома', 'My houses', ky: 'Үйлөрүм', uz: 'Uylarim'), style: display());
    // The design list owns storage, import, templates and export; this
    // page only draws it.
    return HouseHome(
        store: context.projectStore,
        reload: reload,
        createRequest: createRequest,
        builder: (context, list) {
          final houses = _HousesView(list: list, reload: reload);
          final actions = [
            IconButton(
                key: const Key('designs-import'),
                tooltip: tr3(
                    '导入 .house 文件', '.house файлын ашу', 'Открыть файл .house', 'Open a .house file', ky: '.house файлын ачуу', uz: '.house faylini ochish'),
                icon: const Icon(Icons.file_open_outlined),
                onPressed: list.import),
            const SizedBox(width: YSpace.xs),
          ];
          return OnChange(
              builder: (context) => Live<bool>(
                  provider: isProProvider,
                  loading: Scaffold(
                      appBar: AppBar(title: title, actions: actions),
                      body: houses),
                  builder: (context, pro) => !pro
                      ? Scaffold(
                          appBar: AppBar(title: title, actions: actions),
                          body: houses)
                      : DefaultTabController(
                          length: 2,
                          child: Scaffold(
                              appBar: AppBar(
                                  title: title,
                                  actions: actions,
                                  bottom: TabBar(tabs: [
                                    Tab(
                                        text:
                                            tr3('我的房子', 'Үйлерім', 'Мои дома', 'My houses', ky: 'Үйлөрүм', uz: 'Uylarim')),
                                    Tab(
                                        text: tr3('我接的活', 'Жұмыстарым',
                                            'Моя работа',
                                            'My work', ky: 'Менин ишим', uz: 'Mening ishim')),
                                  ])),
                              body: MotionTabView(
                                  children: [houses, const MyJobsView()])))));
        });
  }
}

/// My designs in the platform look: new design first, then what needs me,
/// then every design as a card.
class _HousesView extends StatelessWidget {
  const _HousesView({required this.list, required this.reload});
  final DesignList list;
  final Listenable reload;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final projects = list.projects;
    return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
                // A list given its own padding no longer clears the
                // floating tab bar by itself: add the bar's height, or the
                // last row sits under the bar and the page cannot scroll
                // to it.
                padding: EdgeInsets.fromLTRB(
                    YSpace.gutter,
                    YSpace.sm,
                    YSpace.gutter,
                    YSpace.huge + MediaQuery.paddingOf(context).bottom),
                children: [
                  // The two ways to start, always in reach.
                  Wrap(spacing: YSpace.md, runSpacing: YSpace.sm, children: [
                    FilledButton.icon(
                        key: const Key('designs-new'),
                        onPressed: list.createFromTemplate,
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(tr3('新建设计', 'Жаңа жоба', 'Новый проект', 'New design', ky: 'Жаңы долбоор', uz: 'Yangi loyiha'))),
                    OutlinedButton.icon(
                        key: const Key('designs-template'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: list.createFromTemplate,
                        icon: const Icon(Icons.auto_awesome_mosaic_outlined,
                            size: 18),
                        label: Text(tr3(
                            '也可以从示例开始', 'Үлгіден бастау', 'Начать с примера', 'Start from an example', ky: 'Мисалдан баштоо', uz: 'Namunadan boshlash'))),
                  ]),
                  if (list.error != null) ...[
                    const SizedBox(height: YSpace.md),
                    Hint(list.error!, warn: true),
                  ],
                  if (context.session.currentAccount != null)
                    _ReloadOn(
                        listenable: reload,
                        provider: myHousesProvider,
                        child: Live<List<MyHouse>>(
                            provider: myHousesProvider,
                            loading: const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                            builder: (context, houses) => houses.isEmpty
                                ? const SizedBox.shrink()
                                : _ActiveHouses(houses: houses))),
                  SectionTitle(tr3('我的设计', 'Жобаларым', 'Мои проекты', 'My designs', ky: 'Менин долбоорлорум', uz: 'Mening loyihalarim'),
                      trailing: projects.isEmpty
                          ? null
                          : Text('${projects.length}',
                              style: YText.label.copyWith(color: t.muted))),
                  for (final entry in list.corruptProjects.entries)
                    Padding(
                        padding: const EdgeInsets.only(bottom: YSpace.md),
                        child: YCard(
                            padding: const EdgeInsets.fromLTRB(
                                YSpace.lg, YSpace.sm, YSpace.xs, YSpace.sm),
                            child: Row(children: [
                              Icon(Icons.error_outline, color: t.crit),
                              const SizedBox(width: YSpace.md),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(entry.key,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: YText.labelStrong),
                                    Text(entry.value,
                                        style: YText.caption
                                            .copyWith(color: t.muted)),
                                  ])),
                              IconButton(
                                  tooltip: tr3('删除损坏的设计', 'Бүлінген жобаны жою',
                                      'Удалить повреждённый проект',
                                      'Delete the damaged design', ky: 'Бузулган долбоорду өчүрүү', uz: 'Buzilgan loyihani oʻchirish'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      list.deleteCorrupt(entry.key)),
                            ]))),
                  if (!list.loaded)
                    const SkeletonList(count: 2, avatar: true)
                  else if (projects.isEmpty)
                    _FirstDesign(list: list)
                  else ...[
                    LayoutBuilder(builder: (context, c) {
                      final columns = c.maxWidth >= 720 ? 2 : 1;
                      final w =
                          (c.maxWidth - YSpace.md * (columns - 1)) / columns;
                      return Wrap(
                          spacing: YSpace.md,
                          runSpacing: YSpace.md,
                          children: [
                            for (final entry in projects)
                              SizedBox(
                                  width: w,
                                  child: _DesignCard(entry: entry, list: list)),
                          ]);
                    }),
                    const SizedBox(height: YSpace.lg),
                    _ExampleRow(list: list),
                  ],
                ])));
  }
}

/// One of my designs: its drawing, name and size, the two things people
/// do most (continue, find builders) and a menu for the rest.
class _DesignCard extends StatelessWidget {
  const _DesignCard({required this.entry, required this.list});
  final ProjectEntry entry;
  final DesignList list;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final doc = entry.document;
    // 10 × 13 м, 10,5 × 13 м: no ".0" on whole metres.
    String m(int mm) => dec((mm / 1000)
        .toStringAsFixed(mm % 1000 == 0 ? 0 : (mm % 100 == 0 ? 1 : 2)));
    final floors = doc.floors.length;
    return YCard(
        key: Key('design-card-${entry.id}'),
        padding: const EdgeInsets.all(YSpace.md),
        onTap: () => list.open(entry),
        child: Column(children: [
          Row(children: [
            _PlanThumb(preview: entry.preview, size: 72),
            const SizedBox(width: YSpace.md),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(doc.meta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                      '${m(doc.footprint.width)} × ${m(doc.footprint.depth)} $unitM · ${switch (floors) {
                        1 => tr3('一层', 'бір қабат', '1 этаж', '1 floor', ky: '1 кабат', uz: '1 qavat'),
                        2 => tr3('两层', 'екі қабат', '2 этажа', '2 floors', ky: '2 кабат', uz: '2 qavat'),
                        final n => tr3('$n 层', '$n қабат', 'этажей: $n', 'floors: $n', ky: 'кабаттар: $n', uz: 'qavatlar: $n'),
                      }}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YText.label.copyWith(
                          color: t.muted, fontFeatures: YText.tabular)),
                  Text(
                      '${tr3('更新于', 'Жаңартылды', 'Обновлён', 'Updated', ky: 'Жаңыланды', uz: 'Yangilandi')} ${fmtDay(DateTime.tryParse(doc.meta.updatedAt))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YText.caption.copyWith(
                          color: t.muted, fontFeatures: YText.tabular)),
                ])),
            Builder(
                builder: (anchor) => PopupMenuButton<String>(
                    tooltip:
                        tr3('项目操作', 'Жоба әрекеттері', 'Действия с проектом', 'Design actions', ky: 'Долбоор боюнча аракеттер', uz: 'Loyiha amallari'),
                    icon: Icon(Icons.more_horiz, color: t.muted),
                    onSelected: (action) async {
                      switch (action) {
                        case 'post':
                          await pushPage<void>(
                              context, (_) => PublishPostPage(entry: entry));
                        case 'backup':
                          await pushPage<void>(
                              context, (_) => BackupPage(highlight: entry.id));
                        case 'export':
                          await list.export(entry, anchor);
                        case 'delete':
                          await list.delete(entry);
                      }
                    },
                    itemBuilder: (_) => [
                          _item('post', Icons.ios_share,
                              tr3('发布作品', 'Жобаны жариялау', 'Опубликовать', 'Publish', ky: 'Жарыялоо', uz: 'Eʼlon qilish')),
                          _item(
                              'export',
                              Icons.download_outlined,
                              tr3('导出设计文件', 'Жоба файлын экспорттау',
                                  'Экспорт файла',
                                  'Export file', ky: 'Файлды экспорттоо', uz: 'Faylni eksport qilish')),
                          _item('backup', Icons.cloud_outlined,
                              tr3('备份', 'Сақтық көшірме', 'Резервная копия', 'Backup', ky: 'Резервдик көчүрмө', uz: 'Zaxira nusxa')),
                          const PopupMenuDivider(),
                          _item('delete', Icons.delete_outline,
                              tr3('删除设计', 'Жобаны жою', 'Удалить проект', 'Delete the design', ky: 'Долбоорду өчүрүү', uz: 'Loyihani oʻchirish'),
                              color: t.crit),
                        ])),
          ]),
          const SizedBox(height: YSpace.md),
          Row(children: [
            Expanded(
                child: FilledButton(
                    key: Key('design-continue-${entry.id}'),
                    style: FilledButton.styleFrom(
                        backgroundColor: t.accentSoft,
                        foregroundColor: t.dark ? t.ink : t.accent,
                        minimumSize: const Size(0, yTouch),
                        padding:
                            const EdgeInsets.symmetric(horizontal: YSpace.sm)),
                    onPressed: () => list.open(entry),
                    child: Text(tr3('继续设计', 'Жалғастыру', 'Продолжить', 'Continue', ky: 'Улантуу', uz: 'Davom etish'),
                        maxLines: 1, overflow: TextOverflow.ellipsis))),
            const SizedBox(width: YSpace.sm),
            Expanded(
                child: OutlinedButton(
                    key: Key('design-builders-${entry.id}'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, yTouch),
                        padding:
                            const EdgeInsets.symmetric(horizontal: YSpace.sm)),
                    onPressed: () => pushPage<void>(
                        context, (_) => FromDesignPage(entry: entry)),
                    child: Text(tr3('找施工方', 'Шебер табу', 'Найти мастеров', 'Find pros', ky: 'Адистерди табуу', uz: 'Mutaxassis topish'),
                        maxLines: 1, overflow: TextOverflow.ellipsis))),
          ]),
        ]));
  }

  static PopupMenuItem<String> _item(String value, IconData icon, String text,
          {Color? color}) =>
      PopupMenuItem(
          value: value,
          child: Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: YSpace.md),
            Flexible(
                child: Text(text,
                    style: color == null ? null : TextStyle(color: color))),
          ]));
}

/// A design's drawing on its sheet of paper, or a house icon without one.
class _PlanThumb extends StatelessWidget {
  const _PlanThumb({required this.preview, required this.size});
  final List<int>? preview;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: preview == null ? t.surface : Tokens.light.room,
            borderRadius: BorderRadius.circular(YRadius.control),
            border: Border.all(color: t.line)),
        child: preview == null
            ? Icon(Icons.other_houses_outlined, color: t.muted)
            // Decoded at the tile's size, not the 512 px preview's.
            : Image.memory(imageBytes(preview!),
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
                fit: BoxFit.contain,
                excludeFromSemantics: true));
  }
}

/// Nothing drawn yet: the example house, ready to open and change.
class _FirstDesign extends StatelessWidget {
  const _FirstDesign({required this.list});
  final DesignList list;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return YCard(
        key: const Key('designs-empty'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                  color: Tokens.light.room,
                  borderRadius: BorderRadius.circular(YRadius.control)),
              // A drawing is a sheet of paper: light in both themes.
              child: Theme(
                  data: Theme.of(context).copyWith(
                      extensions: [YTokens.of(context), Tokens.light]),
                  child: Builder(builder: list.examplePreview))),
          const SizedBox(height: YSpace.lg),
          Text(tr3('还没有设计', 'Әзірге жоба жоқ', 'Проектов пока нет', 'No designs yet', ky: 'Азырынча долбоор жок', uz: 'Hozircha loyiha yoʻq'),
              style: YText.heading),
          const SizedBox(height: YSpace.xs),
          Text(
              tr3(
                  '输入长宽就能开始；或者打开这栋哈萨克乡村住宅 10 × 13 米，每一处都可以改。',
                  'Ені мен ұзындығын енгізіп бастаңыз немесе 10 × 13 м қазақ ауыл үйінің үлгісін ашып, кез келген жерін өзгертіңіз.',
                  'Начните с ширины и длины — или откройте пример сельского дома 10 × 13 м и меняйте в нём что угодно.',
                  'Start with width and length, or open the 10 × 13 m village house example and change anything in it.', ky: 'Туурасы менен узундугунан баштаңыз же 10 × 13 м айыл үйүнүн мисалын ачып, каалаганыңызды өзгөртүңүз.', uz: 'Eni va uzunligidan boshlang yoki 10 × 13 m qishloq uyi namunasini ochib, xohlaganingizni oʻzgartiring.'),
              style: YText.label.copyWith(color: t.muted)),
          const SizedBox(height: YSpace.lg),
          OutlinedButton.icon(
              key: const Key('designs-open-example'),
              onPressed: () => list.createFromTemplate('kz'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(tr3('打开这个示例', 'Үлгіні ашу', 'Открыть пример', 'Open the example', ky: 'Мисалды ачуу', uz: 'Namunani ochish'))),
        ]));
  }
}

/// A quiet way back to the example once there are designs.
class _ExampleRow extends StatelessWidget {
  const _ExampleRow({required this.list});
  final DesignList list;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return YCard(
        color: t.surface,
        padding: const EdgeInsets.symmetric(
            horizontal: YSpace.lg, vertical: YSpace.md),
        onTap: () => list.createFromTemplate('kz'),
        child: Row(children: [
          Icon(Icons.auto_awesome_mosaic_outlined, color: t.accent),
          const SizedBox(width: YSpace.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    tr3(
                        '示例：哈萨克乡村住宅 10 × 13 米',
                        'Үлгі: қазақ ауыл үйі 10 × 13 м',
                        'Пример: сельский дом 10 × 13 м',
                        'Example: 10 × 13 m village house', ky: 'Мисал: 10 × 13 м айыл үйү', uz: 'Namuna: 10 × 13 m qishloq uyi'),
                    style: YText.labelStrong),
                Text(
                    tr3(
                        '8 个房间，带家具和构造，打开后随便改',
                        '8 бөлме, жиһазы мен құрылымы бар',
                        '8 комнат, с мебелью и конструкциями',
                        '8 rooms, with furniture and structure', ky: '8 бөлмө, эмерек жана конструкциясы менен', uz: '8 xona, mebel va konstruksiyasi bilan'),
                    style: YText.caption.copyWith(color: t.muted)),
              ])),
          Icon(Icons.chevron_right, color: t.faint),
        ]));
  }
}

/// To-do strip (things only I can unblock: confirmations, inspections,
/// work days; new quotes show on the house cards) and the houses that have demands, quotes or cooperations.
class _ActiveHouses extends StatelessWidget {
  const _ActiveHouses({required this.houses});
  final List<MyHouse> houses;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.session.currentAccount?.id ?? '';
    final todos = <(String, MyHouse, int)>[];
    for (final h in houses) {
      if (h.pendingConfirm(me) > 0) {
        todos.add((
          tr3('「${h.name}」有合作约定待你确认', '«${h.name}»: келісімді растаңыз',
              '«${h.name}»: подтвердите соглашение',
              '“${h.name}”: confirm the agreement', ky: '«${h.name}»: макулдашууну ырастаңыз', uz: '“${h.name}”: kelishuvni tasdiqlang'),
          h,
          2
        ));
      }
      if (h.endAsks(me) > 0) {
        todos.add((
          tr3('「${h.name}」对方请求结束合作', '«${h.name}»: аяқтауды растаңыз',
              '«${h.name}»: подтвердите завершение',
              '“${h.name}”: confirm completion', ky: '«${h.name}»: бүтүрүүнү ырастаңыз', uz: '“${h.name}”: yakunlashni tasdiqlang'),
          h,
          2
        ));
      }
      final inspections = h.cooperations
          .expand((c) => c.milestones)
          .where((m) => m.status == MilestoneStatus.requested)
          .length;
      if (inspections > 0) {
        todos.add((
          tr3(
              '「${h.name}」$inspections 个节点待验收',
              '«${h.name}»: кезеңді қабылдаңыз',
              '«${h.name}»: этапов к приёмке $inspections',
              '“${h.name}”: stages to accept: $inspections', ky: '«${h.name}»: кабыл ала турган этаптар: $inspections', uz: '“${h.name}”: qabul qilinadigan bosqichlar: $inspections'),
          h,
          3
        ));
      }
      final days = h.cooperations
          .expand((c) => c.workLogs)
          .where((w) => !w.confirmed)
          .length;
      if (days > 0) {
        todos.add((
          tr3('「${h.name}」$days 天记工待确认', '«${h.name}»: $days күн расталмады',
              '«${h.name}»: дней к подтверждению $days',
              '“${h.name}”: days to confirm: $days', ky: '«${h.name}»: ырастоого калган күндөр: $days', uz: '“${h.name}”: tasdiqlashga qolgan kunlar: $days'),
          h,
          3
        ));
      }
    }
    void open(MyHouse h, int tab) => pushPage<void>(
        context,
        (_) => h.shareOnly
            ? PostPage(postId: h.postId!)
            : HouseWorkspacePage(houseKey: h.key, initialTab: tab));
    // Finished houses move out of the ongoing ones.
    final done = houses.where((h) => h.stage == HouseStage.done).toList();
    final ongoing = houses.where((h) => h.stage != HouseStage.done).toList();
    Widget strip(List<MyHouse> list) => SizedBox(
        height: 104,
        child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final h = list[i];
              return SizedBox(
                  width: 290,
                  child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                          key: Key('house-card-${h.key}'),
                          borderRadius: BorderRadius.circular(yRadius),
                          onTap: () => open(h, 0),
                          child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(children: [
                                HouseThumb(house: h, size: 80),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                      Text(h.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      StatusPill(
                                          h.shareOnly
                                              ? tr3('已分享', 'Бөлісілді',
                                                  'Опубликован',
                                                  'Published', ky: 'Жарыяланган', uz: 'Eʼlon qilingan')
                                              : houseStageName(h.stage),
                                          color: t.accent),
                                      const SizedBox(height: 4),
                                      Text(h.nextStep(me),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: h.needsMe(me)
                                                  ? t.accent
                                                  : t.muted,
                                              fontWeight: h.newQuotes > 0
                                                  ? FontWeight.w600
                                                  : null,
                                              fontSize: YFont.caption)),
                                    ])),
                              ])))));
            }));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (todos.isNotEmpty) ...[
        SectionTitle(tr3('等你处理', 'Сізді күтуде', 'Ждут вас', 'Waiting for you', ky: 'Сизди күтүүдө', uz: 'Sizni kutmoqda')),
        Material(
            key: const Key('todo-strip'),
            color: t.accentSoft,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(YRadius.card),
            child: Column(children: [
              for (final (text, h, tab) in todos.take(4))
                InkWell(
                    onTap: () => open(h, tab),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: yTouch),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: YSpace.lg, vertical: YSpace.sm),
                            child: Row(children: [
                              Icon(Icons.circle, size: 8, color: t.accent),
                              const SizedBox(width: YSpace.md),
                              Expanded(
                                  child: Text(text, style: YText.labelStrong)),
                              Icon(Icons.chevron_right,
                                  size: 20, color: t.muted),
                            ])))),
            ])),
      ],
      if (ongoing.isNotEmpty) ...[
        SectionTitle(tr3('进行中的房子', 'Жүріп жатқан үйлер', 'Дома в работе', 'Houses in progress', ky: 'Курулуп жаткан үйлөр', uz: 'Qurilayotgan uylar')),
        strip(ongoing),
      ],
      if (done.isNotEmpty) ...[
        SectionTitle(tr3('已完工', 'Аяқталған', 'Готовые', 'Finished', ky: 'Бүткөн', uz: 'Tugallangan')),
        strip(done),
      ],
    ]);
  }
}

class MyCooperations extends StatefulWidget {
  const MyCooperations({super.key});
  @override
  State<MyCooperations> createState() => _MyCooperationsState();
}

class _MyCooperationsState extends State<MyCooperations> {
  int _retry = 0;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return OnChange(
        builder: (context) => context.session.currentAccount == null
            ? SignInPrompt(
                text: tr3('登录后查看合作记录', 'Кіріңіз',
                    'Войдите, чтобы видеть сотрудничество',
                    'Sign in to see cooperations', ky: 'Кызматташууларды көрүү үчүн кириңиз', uz: 'Hamkorliklarni koʻrish uchun kiring'))
            : Live<List<(Cooperation, String)>>(
                provider: myCooperationsProvider(_retry),
                builder: (context, list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.handshake_outlined,
                        title: tr3(
                            '还没有合作', 'Келісім жоқ', 'Пока нет сотрудничества', 'No cooperations yet', ky: 'Азырынча кызматташуу жок', uz: 'Hozircha hamkorlik yoʻq'),
                        body: tr3(
                            '在报名／报价中选定对方并双方确认后，会出现在这里。',
                            'Екі жақ растағаннан кейін осында болады.',
                            'Появится после подтверждения обеими сторонами.',
                            'They appear once both sides confirm.', ky: 'Эки тарап ырастагандан кийин пайда болот.', uz: 'Ikkala tomon tasdiqlagandan keyin paydo boʻladi.'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                    onPressed: () => setState(() => _retry++),
                                    icon: const Icon(Icons.refresh),
                                    label: Text(
                                        tr3('刷新', 'Жаңарту', 'Обновить', 'Refresh', ky: 'Жаңылоо', uz: 'Yangilash')))),
                            for (final (c, title) in list)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: YCard(
                                      onTap: () =>
                                          openCooperation(context, c.id),
                                      child: Row(children: [
                                        const Icon(Icons.handshake_outlined),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(title,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              Text(
                                                  '${cooperationStatusName(c)} · ${c.agreement.amount == null ? '' : money(c.agreement.amount, unit: c.agreement.amountUnit)}',
                                                  style: TextStyle(
                                                      color: t.muted,
                                                      fontSize: YFont.small)),
                                            ])),
                                        const Icon(Icons.chevron_right),
                                      ]))),
                          ])));
  }
}

/// Reloads [provider] whenever [listenable] fires (the local designs
/// changed), on top of the reloads a backend change brings.
class _ReloadOn extends StatefulWidget {
  const _ReloadOn(
      {required this.listenable, required this.provider, required this.child});
  final Listenable listenable;
  final ProviderOrFamily provider;
  final Widget child;
  @override
  State<_ReloadOn> createState() => _ReloadOnState();
}

class _ReloadOnState extends State<_ReloadOn> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant _ReloadOn old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_reload);
      widget.listenable.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_reload);
    super.dispose();
  }

  void _reload() => ProviderScope.containerOf(context, listen: false)
      .invalidate(widget.provider);

  @override
  Widget build(BuildContext context) => widget.child;
}
