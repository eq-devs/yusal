import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/service/api/api_client.dart';

/// The values of [ApiCodes], read from its source so the list cannot drift.
Set<String> appCodes() {
  final src = File('lib/service/api/api_failure.dart').readAsStringSync();
  return {
    for (final m in RegExp(r"static const \w+ = '([A-Z_]+)';").allMatches(src))
      m.group(1)!
  };
}

void main() {
  // yusal-api writes docs/api_codes.json from its source and fails its
  // tests when it is stale; this repo's docs/ holds a copy.
  final server = Set<String>.from(
      (jsonDecode(File('docs/api_codes.json').readAsStringSync())
          as Map<String, dynamic>)['codes'] as List);
  final app = appCodes();

  test('every code the server answers with lands on one of ApiCodes', () {
    final unknown = [
      for (final code in server)
        if (!app.contains(ApiClient.mapCode(code))) code
    ];
    expect(unknown, isEmpty,
        reason: 'add these to ApiCodes or map them in ApiClient.mapCode');
  });

  test('ApiCodes holds only server codes and the two client-side ones', () {
    expect(app.difference(server), {'NOT_SIGNED_IN', 'NETWORK'});
  });
}
