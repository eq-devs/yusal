import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps platform pages on the design system: sizes, radii and colours are
/// named in `theme.dart`, not written as numbers in a page.
void main() {
  // The platform look: the shared UI and every feature except the design
  // tool (its own drafting look), the voice orb and the dev lab. The brand
  // palette in features/shared/brand is where colours are named.
  final pages = [
    Directory('lib/features/shared/ui'),
    ...Directory('lib/features').listSync().whereType<Directory>().where((d) =>
        !const ['/editor', '/voice', '/dev', '/shared'].any(d.path.endsWith)),
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

  test('Material icons only where YIcons has no drawing yet', () {
    // YIcons (tool/brand/icons.json) is the icon set. These files still use
    // Material for room types, furniture and form controls the set does
    // not draw; the counts may only go down, and a file at 0 leaves the list.
    const remaining = {
      'features/admin/page.dart': 7,
      'features/auth/page.dart': 7,
      'features/auth/pages/sign_in_methods.dart': 1,
      'features/backup/page.dart': 1,
      'features/chat/pages/inbox.dart': 3,
      'features/coop/page.dart': 1,
      'features/demand/pages/share.dart': 1,
      'features/discover/page.dart': 2,
      'features/editor/engine/render2d/furniture_names.dart': 22,
      'features/editor/engine/render2d/planning_names.dart': 14,
      'features/editor/page.dart': 3,
      'features/editor/pages/home.dart': 1,
      'features/editor/tabs/cost.dart': 1,
      'features/editor/tabs/heat.dart': 1,
      'features/editor/tabs/other.dart': 2,
      'features/editor/tabs/plan.dart': 5,
      'features/editor/tabs/scene.dart': 1,
      'features/editor/tabs/site.dart': 1,
      'features/editor/tools/outline.dart': 4,
      'features/editor/tools/picking.dart': 1,
      'features/editor/tools/utility.dart': 2,
      'features/editor/tools/wall.dart': 4,
      'features/editor/widgets/dialogs.dart': 1,
      'features/editor/widgets/header.dart': 1,
      'features/editor/widgets/phone_layout.dart': 9,
      'features/editor/widgets/selection_cards.dart': 6,
      'features/editor/widgets/start_sheet.dart': 1,
      'features/home/page.dart': 2,
      'features/home/pages/post.dart': 2,
      'features/coop/widgets/site_tab.dart': 2,
      'features/me/page.dart': 2,
      'features/me/pages/voice_settings.dart': 5,
      'features/trust/page.dart': 5,
      'features/profile/page.dart': 1,
      'features/profile/widgets/profile_card.dart': 1,
      'features/projects/page.dart': 1,
      'features/shared/ui/house_progress.dart': 2,
      'features/shared/ui/photos.dart': 1,
      'features/voice/widgets/read_aloud_button.dart': 2,
      'features/voice/widgets/voice_overlay.dart': 2,
    };
    final uses = RegExp(r'\bIcons\.\w+');
    final actual = <String, int>{
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          if (uses.allMatches(f.readAsStringSync()).length case final n
              when n > 0)
            f.path.substring('lib/'.length): n
    }..remove('features/shared/brand/yicons.dart');
    expect(actual, remaining);
  });
}
