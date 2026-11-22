import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the feature-first layers apart, the way janapost does:
///
/// * `lib/app` is the composition root: it may import anything.
/// * `lib/features/<x>` builds on the lower layers and may use another
///   feature's repository, page or widget.
/// * The lower layers (`shared`, `services`, `core`, `render2d`,
///   `render3d`) never import a feature or the app root.
void main() {
  const lower = ['shared', 'services', 'core', 'render2d', 'render3d'];
  final import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

  List<String> importsOf(String dir, bool Function(String uri) bad) {
    final offenders = <String>[];
    for (final f
        in Directory(dir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final (i, line) in f.readAsLinesSync().indexed) {
        final uri = import.firstMatch(line)?.group(1);
        if (uri != null && bad(uri)) offenders.add('${f.path}:${i + 1} $uri');
      }
    }
    return offenders;
  }

  for (final layer in lower) {
    test('lib/$layer imports neither a feature nor the app root', () {
      expect(Directory('lib/$layer').existsSync(), isTrue,
          reason: 'lib/$layer is missing');
      expect(
          importsOf('lib/$layer',
              (uri) => uri.contains('features/') || uri.contains('yusal/app/')),
          isEmpty);
    });
  }

  test('only the known top-level folders', () {
    final dirs = {
      for (final d in Directory('lib').listSync().whereType<Directory>())
        d.path.split('/').last
    };
    expect(dirs, {'app', 'features', ...lower});
  });

  test('features never import the app root', () {
    expect(importsOf('lib/features', (uri) => uri.contains('yusal/app/')),
        isEmpty);
  });

  test('main.dart stays a bootstrap', () {
    // Startup steps and runApp only; widgets belong in lib/app/.
    final main = File('lib/main.dart').readAsStringSync();
    expect(
        RegExp(r'class \w+ extends (StatelessWidget|StatefulWidget)')
            .hasMatch(main),
        isFalse);
    expect(main.contains('showPerformanceOverlay'), isFalse);
  });
}
