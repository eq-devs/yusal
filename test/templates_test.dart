import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/checks/check_engine.dart';

void main() {
  for (final kind in houseTemplates.keys) {
    test('$kind template is valid and renders without invalid openings', () {
      var sequence = 0;
      final doc =
          createTemplate(kind, '2026-09-30T00:00:00Z', () => 'id${sequence++}');
      expect(validateHouse(doc), isEmpty);
      expect(loadHouse(utf8.encode(encodeHouse(doc))).document, doc);
      final derived = deriveHouse(doc);
      expect(derived.scene3d, isNotEmpty);
      expect(
          derived.floors
              .expand((f) => f.openings)
              .every((p) => p.status == 'ok'),
          isTrue);
      expect(runChecks(doc, derived).where((r) => r.level == 'important'),
          isEmpty);
    });
  }
}
