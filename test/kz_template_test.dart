import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/analysis/house_analysis.dart';
import 'package:yusal/core/checks/check_engine.dart';
import 'package:yusal/core/checks/construction_checks.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/render3d/scene_model.dart';

void main() {
  var n = 0;
  HouseDocument build() => createKazakhTemplate(
      '2026-10-14T00:00:00Z', () => 'kz${n++}',
      names: const {'b1': '卧室 1', 'b2': '卧室 2', 'cor': '走廊'});

  test('the drafting-page house is a valid, editable version 3 design', () {
    final doc = build();
    expect(validateHouse(doc), isEmpty);
    expect(doc.schemaVersion, 3);
    expect(doc.footprint.width, 10000);
    expect(doc.footprint.depth, 13000);
    final floor = doc.floors.first;
    expect(floor.rooms, hasLength(8));
    expect(floor.rooms.map((r) => r.name), containsAll(['卧室 1', '卧室 2', '走廊']));
    expect(floor.openings, hasLength(15));
    expect(doc.mainEntranceOpeningId, isNotNull);
    expect(doc.extras.furniture.length, greaterThan(35));
    expect(doc.extras.sleeves, hasLength(4));
    final loaded = loadHouse(utf8.encode(encodeHouse(doc)));
    expect(loaded.document, doc);
    final derived = deriveHouse(doc);
    expect(derived.floors.first.openings.every((p) => p.status == 'ok'), true,
        reason: derived.floors.first.openings
            .where((p) => p.status != 'ok')
            .map((p) => p.status)
            .join());
  });

  test('walls, foundation, checks and the 3D scene follow the layout', () {
    final doc = build();
    final derived = deriveHouse(doc);
    final walls = wallsOf(derived.floors.first.base, doc.extras.foundation);
    expect(walls.where((w) => w.role == WallRole.bearing), isNotEmpty,
        reason: 'the 400 mm spine carries the roof');
    expect(walls.where((w) => w.role == WallRole.partition), isNotEmpty);
    final takeoff = foundationTakeoff(doc, derived);
    // Exterior perimeter on centrelines (~42.4 m) plus the 13 m spine.
    expect(takeoff.mainLength / 1000, inInclusiveRange(50, 58));
    expect(takeoff.concrete / 1e9, inInclusiveRange(17, 22));
    final issues = constructionChecks(doc, derived);
    expect(issues.map((i) => i.code), containsAll(['C01', 'C02', 'C03', 'C05']));
    expect(issues.map((i) => i.code), contains('C07'),
        reason: 'bedroom 1 opens onto the living room');
    expect(runChecks(doc, derived).where((r) => r.level == 'important'),
        isEmpty);
    final scene = buildScene(doc, derived,
        const SceneOptions(foundation: true), (r) => r.name);
    expect(scene.faces.length, greaterThan(500));
    expect(scene.lines, isNotEmpty);
    expect(scene.colliders, isNotEmpty);
    expect(scene.labels, hasLength(8));
  });
}
