import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the feature-first layers apart: features build on the shared
/// layers, never the other way round. Only the app root (`main.dart`,
/// `lib/app/house_app.dart`) and the voice assistant, which drives every
/// screen, wire features together.
void main() {
  const lower = [
    'shared',
    'domain',
    'data',
    'services',
    'core',
    'storage',
    'render2d',
    'render3d',
  ];
  final import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

  for (final layer in lower) {
    test('lib/$layer does not import a feature', () {
      final offenders = <String>[];
      final dir = Directory('lib/$layer');
      expect(dir.existsSync(), isTrue, reason: 'lib/$layer is missing');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final (i, line) in f.readAsLinesSync().indexed) {
          final uri = import.firstMatch(line)?.group(1);
          if (uri == null) continue;
          if (uri.contains('features/')) offenders.add('${f.path}:${i + 1} $uri');
        }
      }
      expect(offenders, isEmpty);
    });
  }

  test('main.dart stays a bootstrap', () {
    // Startup steps and runApp only; widgets belong in lib/app/.
    final main = File('lib/main.dart').readAsStringSync();
    expect(RegExp(r'class \w+ extends (StatelessWidget|StatefulWidget)')
        .hasMatch(main), isFalse);
    expect(main.contains('showPerformanceOverlay'), isFalse);
  });
}
