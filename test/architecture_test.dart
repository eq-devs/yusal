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
      final odd = [
        for (final MapEntry(key: file, value: targets) in imports.entries)
          if (_isBase(file))
            for (final t in targets)
              if (t.startsWith('package:yusal/features/') &&
                  !t.startsWith('package:yusal/features/shared/') &&
                  !t.startsWith('package:yusal/features/editor/engine/core/'))
                '$file -> ${t.substring('package:yusal/'.length)}'
      ];
      expect(odd, isEmpty);
    });

    test('a feature layer imports only the layers below it', () {
      // data (repository/, model/) <- state/ <- UI (everything else), in
      // its own feature and in others.
      final odd = [
        for (final MapEntry(key: file, value: targets) in imports.entries)
          if (_node(file) case final from?)
            for (final t in targets)
              if (_node(t) case final to?
                  when to.layer.index > from.layer.index)
                '$file -> ${t.substring('package:yusal/'.length)}'
      ];
      expect(odd, isEmpty);
    });

    test('the features of one layer form no cycle', () {
      // A feature opens another feature's page through a Destination
      // (shared/ui/routes.dart), so pages never need each other both ways.
      for (final layer in _Layer.values) {
        final edges = <String, Set<String>>{};
        for (final MapEntry(key: file, value: targets) in imports.entries) {
          final from = _node(file);
          if (from == null || from.layer != layer) continue;
          for (final t in targets) {
            final to = _node(t);
            if (to == null || to.layer != layer || to.feature == from.feature) {
              continue;
            }
            edges.putIfAbsent(from.feature, () => {}).add(to.feature);
          }
        }
        expect(_cycle(edges), isEmpty, reason: '${layer.name} layer');
      }
    });
  });
}

enum _Layer { data, state, ui }

/// The feature and layer a lib/ path or package:yusal URI belongs to;
/// null for the base layers, features/shared and the house engine.
({String feature, _Layer layer})? _node(String path) {
  final m = RegExp(r'(?:^lib/|^package:yusal/)features/(\w+)/(?:(\w+)/)?')
      .firstMatch(path);
  if (m == null) return null;
  final (feature, top) = (m.group(1)!, m.group(2));
  if (feature == 'shared' || (feature == 'editor' && top == 'engine')) {
    return null;
  }
  final layer = switch (top) {
    'repository' || 'model' => _Layer.data,
    'state' => _Layer.state,
    _ => _Layer.ui,
  };
  return (feature: feature, layer: layer);
}

/// One cycle of [edges] (its nodes in order), or empty when there is none.
List<String> _cycle(Map<String, Set<String>> edges) {
  final done = <String>{};
  final path = <String>[];
  List<String> visit(String v) {
    if (path.contains(v)) return [...path.sublist(path.indexOf(v)), v];
    if (!done.add(v)) return const [];
    path.add(v);
    for (final w in edges[v] ?? const <String>{}) {
      final c = visit(w);
      if (c.isNotEmpty) return c;
    }
    path.removeLast();
    return const [];
  }

  for (final v in edges.keys) {
    final c = visit(v);
    if (c.isNotEmpty) return c;
  }
  return const [];
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
