import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../domain/models.dart';
import 'theme.dart';

/// Where a house stands on the one line every role sees:
/// design → finding people → building → done.
enum HouseStage { design, finding, building, done }

/// Public stage from the house's demands: any open demand means "finding";
/// a demand marked found means building has started.
HouseStage stageFromDemands(Iterable<Demand> demands) {
  if (demands.any((d) => d.status == DemandStatus.found))
    return HouseStage.building;
  if (demands.any((d) =>
      d.status == DemandStatus.open ||
      d.status == DemandStatus.paused ||
      d.status == DemandStatus.pendingReview)) return HouseStage.finding;
  return HouseStage.design;
}

String houseStageName(HouseStage s) => switch (s) {
      HouseStage.design => tr3('设计', 'Жоба', 'Проект'),
      HouseStage.finding => tr3('找人', 'Іздеу', 'Поиск'),
      HouseStage.building => tr3('施工', 'Құрылыс', 'Стройка'),
      HouseStage.done => tr3('完工', 'Аяқталды', 'Готово'),
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
    final steps = HouseStage.values;
    return Semantics(
        label: '${tr3('进度', 'Барысы', 'Этап')}: ${houseStageName(stage)}',
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
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          i < stage.index
                              ? Icons.check_circle
                              : i == stage.index
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                          size: 18,
                          color: i <= stage.index ? t.accent : t.faint),
                      const SizedBox(height: 2),
                      Text(houseStageName(steps[i]),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == stage.index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i <= stage.index ? t.ink : t.muted)),
                    ]))),
          ],
        ]));
  }
}
