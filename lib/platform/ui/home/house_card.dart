import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/settings.dart';
import '../design/plan_viewer.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../../motion/motion.dart';

/// A house in the feed: the plan as a big picture, then the facts a
/// visitor scans first (where, how big, what it costs) and who made it.
class HouseCard extends StatelessWidget {
  const HouseCard(
      {super.key,
      required this.post,
      required this.onTap,
      this.liked = false,
      this.onLike,
      this.onReuse,
      this.compact = false});
  final HousePost post;
  final VoidCallback onTap;
  final bool liked, compact;

  /// Toggles the like; answers the new state, or null when it failed.
  final Future<bool?> Function()? onLike;

  /// "Start from this one": copies the plan into my houses.
  final VoidCallback? onReuse;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = post;
    return HeroTapArea(
        child: Pressable(
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(yRadius),
        splashFactory: NoSplash.splashFactory,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            HeroSource(
                heroKey: houseHeroKey(p.id),
                borderRadius: BorderRadius.circular(yRadius),
                child: PostPicture(
                    post: p,
                    builder: (context, image, loading) => Cover(
                        icon: Icons.home_outlined,
                        seed: p.id,
                        height: compact ? 150 : 230,
                        image: image,
                        child: image == null &&
                                !loading &&
                                p.snapshotId.isNotEmpty
                            ? PlanCover(snapshotId: p.snapshotId, postId: p.id)
                            : null))),
            if (onLike != null)
              Positioned(
                  top: 10,
                  right: 10,
                  child: OptimisticLike(
                      liked: liked,
                      toggle: onLike!,
                      builder: (context, liked, toggle) => Material(
                      color: t.card.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: toggle,
                          child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: PopOnActive(
                                  active: liked,
                                  child: Icon(
                                      liked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 20,
                                      color: liked ? t.accent : t.ink))))))),
            if (p.openForBuilders)
              Positioned(
                  left: 10,
                  top: 10,
                  child: StatusPill(
                      tr3('正在找施工方', 'Құрылысшы іздейді', 'Ищет строителей'),
                      color: t.accent,
                      filled: true))
            else if (p.focus.isNotEmpty)
              Positioned(
                  left: 10,
                  top: 10,
                  child: StatusPill(
                      tr3('求点评 · ${p.focus.map(feedbackTopicName).join('、')}',
                          'Пікір сұрайды', 'Просит отзывы'),
                      color: t.ink,
                      filled: true)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(
                        size: compact ? 16 : 18,
                        weight: FontWeight.w600,
                        color: t.ink))),
            if (p.rating != null) ...[
              Icon(Icons.star, size: 15, color: t.ink),
              const SizedBox(width: 3),
              Text(p.rating!.toStringAsFixed(1),
                  style: TextStyle(fontSize: YFont.label, color: t.ink)),
            ],
          ]),
          if (p.rating == null)
            Text(
                p.commentCount > 0
                    ? tr3('${p.commentCount} 条点评', '${p.commentCount} пікір',
                        'Отзывов: ${p.commentCount}')
                    : p.openForBuilders
                        ? tr3('暂无评价', 'Пікір жоқ', 'Нет оценок')
                        : tr3('等你来点评', 'Пікір қалдырыңыз', 'Оставьте отзыв'),
                style: TextStyle(fontSize: YFont.caption, color: t.muted)),
          const SizedBox(height: 2),
          Text(houseFacts(p), style: TextStyle(color: t.muted, fontSize: YFont.label)),
          if (p.estimatedCost != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                    TextSpan(
                        style: TextStyle(color: t.ink, fontSize: YFont.label),
                        children: [
                          TextSpan(
                              text: '≈ ${money(p.estimatedCost)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ])),
                          TextSpan(
                              text:
                                  ' ${tr3('预估造价', 'болжамды құн', 'оценка стоимости')}',
                              style: TextStyle(color: t.muted)),
                        ]),
                    // One line, so long labels (Russian) cannot push the
                    // card past a fixed-height list such as the Me tab.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          if (!compact)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Live<Account?>(
                    reloadKey: p.ownerId,
                    load: (r) => r.account(p.ownerId),
                    loading: const SizedBox(height: 24),
                    builder: (context, a) => Row(children: [
                          Avatar(a?.displayName ?? '', size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  a == null ? deletedName(null) : a.displayName,
                                  style:
                                      TextStyle(color: t.muted, fontSize: YFont.small))),
                          Icon(Icons.favorite, size: 14, color: t.faint),
                          const SizedBox(width: 3),
                          Text('${p.likeCount}',
                              style: TextStyle(color: t.muted, fontSize: YFont.small)),
                          const SizedBox(width: 10),
                          Icon(Icons.chat_bubble_outline,
                              size: 14, color: t.faint),
                          const SizedBox(width: 3),
                          Text('${p.commentCount}',
                              style: TextStyle(color: t.muted, fontSize: YFont.small)),
                        ]))),
          if (onReuse != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                          onPressed: onReuse,
                          style: OutlinedButton.styleFrom(
                              foregroundColor: t.accent,
                              side: BorderSide(color: t.accent),
                              visualDensity: VisualDensity.compact),
                          icon:
                              const Icon(Icons.content_copy_outlined, size: 16),
                          label: Text(startFromThis())),
                      if (p.reuseCount > 0)
                        Text(reusedTimes(p.reuseCount),
                            style: TextStyle(color: t.muted, fontSize: YFont.small)),
                    ])),
        ]))));
  }
}

