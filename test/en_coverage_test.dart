import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/localization/messages_en.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/analysis/build_schedule.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/editor/engine/render2d/furniture_names.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;
import 'tabs.dart';

/// Cyrillic and Chinese: neither belongs on an English screen.
final _cyrillic = RegExp('[Ѐ-ӿ]');
final _chinese = RegExp('[一-鿿]');

/// The language switch names each language in itself.
const _allowed = {
  'Қазақша',
  'Русский',
  '中文',
  'Тіл / 语言 / Language',
  'Тіл / Язык / 语言 / Language',
};

Set<String> shownTexts(WidgetTester t) {
  final out = <String>{};
  for (final w in t.allWidgets) {
    if (w is Text) {
      out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
    } else if (w is RichText) {
      out.add(w.text.toPlainText());
    } else if (w is Tooltip) {
      out.add(w.message ?? '');
    } else if (w is EditableText) {
      out.add(w.controller.text);
    }
  }
  return out..remove('');
}

List<String> foreign(Set<String> texts) => [
      for (final s in texts)
        if (!_allowed.contains(s) &&
            (_cyrillic.hasMatch(s) || _chinese.hasMatch(s)))
          s
    ];

void main() {
  tearDown(() => appLang = AppLang.zh);

  test('every tr3 call with written texts also has English', () {
    // tr3('中文', 'Қазақша', 'Русский') with no fourth text shows Russian
    // to English readers.
    final threeOnly = RegExp(
        r"tr3\(\s*'[^']*',\s*'[^']*',\s*'[^']*'\s*\)",
        multiLine: true);
    final offenders = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final m in threeOnly.allMatches(f.readAsStringSync()))
          '${f.path}: ${m[0]}'
    ];
    expect(offenders, isEmpty);
  });

  test('every table row has an English text', () {
    final missing = <String>[
      for (final n in furnitureNames.values)
        if (!hasEnText(n.$2)) n.$2,
      for (final list in stageChecks.values)
        for (final c in list)
          if (!hasEnText(c.$2)) c.$2,
    ];
    expect(missing, isEmpty);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
        'in English every page of the design tool is English at ${size.width}',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      appLang = AppLang.en;
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var id = 0;
      final doc = createKazakhTemplate(
          '2026-11-01T00:00:00Z', () => 'en_${id++}',
          name: 'Kazakh village house', names: kazakhTemplateNames());
      final store = ProjectStore(fileSystem: MemoryFiles());
      final pid = await store.createProject(doc);
      await t.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: HouseEditor(entry: ProjectEntry(pid, doc), store: store))));
      await t.pumpAndSettle();

      final found = <String, List<String>>{};
      void scan(String where) {
        final bad = foreign(shownTexts(t));
        if (bad.isNotEmpty) found[where] = bad;
      }

      scan('plan');
      for (final key in [
        'ext',
        'walk',
        'site',
        'det',
        'heat',
        'qty',
        'cost',
        'build',
        'iss',
        'plan'
      ]) {
        await t.pumpAndSettle();
        await openTab(t, key);
        await t.pumpAndSettle();
        scan(key);
        final lists = find.byType(Scrollable);
        if (key != 'plan' && key != 'ext' && key != 'walk') {
          await t.drag(lists.last, const Offset(0, -700), warnIfMissed: false);
          await t.pumpAndSettle();
          scan('$key (scrolled)');
        }
        expect(t.takeException(), isNull, reason: key);
      }

      await t.tap(find.byTooltip('More actions'));
      await t.pumpAndSettle();
      scan('menu');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      expect(found, isEmpty,
          reason: found.entries
              .map((e) => '${e.key}: ${e.value.take(12).join(' | ')}')
              .join('\n'));
    });
  }
}
