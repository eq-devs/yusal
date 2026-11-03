import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../../storage/project_store.dart';
import '../../domain/models.dart';
import '../../snapshot/design_snapshot.dart';
import '../../../render2d/planning_names.dart' show costLineName;
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'post_page.dart';

/// Shares a local design to the feed: a title, a few words, the region,
/// whether builders are welcome. Area, floors, rooms and the cost estimate
/// come from the design itself.
class PublishPostPage extends StatefulWidget {
  const PublishPostPage({super.key, required this.entry});
  final ProjectEntry entry;
  @override
  State<PublishPostPage> createState() => _PublishPostPageState();
}

class _PublishPostPageState extends State<PublishPostPage> {
  late final title =
      TextEditingController(text: widget.entry.document.meta.name);
  final story = TextEditingController();
  String region = regionCodes.first;
  bool openForBuilders = true;
  final tags = <String>{};
  DesignExtract? extract;

  @override
  void initState() {
    super.initState();
    try {
      extract =
          extractDesign(widget.entry.document, const [], nameOf: costLineName);
      if (extract!.floors >= 2) tags.add('two_floors');
      if (extract!.floors == 1) tags.add('one_floor');
    } catch (_) {
      extract = null;
    }
  }

  @override
  void dispose() {
    title.dispose();
    story.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (title.text.trim().isEmpty) {
      toast(context, tr3('请填标题', 'Атауын жазыңыз', 'Введите название'));
      return;
    }
    if (!await requireLogin(context) || !mounted) return;
    final doc = widget.entry.document;
    final e = extract;
    final snapshot = buildSnapshot(
        projectId: widget.entry.id,
        doc: doc,
        stages: snapshotStages,
        lines: e?.lines ?? const [],
        summary: e == null
            ? doc.meta.name
            : '${(e.width / 1000).toStringAsFixed(1)} × ${(e.depth / 1000).toStringAsFixed(1)} m · ${e.floors} ${tr3('层', 'қабат', 'эт.')} · ${e.buildingArea.toStringAsFixed(0)} m²',
        preview: widget.entry.preview);
    final post = await attempt(context, () async {
      final saved = await context.repos.saveSnapshot(snapshot);
      return context.repos.publishPost(HousePost(
          id: '',
          ownerId: '',
          projectId: widget.entry.id,
          snapshotId: saved.id,
          title: title.text,
          story: story.text,
          region: region,
          createdAt: context.now,
          updatedAt: context.now,
          area: e?.buildingArea ?? 0,
          floors: e?.floors ?? doc.floors.length,
          rooms: e?.rooms ?? 0,
          estimatedCost: e?.estimatedCost,
          tags: tags.toList(),
          openForBuilders: openForBuilders,
          preview: widget.entry.preview));
    });
    if (!mounted) return;
    if (post != null) {
      toast(context, tr3('已发布到首页', 'Жарияланды', 'Опубликовано'));
      Navigator.of(context)
          .pushReplacement(platformRoute((_) => PostPage(postId: post.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    final e = extract;
    final preview = widget.entry.preview;
    return PageScaffold(
        title: tr3('发布到首页', 'Басты бетке', 'Опубликовать'),
        bottom: ActionBar(
            child: Row(children: [
          Expanded(
              child: Text(
                  tr3('发布后所有人可见，随时可以下架。', 'Барлығы көреді, жасыруға болады.',
                      'Увидят все; можно скрыть.'),
                  style: TextStyle(color: t.muted, fontSize: 13))),
          BusyButton(
              expand: false,
              onPressed: publish,
              label: tr3('发布', 'Жариялау', 'Опубликовать')),
        ])),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Cover(
              icon: Icons.home_outlined,
              seed: widget.entry.id,
              height: 200,
              image: preview == null
                  ? null
                  : MemoryImage(Uint8List.fromList(preview))),
          if (e != null)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                    '${e.buildingArea.toStringAsFixed(0)} m² · ${e.floors} ${tr3('层', 'қабат', 'эт.')} · ${e.rooms} ${tr3('个房间', 'бөлме', 'комн.')}${e.estimatedCost == null ? '' : ' · ≈ ${money(e.estimatedCost)}'}',
                    style: TextStyle(color: t.muted)))
          else
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Hint(
                    tr3('无法从这个设计算出面积和造价，只发布平面图和说明。', 'Есептеу мүмкін емес.',
                        'Не удалось посчитать площадь и стоимость.'),
                    warn: true)),
          const SizedBox(height: 18),
          TextField(
              controller: title,
              maxLength: 40,
              decoration: InputDecoration(
                  labelText: tr3('标题', 'Атауы', 'Название'),
                  hintText: tr3('比如：给父母盖的一层砖房', 'Мысалы: ата-анама үй',
                      'Например: дом для родителей'))),
          const SizedBox(height: 12),
          TextField(
              controller: story,
              minLines: 3,
              maxLines: 8,
              maxLength: 600,
              decoration: InputDecoration(
                  labelText: tr3('说明（可选）', 'Сипаттама', 'Описание'),
                  hintText: tr3(
                      '给谁住、为什么这么设计、想听大家什么意见…',
                      'Кім тұрады, неге осылай…',
                      'Для кого, почему так, что хотите услышать…'),
                  alignLabelWithHint: true)),
          SectionTitle(tr3('地区', 'Аймақ', 'Район'), top: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in regionCodes)
              FilterPill(
                  label: regionName(c),
                  selected: region == c,
                  onTap: () => setState(() => region = c)),
          ]),
          SectionTitle(tr3('标签', 'Тегтер', 'Теги')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in postTags)
              FilterPill(
                  label: postTagName(c),
                  selected: tags.contains(c),
                  onTap: () => setState(
                      () => tags.contains(c) ? tags.remove(c) : tags.add(c))),
          ]),
          const SizedBox(height: 16),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: openForBuilders,
              onChanged: (v) => setState(() => openForBuilders = v),
              title: Text(tr3('欢迎施工方联系我', 'Құрылысшылар жаза алады',
                  'Строители могут написать мне')),
              subtitle: Text(tr3(
                  '首页会标出“正在找施工方”。具体需求可以之后在房子页里发布。',
                  'Бетте белгі болады.',
                  'На карточке появится пометка; заявку можно создать позже.'))),
          const SizedBox(height: 40),
        ]));
  }
}
