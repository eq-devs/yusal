import 'package:flutter/material.dart';
import '../app/settings.dart';

typedef WallLengthChoice = ({int length, String direction});

class WallLengthDialog extends StatefulWidget {
  const WallLengthDialog({super.key});
  @override
  State<WallLengthDialog> createState() => _WallLengthDialogState();
}

class _WallLengthDialogState extends State<WallLengthDialog> {
  final controller = TextEditingController(text: '2.00');
  String direction = 'right';
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final meters = double.tryParse(controller.text);
    if (meters == null || !meters.isFinite || meters < 0.3 || meters > 100) {
      setState(() => error = tr('请输入 0.30 到 100 米', '0,30–100 м аралығында енгізіңіз'));
      return;
    }
    Navigator.pop(
        context, (length: (meters * 1000).round(), direction: direction));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(tr('从起点输入墙长', 'Бастаудан қабырға ұзындығы')),
          scrollable: true,
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(
                            labelText: tr('墙长（米）', 'Қабырға ұзындығы (м)'),
                            errorText: error),
                    onSubmitted: (_) => submit()),
                const SizedBox(height: 16),
                Text(tr('方向', 'Бағыты')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final item in {
                    'right': tr('向右', 'Оңға'),
                    'up': tr('向上', 'Жоғары'),
                    'left': tr('向左', 'Солға'),
                    'down': tr('向下', 'Төмен')
                  }.entries)
                    ChoiceChip(
                        label: Text(item.value),
                        selected: direction == item.key,
                        onSelected: (_) => setState(() => direction = item.key))
                ])
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('取消', 'Болдырмау'))),
            FilledButton(
                onPressed: submit, child: Text(tr('增加墙', 'Қабырға қосу')))
          ]);
}

/// Wall thickness with the brick sizes self-builders already use
/// (12 墙 / 18 墙 / 24 墙 / 37 墙, i.e. 120–370 mm) one tap away, plus a
/// free value.
class WallThicknessDialog extends StatefulWidget {
  const WallThicknessDialog({super.key, required this.initial});
  final int initial;
  @override
  State<WallThicknessDialog> createState() => _WallThicknessDialogState();
}

class _WallThicknessDialogState extends State<WallThicknessDialog> {
  late final controller =
      TextEditingController(text: (widget.initial / 1000).toStringAsFixed(2));
  String? error;
  static const presets = {120: '12 墙', 180: '18 墙', 240: '24 墙', 370: '37 墙'};
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final meters = double.tryParse(controller.text);
    if (meters == null || !meters.isFinite || meters < 0.05 || meters > 1) {
      setState(() => error = tr('请输入 0.05 到 1.00 米', '0,05–1,00 м аралығында енгізіңіз'));
      return;
    }
    Navigator.pop(context, (meters * 1000).round());
  }

  @override
  Widget build(BuildContext context) {
    final current = ((double.tryParse(controller.text) ?? 0) * 1000).round();
    return AlertDialog(
        title: Text(tr('墙厚', 'Қабырға қалыңдығы')),
        scrollable: true,
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final entry in presets.entries)
                  ChoiceChip(
                      label: Text(isKk
                          ? '${entry.key} мм'
                          : '${entry.value} · ${(entry.key / 1000).toStringAsFixed(2)} 米'),
                      selected: current == entry.key,
                      onSelected: (_) => setState(() => controller.text =
                          (entry.key / 1000).toStringAsFixed(2)))
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(
                          labelText: tr('墙厚（米）', 'Қабырға қалыңдығы (м)'),
                          errorText: error),
                  onChanged: (_) => setState(() => error = null),
                  onSubmitted: (_) => submit()),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('取消', 'Болдырмау'))),
          FilledButton(onPressed: submit, child: Text(tr('确定', 'Жарайды')))
        ]);
  }
}
