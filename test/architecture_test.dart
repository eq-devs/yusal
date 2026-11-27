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

  group('dependency direction', () {
    final imports = _imports();

    test('the house engine core is pure Dart and self-contained', () {
      // It runs in tests, tools and the benchmark without Flutter.
      final odd = [
        for (final MapEntry(key: file, value: targets) in imports.entries)
          if (file.startsWith('lib/features/editor/engine/core/'))
            for (final t in targets)
              if (t.startsWith('package:') &&
                  !t.startsWith('package:yusal/features/editor/engine/core/') &&
                  !t.startsWith('package:meta/'))
                '$file -> $t'
      ];
      expect(odd, isEmpty);
    });

    test('the base layers do not reach into features', () {
      // constant/, localization/, service/, utils/ and features/shared are
      // what features build on; they may use the engine core, not a
      // feature's pages, state or repositories.
      const allowed = {
        // attempt() and requireLogin() open the login page.
        'lib/features/shared/ui/scope.dart -> features/auth/page.dart',
      };
      final odd = [
        for (final MapEntry(key: file, value: targets) in imports.entries)
          if (_isBase(file))
            for (final t in targets)
              if (t.startsWith('package:yusal/features/') &&
                  !t.startsWith('package:yusal/features/shared/') &&
                  !t.startsWith('package:yusal/features/editor/engine/core/'))
                '$file -> ${t.substring('package:yusal/'.length)}'
      ]..removeWhere(allowed.contains);
      expect(odd, isEmpty);
    });

    test('features depend on each other only as listed', () {
      // The feature graph as it is, cycles included (see
      // docs/governance/TASKS.md). A new edge needs a reason and a line
      // here; a removed one must be deleted here, so the list only shrinks.
      const listed = {
        'admin': {'coop', 'demand', 'editor', 'home', 'me', 'profile'},
        'apply': {'demand', 'profile', 'voice'},
        'auth': {'voice'},
        'backup': {'editor'},
        'chat': {
          'apply',
          'auth',
          'coop',
          'demand',
          'home',
          'me',
          'profile',
          'voice'
        },
        'coop': {'auth', 'chat', 'demand', 'houses', 'profile', 'voice'},
        'demand': {
          'apply',
          'auth',
          'backup',
          'chat',
          'coop',
          'editor',
          'home',
          'me',
          'profile',
          'voice'
        },
        'discover': {'chat', 'demand', 'profile'},
        'editor': {'voice'},
        'explore': {'demand', 'discover', 'home', 'profile', 'shell'},
        'home': {
          'auth',
          'backup',
          'chat',
          'demand',
          'discover',
          'editor',
          'me',
          'profile',
          'shell'
        },
        'houses': {'apply', 'backup', 'coop', 'demand', 'home'},
        'me': {
          'admin',
          'apply',
          'auth',
          'backup',
          'chat',
          'coop',
          'demand',
          'home',
          'profile',
          'voice'
        },
        'profile': {'auth', 'chat', 'coop', 'me'},
        'projects': {
          'backup',
          'coop',
          'demand',
          'editor',
          'home',
          'houses',
          'profile'
        },
        'shell': {'backup', 'chat', 'explore', 'me', 'projects', 'voice'},
        'voice': {'chat', 'coop', 'demand', 'editor'},
      };
      final actual = <String, Set<String>>{};
      for (final MapEntry(key: file, value: targets) in imports.entries) {
        final from = _feature(file);
        if (from == null || from == 'shared') continue;
        for (final t in targets) {
          final to = _feature(t);
          if (to == null || to == 'shared' || to == from) continue;
          actual.putIfAbsent(from, () => {}).add(to);
        }
      }
      expect(actual, listed);
    });
  });
}

/// Each lib/ file's `package:` imports and exports.
Map<String, List<String>> _imports() {
  final directive =
      RegExp("^(?:import|export) '(package:[^']+)'", multiLine: true);
  return {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path: [
          for (final m in directive.allMatches(f.readAsStringSync()))
            m.group(1)!
        ]
  };
}

bool _isBase(String file) => [
      'lib/constant/',
      'lib/localization/',
      'lib/service/',
      'lib/utils/',
      'lib/features/shared/'
    ].any(file.startsWith);

/// The feature a lib/ path or package:yusal URI belongs to.
String? _feature(String path) =>
    RegExp(r'(?:^lib/|^package:yusal/)features/(\w+)/')
        .firstMatch(path)
        ?.group(1);
