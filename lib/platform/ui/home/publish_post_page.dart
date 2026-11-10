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
import '../unsaved_changes_guard.dart';
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

  /// Default: share to hear opinions; building is one tap away later.
  bool openForBuilders = false;
  final focus = <String>[];
  final tags = <String>{};
  DesignExtract? extract;
  late String _initialDraft;
  bool _busy = false;
  String get _draft => [
        title.text,
        story.text,
        region,
        openForBuilders,
        focus.join(','),
        (tags.toList()..sort()).join(',')
      ].join('\u0000');

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
    _initialDraft = _draft;
  }

  @override
  void dispose() {
    title.dispose();
    story.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _publish();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
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
          focus: openForBuilders ? const [] : List.of(focus),
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
    return UnsavedChangesGuard(
        hasChanges: () => _draft != _initialDraft,
        isBusy: () => _busy,
        changes: Listenable.merge([title, story]),
        child: PageScaffold(
            title: tr3('发布到首页', 'Басты бетке', 'Опубликовать'),
            bottom: Row(children: [
              Expanded(
                  child: Text(
                      tr3(
                          '发布后所有人可查看各楼层图纸；不含私人备注，随时可下架。',
                          'Қабат жоспарлары жарияланады, жеке жазбаларсыз. Жасыруға болады.',
                          'Планы этажей доступны всем, без личных заметок. Можно скрыть.'),
                      style: TextStyle(color: t.muted, fontSize: YFont.small))),
              BusyButton(
                  expand: false,
                  onPressed: publish,
                  label: tr3('发布', 'Жариялау', 'Опубликовать')),
            ]),
            body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            tr3(
                                '无法从这个设计算出面积和造价，只发布平面图和说明。',
                                'Есептеу мүмкін емес.',
                                'Не удалось посчитать площадь и стоимость.'),
                            warn: true)),
                  SectionTitle(tr3('你想要什么？', 'Не қалайсыз?', 'Чего вы хотите?'),
                      top: 18),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: _IntentCard(
                            key: const Key('intent-feedback'),
                            selected: !openForBuilders,
                            icon: Icons.forum_outlined,
                            title:
                                tr3('听听大家意见', 'Пікір тыңдау', 'Узнать мнения'),
                            body: tr3('只分享，收点评和建议', 'Тек бөлісу',
                                'Просто поделиться и получить советы'),
                            onTap: () =>
                                setState(() => openForBuilders = false))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _IntentCard(
                            key: const Key('intent-build'),
                            selected: openForBuilders,
                            icon: Icons.construction,
                            title: tr3('准备盖，找施工方', 'Салуға дайын',
                                'Строю, ищу мастеров'),
                            body: tr3(
                                '标出“正在找施工方”，之后发具体需求',
                                'Құрылысшы іздеймін',
                                'Пометка «ищет строителей»'),
                            onTap: () =>
                                setState(() => openForBuilders = true))),
                  ]),
                  if (!openForBuilders) ...[
                    const SizedBox(height: 12),
                    Text(
                        tr3(
                            '最想请大家看哪些方面？（最多 3 个，可不选）',
                            'Нені көрсін? (3-ке дейін)',
                            'На что обратить внимание? (до 3)'),
                        style: TextStyle(color: t.muted, fontSize: YFont.small)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final k in feedbackTopics)
                        FilterPill(
                            key: Key('focus-$k'),
                            label: feedbackTopicName(k),
                            selected: focus.contains(k),
                            onTap: () => setState(() {
                                  if (focus.contains(k))
                                    focus.remove(k);
                                  else if (focus.length < 3)
                                    focus.add(k);
                                  else
                                    toast(
                                        context,
                                        tr3('最多选 3 个', 'Ең көбі 3',
                                            'Не больше 3'));
                                })),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        tr3(
                            '想盖的时候，在房子页点“准备开建？”就能找人，点评都会保留。',
                            'Кейін «Салуға дайынсыз ба?» басыңыз.',
                            'Когда решите строить — нажмите «Готовы строить?».'),
                        style: TextStyle(color: t.muted, fontSize: YFont.caption)),
                  ],
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
                          onTap: () => setState(() =>
                              tags.contains(c) ? tags.remove(c) : tags.add(c))),
                  ]),
                  const SizedBox(height: 40),
                ])));
  }
}

class _IntentCard extends StatelessWidget {
  const _IntentCard(
      {super.key,
      required this.selected,
      required this.icon,
      required this.title,
      required this.body,
      required this.onTap});
  final bool selected;
  final IconData icon;
  final String title, body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Material(
        color: selected ? t.accent.withValues(alpha: 0.08) : t.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(yRadius),
            side: BorderSide(
                color: selected ? t.accent : t.line, width: selected ? 2 : 1)),
        child: InkWell(
            borderRadius: BorderRadius.circular(yRadius),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: selected ? t.accent : t.muted),
                      const SizedBox(height: 6),
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(body,
                          style: TextStyle(color: t.muted, fontSize: YFont.caption)),
                    ]))));
  }
}
