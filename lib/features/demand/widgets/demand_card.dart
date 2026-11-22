import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yusal/features/shared/motion/motion.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/home/widgets/plan_viewer.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';

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
                    fontSize: YFont.body,
                    fontWeight: FontWeight.w700,
                    height: 1.25))),
        if (demand.status != DemandStatus.open) ...[
          const SizedBox(width: 8),
          StatusPill(demandStatusName(demand.status),
              color: demandStatusColor(t, demand.status)),
        ],
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 3),
      Text(placeText(v.region, v.locality),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.muted, fontSize: YFont.label)),
      Text('${v.trades.map(tradeName).join(listSep)}$headcount',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.muted, fontSize: YFont.label)),
      if ((v.contract?.quantities.length ?? 0) > 0)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StatusPill(
                tr3(
                    '按清单报价 · ${v.contract!.quantities.length} 项',
                    'Тізім бойынша · ${v.contract!.quantities.length}',
                    'По смете · ${v.contract!.quantities.length} поз.'),
                color: t.accent)),
      const SizedBox(height: 6),
      Text.rich(TextSpan(children: [
        TextSpan(
            text: budgetText(v.budget),
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: YFont.body,
                fontFeatures: YText.tabular)),
        TextSpan(
            text: '  ·  $start',
            style: TextStyle(color: t.muted, fontSize: YFont.small)),
      ])),
    ]);
    if (compact) return YCard(onTap: onTap, child: info);
    final heart = onFavourite == null
        ? null
        : IconButton(
            tooltip: favourite == true
                ? tr3('取消收藏', 'Таңдаулыдан алу', 'Убрать из избранного')
                : tr3('收藏', 'Таңдаулы', 'В избранное'),
            onPressed: () {
              if (favourite != true) HapticFeedback.lightImpact();
              onFavourite!();
            },
            icon: PopOnActive(
                active: favourite == true,
                child: Icon(
                    favourite == true ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                    color: favourite == true ? t.accent : t.muted)));
    // The kind of demand leads the card; a drawing, when there is one, is
    // the only picture. Without a drawing the card is its facts.
    final kind = Row(children: [
      Icon(demandIcon(demand), size: 18, color: t.accent),
      const SizedBox(width: 6),
      Expanded(
          child: Text(demandTypeName(demand.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: YText.labelStrong.copyWith(color: t.accent))),
      if (heart != null) heart,
    ]);
    return Pressable(
        child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(YRadius.card),
                border: Border.all(color: t.line)),
            child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                    onTap: onTap,
                    splashFactory: NoSplash.splashFactory,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (v.snapshotId != null)
                            SizedBox(
                                height: 150,
                                child: Stack(children: [
                                  Positioned.fill(
                                      child: PlanCover(
                                          snapshotId: v.snapshotId!,
                                          demandId: demand.id)),
                                  Positioned(
                                      left: YSpace.md,
                                      bottom: YSpace.md,
                                      child: StatusPill(
                                          tr3('附设计工程量', 'Жоба көлемімен',
                                              'С объёмами из проекта'),
                                          color: YTokens.light.ink,
                                          filled: true)),
                                ])),
                          Padding(
                              padding: EdgeInsets.fromLTRB(
                                  YSpace.lg,
                                  heart == null ? YSpace.md : YSpace.xs,
                                  heart == null ? YSpace.lg : YSpace.xs,
                                  0),
                              child: kind),
                          Padding(
                              padding: EdgeInsets.fromLTRB(
                                  YSpace.lg,
                                  heart == null ? YSpace.sm : 0,
                                  YSpace.lg,
                                  YSpace.lg),
                              child: info),
                        ])))));
  }
}
