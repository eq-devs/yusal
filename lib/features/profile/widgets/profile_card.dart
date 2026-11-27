import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/profile/state/profile.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Card of a worker or team profile.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.profile, required this.onTap});
  final ServiceProfile profile;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = profile;
    final available = p.availableOn(context.now);
    final stale = context.now.difference(p.availabilityConfirmedAt).inDays > 14;
    return YCard(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(p.name, size: 52, team: p.kind == ProfileKind.team),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: YFont.body,
                              fontWeight: FontWeight.w700))),
                  if (p.verified) ...[
                    const SizedBox(width: 6),
                    const VerifiedBadge(),
                  ],
                ]),
                const SizedBox(height: 3),
                // The kind leads the trades line: as a pill beside the
                // name it left a long name only a few letters.
                Text(
                    '${profileKindName(p.kind)} · '
                    '${p.trades.map(tradeName).join(listSep)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted)),
                Text(p.regions.map(regionName).join(listSep),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: YFont.small)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.circle,
                      size: 9, color: available ? t.ok : t.faint),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(availabilityName(p),
                          style: const TextStyle(
                              fontSize: YFont.small,
                              fontWeight: FontWeight.w600))),
                  if (stale) ...[
                    const SizedBox(width: 6),
                    Text(
                        tr3('· 较久未确认', '· ұзақ расталмаған',
                            '· давно не обновлял',
                            '· not updated for a while', ky: '· бир топтон бери жаңыланган жок', uz: '· ancha vaqtdan beri yangilanmagan'),
                        style:
                            TextStyle(fontSize: YFont.caption, color: t.muted)),
                  ],
                ]),
                _TrackRecord(profile: p),
                if (p.refPrices.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                      '${money(p.refPrices.first.amount, unit: p.refPrices.first.unit)} ${tr3('起', 'бастап', 'от', 'from', ky: 'кеминде', uz: 'kamida')} · ${p.refPrices.first.scope}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: YFont.small)),
                ],
              ])),
        ]));
  }
}

/// What a pro has shown on Yusal: average rating from reviews about them,
/// and how many works, of which how many came from jobs on the platform.
/// Nothing is shown for a pro with no record yet.
class _TrackRecord extends StatelessWidget {
  const _TrackRecord({required this.profile});
  final ServiceProfile profile;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = profile;
    final onPlatform =
        p.works.where((w) => w.source == WorkSource.platform).length;
    return Live<List<Review>>(
        provider: reviewsAboutProvider(p.ownerId),
        loading: const SizedBox.shrink(),
        builder: (context, reviews) {
          final scores = [
            for (final r in reviews)
              if (r.scores.isNotEmpty)
                r.scores.values.reduce((a, b) => a + b) / r.scores.length
          ];
          final parts = [
            if (p.works.isNotEmpty)
              tr3('${p.works.length} 个作品', '${p.works.length} жұмыс',
                  'Работ: ${p.works.length}',
                  'Jobs: ${p.works.length}', ky: 'Иштер: ${p.works.length}', uz: 'Ishlar: ${p.works.length}'),
            if (onPlatform > 0)
              tr3('$onPlatform 个平台合作', 'Платформада: $onPlatform',
                  'На платформе: $onPlatform',
                  'On the platform: $onPlatform', ky: 'Платформада: $onPlatform', uz: 'Platformada: $onPlatform'),
          ];
          if (scores.isEmpty && parts.isEmpty) return const SizedBox.shrink();
          return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                if (scores.isNotEmpty) ...[
                  Icon(YIcons.starFill, size: 15, color: t.ink),
                  const SizedBox(width: 3),
                  Text(
                      '${(scores.reduce((a, b) => a + b) / scores.length).toStringAsFixed(1)} (${scores.length})',
                      style: const TextStyle(
                          fontSize: YFont.small,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  if (parts.isNotEmpty) const SizedBox(width: 8),
                ],
                Flexible(
                    child: Text(parts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: YFont.small, color: t.muted))),
              ]));
        });
  }
}
