import 'package:flutter/widgets.dart';

import 'package:yusal/features/voice/model/action.dart';

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
