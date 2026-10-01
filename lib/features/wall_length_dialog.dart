import 'package:flutter/material.dart';

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
      setState(() => error = '请输入 0.30 到 100 米');
      return;
    }
    Navigator.pop(
        context, (length: (meters * 1000).round(), direction: direction));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('从 ➕ 起点增加墙'),
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
                        InputDecoration(labelText: '墙长（米）', errorText: error),
                    onSubmitted: (_) => submit()),
                const SizedBox(height: 16),
                const Text('方向'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final item in {
                    'right': '向右',
                    'up': '向上',
                    'left': '向左',
                    'down': '向下'
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
                child: const Text('取消')),
            FilledButton(onPressed: submit, child: const Text('增加墙'))
          ]);
}
