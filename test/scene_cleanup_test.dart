import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/house_templates.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render3d/scene_cleanup.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';

import 'perf/engine_bench.dart';
import 'support/scene_cleanup_reference.dart';

/// Everything the painter reads of a face, as text.
String describe(Face3 f) => [
      f.points.map((p) => '${p.x},${p.y},${p.z}').join(' '),
      '${f.normal.x},${f.normal.y},${f.normal.z}',
      f.color,
      f.alpha,
      f.layer,
      f.source,
      f.doubleSided,
      f.glow,
      f.roof,
      f.furniture,
      f.floorIndex,
      f.castsShadow,
      f.interior,
      f.covering,
      f.textile,
      f.textileVariant,
      f.uv,
      f.capOnly,
      f.enclosed,
    ].join(' | ');

void main() {
  var n = 0;
  String id() => 'id${n++}';
  final houses = <String, HouseDocument>{
    'gable': loadHouse(
            File('test/fixtures/full_two_floor_gable.house').readAsBytesSync())
        .document!,
    'kz': createKazakhTemplate('2026-10-14T00:00:00Z', id),
    'two': createTemplate('two', '2026-10-14T00:00:00Z', id),
    'five': createTemplate('five', '2026-10-14T00:00:00Z', id),
    'typical': composeDocument(benchMeta, typicalPlan()),
    'large': composeDocument(benchMeta, largePlan()),
  };
  const options = <String, SceneOptions>{
    'full': SceneOptions(),
    'no roof': SceneOptions(roof: false),
    'foundation': SceneOptions(foundation: true),
    'walk': SceneOptions(walk: true),
    'ground floor': SceneOptions(maxFloor: 0),
  };
  tearDown(() => sceneCleanup = cleanFaces);

  for (final house in houses.entries) {
    test('${house.key}: the cleanup gives the faces the first one gave', () {
      final doc = house.value;
      final derived = deriveHouse(doc);
      for (final option in options.entries) {
        sceneCleanup = referenceCleanFaces;
        final before =
            buildScene(doc, derived, option.value, (r) => r.name).faces;
        sceneCleanup = cleanFaces;
        final after =
            buildScene(doc, derived, option.value, (r) => r.name).faces;
        expect(after.length, before.length, reason: option.key);
        expect(after.map(describe).toList(), before.map(describe).toList(),
            reason: option.key);
        expect(after, isNotEmpty);
      }
    });
  }
}
