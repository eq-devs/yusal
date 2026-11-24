import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps lib/ feature-first: main.dart and app.dart at the root,
/// then constant/, localization/, service/, utils/ and features/.
void main() {
  test('only the known top-level folders and files', () {
    final entries = {
      for (final e in Directory('lib').listSync()) e.path.split('/').last
    };
    expect(entries, {
      'main.dart',
      'app.dart',
      'firebase_options.dart',
      'constant',
      'localization',
      'service',
      'utils',
      'features',
    });
  });

  test('every feature folder uses the known sub-folders', () {
    const allowed = {
      'pages', 'widgets', 'state', 'repository', 'model', 'util',
      // The design tool: its library parts and the house engine.
      'tabs', 'tools', 'engine',
      // features/shared
      'ui', 'motion', 'brand',
      // features/voice: what the assistant can do.
      'actions',
    };
    final odd = <String>[];
    for (final feature in Directory('lib/features').listSync()) {
      if (feature is! Directory) continue;
      for (final sub in feature.listSync().whereType<Directory>()) {
        final name = sub.path.split('/').last;
        if (!allowed.contains(name)) odd.add(sub.path);
      }
    }
    expect(odd, isEmpty);
  });

  test('main.dart stays a bootstrap', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(
        RegExp(r'class \w+ extends (StatelessWidget|StatefulWidget)')
            .hasMatch(main),
        isFalse);
  });
}
