import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/axis/axis_resolver.dart';
import 'package:yusal/core/canonicalization/room_canonicalizer.dart';
import 'package:yusal/core/serialization/house_codec.dart';

void main() {
  test('minimal house loads and encodes stably', () {
    final bytes = File('test/fixtures/minimal_flat.house').readAsBytesSync();
    final result = loadHouse(bytes);
    expect(result.isSuccess, isTrue);
    expect(utf8.encode(encodeHouse(result.document!)), bytes);
  });

  test('resolved boundary axes produce the expected single cell', () {
    final bytes = File('test/fixtures/minimal_flat.house').readAsBytesSync();
    final doc = loadHouse(bytes).document!;
    final axes = resolveFloorAxes(doc, 'f1')!;
    expect((axes.nx, axes.ny), (1, 1));
    expect(
      canonicalizeRegions(axes, doc.floors.first.rooms.first.regions).regions,
      doc.floors.first.rooms.first.regions,
    );
  });
}
