import 'package:flutter/widgets.dart';

import 'action.dart';
import 'screen.dart';

enum FieldType { text, number, choice }

/// One input of a page that voice can fill. A page lists the ones it
/// shows in its contract; filling never submits.
class VoiceField {
  const VoiceField(this.name, this.label, this.type, this.write,
      {this.values = const []});

  /// Free text into [controller].
  VoiceField.text(String name, L3 label, TextEditingController controller)
      : this(name, label, FieldType.text, (v) => controller.text = v as String);

  /// A number into [controller], written the way a person types it:
  /// 15000, not 15000.0.
  VoiceField.number(String name, L3 label, TextEditingController controller)
      : this(name, label, FieldType.number, (v) {
          final n = v as num;
          controller.text = n == n.truncate() ? '${n.toInt()}' : '$n';
        });

  /// One of [values], handed to [select].
  VoiceField.choice(String name, L3 label, List<String> values,
      void Function(String value) select)
      : this(name, label, FieldType.choice, (v) => select(v as String),
            values: values);

  /// Lower-case name the language model uses: "wage".
  final String name;
  final L3 label;
  final FieldType type;
  final List<String> values;
  final void Function(Object value) write;

  bool accepts(Object? value) => switch (type) {
        FieldType.text => value is String,
        FieldType.number => value is num && value.isFinite,
        FieldType.choice => values.contains(value),
      };
}

/// Failure code when the page has nothing to send.
const nothingToSubmit = 'nothing_to_submit';

final formActions = [
  AppAction(
    id: 'form.fill',
    title: const L3('填写表单', 'Пішінді толтыру', 'Заполнить форму'),
    examples: const L3('找两个瓦工，日薪一万五', 'Екі қалаушы керек, күніне он бес мың',
        'Нужны два каменщика, пятнадцать тысяч в день'),
    params: const {'values': Param.fields()},
    when: (ctx) => VoiceScreens.current?.fields.isNotEmpty ?? false,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final fields = {
        for (final f in VoiceScreens.current?.fields ?? const <VoiceField>[])
          f.name: f
      };
      final values = args.fields('values');
      // All or nothing: one bad value and no field changes.
      for (final MapEntry(key: name, :value) in values.entries) {
        if (!(fields[name]?.accepts(value) ?? false)) {
          return ActionResult.fail(ActionCodes.badArgs, say: {'field': name});
        }
      }
      for (final MapEntry(key: name, :value) in values.entries) {
        fields[name]!.write(value!);
      }
      return ActionResult.ok(changed: [...values.keys]);
    },
  ),
  AppAction(
    id: 'form.submit',
    title: const L3('提交或发送', 'Жіберу', 'Отправить'),
    examples: const L3('发送', 'Жібер', 'Отправь'),
    when: (ctx) => VoiceScreens.current?.voiceSubmit != null,
    risk: Risk.outbound,
    run: (ctx, args) async {
      final submit = VoiceScreens.current?.voiceSubmit;
      if (submit == null) return const ActionResult.fail(nothingToSubmit);
      await submit();
      return const ActionResult.ok();
    },
  ),
];
