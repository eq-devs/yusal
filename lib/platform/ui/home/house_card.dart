import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// A house in the feed: the plan as a big picture, then the facts a
/// visitor scans first (where, how big, what it costs) and who made it.
class HouseCard extends StatelessWidget {
  const HouseCard(
      {super.key,
      required this.post,
      required this.onTap,
      this.liked = false,
      this.onLike,
      this.compact = false});
  final HousePost post;
  final VoidCallback onTap;
  final bool liked, compact;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = post;
    final image =
        p.preview == null ? null : MemoryImage(Uint8List.fromList(p.preview!));
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(yRadius),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Cover(
                icon: Icons.home_outlined,
                seed: p.id,
                height: compact ? 150 : 230,
                image: image),
            if (onLike != null)
              Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                      color: t.card.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onLike,
                          child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                  liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 20,
                                  color: liked ? t.accent : t.ink))))),
            if (p.openForBuilders)
              Positioned(
                  left: 10,
                  top: 10,
                  child: StatusPill(
                      tr3('正在找施工方', 'Құрылысшы іздейді', 'Ищет строителей'),
                      color: t.accent,
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
                  style: TextStyle(fontSize: 14, color: t.ink)),
            ],
          ]),
          const SizedBox(height: 2),
          Text(houseFacts(p), style: TextStyle(color: t.muted, fontSize: 14)),
          if (p.estimatedCost != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: RichText(
                    text: TextSpan(
                        style: TextStyle(color: t.ink, fontSize: 14),
                        children: [
                      TextSpan(
                          text: '≈ ${money(p.estimatedCost)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text:
                              ' ${tr3('预估造价', 'болжамды құн', 'оценка стоимости')}',
                          style: TextStyle(color: t.muted)),
                    ]))),
          if (!compact)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Live<Account?>(
                    load: (r) => r.account(p.ownerId),
                    loading: const SizedBox(height: 24),
                    builder: (context, a) => Row(children: [
                          Avatar(a?.displayName ?? '', size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  a == null ? deletedName(null) : a.displayName,
                                  style:
                                      TextStyle(color: t.muted, fontSize: 13))),
                          Icon(Icons.favorite, size: 14, color: t.faint),
                          const SizedBox(width: 3),
                          Text('${p.likeCount}',
                              style: TextStyle(color: t.muted, fontSize: 13)),
                          const SizedBox(width: 10),
                          Icon(Icons.chat_bubble_outline,
                              size: 14, color: t.faint),
                          const SizedBox(width: 3),
                          Text('${p.commentCount}',
                              style: TextStyle(color: t.muted, fontSize: 13)),
                        ]))),
        ]));
  }
}

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
