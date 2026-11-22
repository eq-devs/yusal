import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps platform pages on the design system: sizes, radii and colours are
/// named in `theme.dart`, not written as numbers in a page.
void main() {
  // The platform look: the shared UI and every feature except the design
  // tool (its own drafting look), the voice orb and the dev lab.
  final pages = [
    Directory('lib/shared/ui'),
    ...Directory('lib/features').listSync().whereType<Directory>().where(
        (d) => !const ['/editor', '/voice', '/dev'].any(d.path.endsWith)),
  ]
      .expand((d) => d.listSync(recursive: true))
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('finds the platform pages', () {
    expect(pages.length, greaterThan(40));
  });

  Map<String, List<String>> offenders(RegExp pattern,
      {Set<String> allow = const {}}) {
    final out = <String, List<String>>{};
    for (final f in pages) {
      final name = f.path.split('/').last;
      if (allow.contains(name)) continue;
      final hits = [
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (!line.trimLeft().startsWith('//') && pattern.hasMatch(line))
            '${i + 1}: ${line.trim()}'
      ];
      if (hits.isNotEmpty) out[name] = hits;
    }
    return out;
  }

  test('no literal font size in a page', () {
    expect(
        offenders(RegExp(r'fontSize:\s*\d'), allow: {'theme.dart'}), isEmpty);
  });

  test('no literal corner radius in a page', () {
    expect(
        offenders(RegExp(r'[Rr]adius\.circular\(\s*\d'), allow: {'theme.dart'}),
        isEmpty);
  });

  test('no literal colour in a page', () {
    // widgets.dart holds the avatar and placeholder-cover palettes.
    expect(
        offenders(RegExp(r'Color\(0x|Colors\.(white|black)\b'),
            allow: {'theme.dart', 'widgets.dart'}),
        isEmpty);
  });
}