/// A post's plan thumbnail: the one the post carries, or (for a post from
/// a feed, which leaves pictures out) fetched when this is first built.
/// [loading] is true only while that fetch runs.
class PostPicture extends StatefulWidget {
  const PostPicture({super.key, required this.post, required this.builder});
  final HousePost post;
  final Widget Function(BuildContext context, ImageProvider? image, bool loading)
      builder;
  @override
  State<PostPicture> createState() => _PostPictureState();
}

class _PostPictureState extends State<PostPicture> {
  ImageProvider? _image;
  bool _loading = false;
  String? _resolved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PostPicture old) {
    super.didUpdateWidget(old);
    if (old.post.id != widget.post.id ||
        !identical(old.post.preview, widget.post.preview)) {
      _resolved = null;
      _resolve();
    }
  }

  void _take(List<int>? bytes) {
    _image = bytes == null ? null : MemoryImage(imageBytes(bytes));
    _loading = false;
  }

  void _resolve() {
    final id = widget.post.id;
    if (_resolved == id) return;
    _resolved = id;
    final own = widget.post.preview;
    final found = own ?? context.repos.postPreview(id);
    if (found is! Future<List<int>?>) return _take(found);
    _image = null;
    _loading = true;
    found.then((bytes) {
      if (mounted && _resolved == id) setState(() => _take(bytes));
    }, onError: (Object _) {
      if (mounted && _resolved == id) setState(() => _take(null));
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _image, _loading);
}

/// Shared-element key of a house's cover, list card → house page.
String houseHeroKey(String postId) => 'house:$postId';

/// "塔尔加尔 · 130 m² · 一层 · 4 个房间"
String houseFacts(HousePost p) => [
      regionName(p.region),
      '${p.area.round()} m²',
      switch (p.floors) {
        1 => tr3('一层', 'Бір қабат', '1 этаж'),
        2 => tr3('两层', 'Екі қабат', '2 этажа'),
        final n => tr3('$n 层', '$n қабат', '$n этажа'),
      },
      if (p.rooms > 0)
        tr3('${p.rooms} 个房间', '${p.rooms} бөлме', '${p.rooms} комн.'),
    ].join(' · ');

/// The main action on a public design.
String startFromThis() => tr3('用这套开始', 'Осыдан бастау', 'Начать с этого');

/// "已被复用 23 次"
String reusedTimes(int n) =>
    tr3('已被复用 $n 次', '$n рет қолданылды', 'Взяли за основу: $n');

/// Shows a like at once and sends it after; goes back if the call fails,
/// and follows [liked] again once the page reloads with the server's view.
class OptimisticLike extends StatefulWidget {
  const OptimisticLike(
      {super.key, required this.liked, required this.toggle, required this.builder});
  final bool liked;
  final Future<bool?> Function() toggle;
  final Widget Function(BuildContext context, bool liked, VoidCallback toggle) builder;
  @override
  State<OptimisticLike> createState() => _OptimisticLikeState();
}

class _OptimisticLikeState extends State<OptimisticLike> {
  bool? _shown;
  bool _busy = false;

  @override
  void didUpdateWidget(OptimisticLike old) {
    super.didUpdateWidget(old);
    if (!_busy && widget.liked != old.liked) _shown = null;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final before = _shown ?? widget.liked;
    if (!before) HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _shown = !before;
    });
    final result = await widget.toggle();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _shown = result ?? before;
      if (_shown == widget.liked) _shown = null;
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _shown ?? widget.liked, _toggle);
}
