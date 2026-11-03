import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../domain/models.dart';
import 'l10n.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

IconData demandIcon(Demand d) => d.type == DemandType.hire
    ? Icons.engineering_outlined
    : Icons.home_work_outlined;

Color demandStatusColor(YTokens t, DemandStatus s) => switch (s) {
      DemandStatus.open => t.ok,
      DemandStatus.pendingReview || DemandStatus.draft => t.muted,
      DemandStatus.rejected => t.crit,
      DemandStatus.found => t.info,
      _ => t.muted,
    };

/// Listing-style card of a demand.
class DemandCard extends StatelessWidget {
  const DemandCard(
      {super.key,
      required this.demand,
      required this.onTap,
      this.favourite,
      this.onFavourite,
      this.compact = false,
      this.trailing});
  final Demand demand;
  final VoidCallback onTap;
  final bool? favourite;
  final VoidCallback? onFavourite;
  final bool compact;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final v = demand.current;
    final start = v.startDate == null
        ? tr3('开工待协商', 'Басталуы келісіледі', 'Старт по договорённости')
        : tr3('${fmtDay(v.startDate)} 开工', '${fmtDay(v.startDate)} басталады',
            'Старт ${fmtDay(v.startDate)}');
    final headcount = v.hire == null
        ? ''
        : ' · ${tr3('${v.hire!.headcount} 人', '${v.hire!.headcount} адам', '${v.hire!.headcount} чел.')}';
    final info =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(v.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, height: 1.25))),
        if (demand.status != DemandStatus.open) ...[
          const SizedBox(width: 8),
          StatusPill(demandStatusName(demand.status),
              color: demandStatusColor(t, demand.status)),
        ],
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 3),
      Text(
          '${regionName(v.region)}${v.locality.isEmpty ? '' : ' · ${v.locality}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.muted, fontSize: 14)),
      Text('${v.trades.map(tradeName).join('、')}$headcount',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.muted, fontSize: 14)),
      const SizedBox(height: 6),
      Text.rich(TextSpan(children: [
        TextSpan(
            text: budgetText(v.budget),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        TextSpan(
            text: '  ·  $start',
            style: TextStyle(color: t.muted, fontSize: 13)),
      ])),
    ]);
    if (compact) return YCard(onTap: onTap, child: info);
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(yRadius),
        child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Cover(
                  icon: demandIcon(demand),
                  seed: demand.id,
                  height: 150,
                  child: Stack(children: [
                    Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: t.softShadow),
                            child: Text(demandTypeName(demand.type),
                                style: const TextStyle(
                                    color: Color(0xff222222),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)))),
                    if (v.snapshotId != null)
                      Positioned(
                          left: 12,
                          bottom: 12,
                          child: StatusPill(
                              tr3('附设计工程量', 'Жоба көлемімен',
                                  'С объёмами из проекта'),
                              color: const Color(0xff222222),
                              filled: true)),
                    if (onFavourite != null)
                      Positioned(
                          right: 4,
                          top: 4,
                          child: IconButton(
                              tooltip: tr3('收藏', 'Таңдаулы', 'В избранное'),
                              onPressed: onFavourite,
                              icon: Icon(
                                  favourite == true
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: favourite == true
                                      ? t.accent
                                      : Colors.white,
                                  shadows: const [
                                    Shadow(blurRadius: 6, color: Colors.black38)
                                  ]))),
                  ])),
              const SizedBox(height: 10),
              info,
            ])));
  }
}

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
                              fontSize: 16, fontWeight: FontWeight.w700))),
                  StatusPill(profileKindName(p.kind)),
                ]),
                const SizedBox(height: 3),
                Text(p.trades.map(tradeName).join('、'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted)),
                Text(p.regions.map(regionName).join('、'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.circle,
                      size: 9, color: available ? t.ok : t.faint),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(availabilityName(p),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600))),
                  if (stale) ...[
                    const SizedBox(width: 6),
                    Text(
                        tr3('· 较久未确认', '· ұзақ расталмаған',
                            '· давно не обновлял'),
                        style: TextStyle(fontSize: 12, color: t.muted)),
                  ],
                ]),
                if (p.refPrices.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                      '${money(p.refPrices.first.amount, unit: p.refPrices.first.unit)} ${tr3('起', 'бастап', 'от')} · ${p.refPrices.first.scope}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ],
              ])),
        ]));
  }
}
