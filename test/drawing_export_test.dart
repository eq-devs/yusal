import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/analysis/utility_plan.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/features/drawing_export.dart';

void main() {
  var n = 0;
  String next() => 'dx${n++}';
  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(extractDesignState(doc),
        DesignCommand(kind, args), CommandContext(newId: next, now: () => 'x'));
    expect(result, isA<Applied>(),
        reason: result is Rejected ? result.message : kind);
    return composeDocument(doc.meta, (result as Applied).newState);
  }

  DrawingInput input(HouseDocument doc) => DrawingInput(
      doc: doc,
      derived: deriveHouse(doc),
      roomName: (r) => r.name,
      floorName: (s) => s,
      openingLabel: (p, f) => p.opening.id,
      date: '2026-10-19');

  test('the set grows with the design: utilities and plot add sheets', () {
    var doc = createKazakhTemplate('2026-10-19T00:00:00Z', next);
    final plain = drawingSheetTitles(input(doc));
    expect(plain, hasLength(8));
    final spots = suggestUtilities(doc, deriveHouse(doc), 0);
    doc = run(doc, 'AddUtilities', {
      'floorId': doc.floors.first.id,
      'points': [
        for (final s in spots) {'kind': s.kind, 'x': s.x, 'y': s.y}
      ]
    });
    doc = run(doc, 'SetSite', {});
    final full = drawingSheetTitles(input(doc));
    expect(full, hasLength(10));
    expect(full.toSet().length, full.length);
  });

  testWidgets('the PDF has one page per sheet and a PNG plan comes out',
      (tester) async {
    await tester.runAsync(() async {
      var doc = createKazakhTemplate('2026-10-19T00:00:00Z', next);
      doc = run(doc, 'SetSite', {});
      final pdf = await buildDrawingPdf(input(doc));
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      final text = latin1.decode(pdf);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length,
          drawingSheetTitles(input(doc)).length);
      final png = await buildPlanPng(input(doc), 0);
      expect(png.sublist(1, 4), [0x50, 0x4E, 0x47]);
    });
  });
}
