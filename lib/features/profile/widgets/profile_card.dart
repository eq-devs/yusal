import 'package:flutter/material.dart';
import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/shared/l10n/l10n.dart';
import 'package:yusal/features/profile/state/profile.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/shared/theme/theme.dart';
import 'package:yusal/shared/ui/widgets.dart';

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
                  Expanded(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: YFont.body,
                              fontWeight: FontWeight.w700))),
                  if (p.verified) ...[
                    const VerifiedBadge(),
                    const SizedBox(width: 6),
                  ],
                  StatusPill(profileKindName(p.kind)),
                ]),
                const SizedBox(height: 3),
                Text(p.trades.map(tradeName).join(listSep),
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
                            '· давно не обновлял'),
                        style:
                            TextStyle(fontSize: YFont.caption, color: t.muted)),
                  ],
                ]),
                _TrackRecord(profile: p),
                if (p.refPrices.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                      '${money(p.refPrices.first.amount, unit: p.refPrices.first.unit)} ${tr3('起', 'бастап', 'от')} · ${p.refPrices.first.scope}',
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
                  'Работ: ${p.works.length}'),
            if (onPlatform > 0)
              tr3('$onPlatform 个平台合作', 'Платформада: $onPlatform',
                  'На платформе: $onPlatform'),
          ];
          if (scores.isEmpty && parts.isEmpty) return const SizedBox.shrink();
          return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                if (scores.isNotEmpty) ...[
                  Icon(Icons.star, size: 15, color: t.ink),
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
