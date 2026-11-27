import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/document/extras_planning.dart';
import 'package:yusal/features/editor/repository/price_repository.dart';

void main() {
  // yusal-api writes docs/price_keys.json from pricing.go and fails its
  // tests when it is stale; this repo's docs/ holds a copy.
  final doc = jsonDecode(File('docs/price_keys.json').readAsStringSync())
      as Map<String, dynamic>;

  test('the server keeps prices for the regions the app offers', () {
    expect(doc['regions'], priceRegions);
  });

  test('the server keeps prices in the currencies the app estimates in', () {
    expect((doc['currencies'] as List).toSet(),
        {for (final c in Currency.values) c.name});
  });

  test('every line the app estimates can be priced on the server', () {
    // Masonry other than aerated blocks is priced under masonry_<unit>.
    final lines = {
      for (final c in Currency.values) ...defaultPrices[c]!.keys,
      for (final u in MasonryUnit.values)
        if (u != MasonryUnit.aerated) 'masonry_${u.name}',
    };
    expect((doc['keys'] as List).toSet(), lines);
  });
}
