import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../../core/serialization/house_codec.dart';
import '../../../storage/project_store.dart';
import '../../domain/models.dart';
import '../../snapshot/design_snapshot.dart';
import '../l10n.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'plan_thumb.dart';
import 'showcase_detail_page.dart';

/// Picks one of my local designs and opens the publish form for it.
Future<void> shareMyDesign(BuildContext context) async {
  if (!await requireLogin(context) || !context.mounted) return;
  final List<ProjectEntry> projects;
  try {
    projects = await context.projectStore.listProjects();
  } catch (_) {
    if (context.mounted)
      toast(
          context,
          tr3('暂时无法读取设计', 'Жобаларды оқу мүмкін емес',
              'Не удалось прочитать проекты'));
    return;
  }
  if (!context.mounted) return;
  if (projects.isEmpty) {
    toast(context,
        tr3('先画一套设计，再来发布', 'Алдымен жоба жасаңыз', 'Сначала создайте проект'));
    ShellNav.goFrom(context, ShellTab.design);
    return;
  }
  final entry = projects.length == 1
      ? projects.single
      : await pickOne<ProjectEntry>(
          context,
          tr3('发布哪一套设计？', 'Қай жобаны?', 'Какой проект?'),
          [for (final p in projects) (p, p.document.meta.name)]);
  if (entry == null || !context.mounted) return;
  await pushPage<void>(context, (_) => ShareShowcasePage(entry: entry));
}

/// Publish a design to the home feed: a title, a few words about the
/// house, where it is and its style.
class ShareShowcasePage extends StatefulWidget {
  const ShareShowcasePage({super.key, required this.entry});
  final ProjectEntry entry;
  @override
  State<ShareShowcasePage> createState() => _ShareShowcasePageState();
}

class _ShareShowcasePageState extends State<ShareShowcasePage> {
  late final title =
      TextEditingController(text: widget.entry.document.meta.name);
  final story = TextEditingController();
  String region = regionCodes.first;
  final styles = <String>{};
  late final String text = encodeHouse(widget.entry.document);

  @override
  void dispose() {
    title.dispose();
    story.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (title.text.trim().isEmpty) {
      toast(context, tr3('给房子起个名字', 'Атау жазыңыз', 'Дайте название'));
      return;
    }
    final f = showcaseFacts(widget.entry.document);
    final s = await attempt(
        context,
        () => context.repos.publishShowcase(
            projectId: widget.entry.id,
            title: title.text,
            story: story.text,
            region: region,
            styles: styles.toList(),
            houseText: text,
            width: f.width,
            depth: f.depth,
            floors: f.floors,
            rooms: f.rooms,
            area: f.area),
        success: tr3('已发布到首页', 'Жарияланды', 'Опубликовано'));
    if (s == null || !mounted) return;
    await Navigator.of(context).pushReplacement(
        platformRoute((_) => ShowcaseDetailPage(showcaseId: s.id)));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    AppScope.watch(context);
    return PageScaffold(
        title: tr3('发布到首页', 'Жариялау', 'Опубликовать'),
        bottom: SizedBox(
            width: double.infinity,
            child: BusyButton(
                label: tr3('发布', 'Жариялау', 'Опубликовать'),
                onPressed: publish)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(yRadius),
              child: SizedBox(
                  height: 220,
                  child: PlanThumb(
                      cacheKey:
                          'share-${widget.entry.id}-${widget.entry.document.meta.updatedAt}',
                      houseText: text,
                      labels: true))),
          const SizedBox(height: 8),
          Text(
              tr3(
                  '大家会看到平面、尺寸和房间；精确地址和你的手机号不会公开。',
                  'Жоспар мен өлшем көрінеді; мекенжай мен телефон жасырын.',
                  'Видны план и размеры; адрес и телефон скрыты.'),
              style: TextStyle(color: t.muted, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
              controller: title,
              maxLength: 40,
              decoration:
                  InputDecoration(labelText: tr3('名称', 'Атауы', 'Название'))),
          const SizedBox(height: 8),
          TextField(
              controller: story,
              maxLines: 4,
              maxLength: 400,
              decoration: InputDecoration(
                  labelText: tr3('说说这套房子', 'Үй туралы', 'О доме'),
                  hintText: tr3(
                      '给谁住、有什么想法、现在进行到哪一步',
                      'Кімге, қандай ой, қай кезең',
                      'Для кого, идеи, на каком этапе'),
                  alignLabelWithHint: true)),
          SectionTitle(tr3('地区', 'Аймақ', 'Район'), top: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in regionCodes)
              ChoiceChip(
                  label: Text(regionName(r)),
                  selected: region == r,
                  onSelected: (_) => setState(() => region = r)),
          ]),
          SectionTitle(tr3('风格（可多选）', 'Стиль', 'Стиль')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in showcaseStyles)
              FilterChip(
                  label: Text(styleName(s)),
                  selected: styles.contains(s),
                  onSelected: (on) =>
                      setState(() => on ? styles.add(s) : styles.remove(s))),
          ]),
        ]));
  }
}
