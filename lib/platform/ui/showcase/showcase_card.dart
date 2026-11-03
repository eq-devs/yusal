import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../theme.dart';
import 'plan_thumb.dart';

/// "12 × 10 m · 2 floors · 186 m²".
String showcaseSize(Showcase s) {
  String m(int mm) => numText(mm / 1000);
  return tr3(
      '${m(s.width)}×${m(s.depth)} 米 · ${s.floors} 层 · ${s.area.toStringAsFixed(0)} ㎡',
      '${m(s.width)}×${m(s.depth)} м · ${s.floors} қабат · ${s.area.toStringAsFixed(0)} м²',
      '${m(s.width)}×${m(s.depth)} м · ${s.floors} эт. · ${s.area.toStringAsFixed(0)} м²');
}

/// Round heart over a picture, like a listing's "save".
class HeartButton extends StatelessWidget {
  const HeartButton({super.key, required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Semantics(
        button: true,
        label: tr3('点赞', 'Ұнату', 'Нравится'),
        child: InkResponse(
            onTap: onTap,
            radius: 24,
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(on ? Icons.favorite : Icons.favorite_border,
                    size: 26,
                    color: on ? t.accent : Colors.white,
                    shadows: const [
                      Shadow(color: Color(0x66000000), blurRadius: 6)
                    ]))));
  }
}

/// Small solid label over a picture.
class PhotoBadge extends StatelessWidget {
  const PhotoBadge(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(999),
            boxShadow: t.softShadow),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: t.accent),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: t.ink)),
        ]));
  }
}

/// Listing-style card of a published house design.
class ShowcaseCard extends StatelessWidget {
  const ShowcaseCard(
      {super.key,
      required this.showcase,
      required this.ownerName,
      required this.liked,
      required this.onLike,
      required this.onTap});
  final Showcase showcase;
  final String ownerName;
  final bool liked;
  final VoidCallback onLike, onTap;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final s = showcase;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(yRadius),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
              aspectRatio: 1.12,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(yRadius),
                  child: Stack(children: [
                    Positioned.fill(
                        child: Hero(
                            tag: 'plan-${s.id}',
                            child: PlanThumb(
                                cacheKey: s.id, houseText: s.houseText))),
                    if (s.hiring)
                      Positioned(
                          left: 10,
                          top: 10,
                          child: PhotoBadge(
                              tr3('招人中', 'Адам керек', 'Ищут мастеров'),
                              icon: Icons.handyman)),
                    Positioned(
                        right: 2,
                        top: 2,
                        child: HeartButton(on: liked, onTap: onLike)),
                  ]))),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700))),
            if (s.rating != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, size: 16, color: t.ink),
              Text(' ${s.rating!.toStringAsFixed(1)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ]),
          const SizedBox(height: 2),
          Text(showcaseSize(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.muted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
              '${regionName(s.region)} · $ownerName · ♥ ${s.likes} · ${tr3('${s.commentCount} 条评论', '${s.commentCount} пікір', '${s.commentCount} отз.')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.muted, fontSize: 13)),
        ]));
  }
}
