import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Where a house stands on the one line every role sees:
/// design → finding people → building → done.
enum HouseStage { design, finding, building, done }

/// Public stage from the house's demands: any open demand means "finding";
/// a demand marked found means building has started.
HouseStage stageFromDemands(Iterable<Demand> demands) {
  if (demands.any((d) => d.status == DemandStatus.found)) {
    return HouseStage.building;
  }
  if (demands.any((d) =>
      d.status == DemandStatus.open ||
      d.status == DemandStatus.paused ||
      d.status == DemandStatus.pendingReview)) {
    return HouseStage.finding;
  }
  return HouseStage.design;
}

String houseStageName(HouseStage s) => switch (s) {
      HouseStage.design => tr3('设计', 'Жоба', 'Проект', 'Project', ky: 'Долбоор', uz: 'Loyiha'),
      HouseStage.finding => tr3('找人', 'Іздеу', 'Поиск', 'Search', ky: 'Издөө', uz: 'Qidiruv'),
      HouseStage.building => tr3('施工', 'Құрылыс', 'Стройка', 'Build', ky: 'Курулуш', uz: 'Qurilish'),
      HouseStage.done => tr3('完工', 'Аяқталды', 'Готово', 'Done', ky: 'Даяр', uz: 'Tayyor'),
    };

/// "● 设计 ─ ● 找人中 ─ ○ 施工 ─ ○ 完工"
class HouseProgress extends StatelessWidget {
  const HouseProgress({super.key, required this.stage, this.onTap});
  final HouseStage stage;

  /// Tapping a step, e.g. to jump to that tab of the workspace.
  final void Function(HouseStage)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    const steps = HouseStage.values;
    return Semantics(
        label: '${tr3('进度', 'Барысы', 'Этап', 'Stage', ky: 'Этап', uz: 'Bosqich')}: ${houseStageName(stage)}',
        child: Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                  child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: i <= stage.index ? t.accent : t.line)),
            InkWell(
                onTap: onTap == null ? null : () => onTap!(steps[i]),
                borderRadius: BorderRadius.circular(YRadius.row),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          i < stage.index
                              ? YIcons.checkCircle
                              : i == stage.index
                                  ? YIcons.radioOn
                                  : YIcons.radioOff,
                          size: 18,
                          color: i <= stage.index ? t.accent : t.faint),
                      const SizedBox(height: 2),
                      Text(houseStageName(steps[i]),
                          style: TextStyle(
                              fontSize: YFont.caption,
                              fontWeight: i == stage.index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i <= stage.index ? t.ink : t.muted)),
                    ]))),
          ],
        ]));
  }
}
