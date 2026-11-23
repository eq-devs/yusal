// How lists, places, floors, units and dates read in each language: the
// Chinese forms must not leak into Kazakh and Russian.
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/commands/house_templates.dart';
import 'package:yusal/localization/l10n.dart';

void main() {
  tearDown(() => appLang = AppLang.zh);

  test("lists are joined with the language's own comma", () {
    appLang = AppLang.zh;
    expect(['瓦工', '抹灰'].join(listSep), '瓦工、抹灰');
    for (final lang in [AppLang.kk, AppLang.ru]) {
      appLang = lang;
      expect(['Каменщик', 'Штукатур'].join(listSep), 'Каменщик, Штукатур');
    }
  });

  test('automatic floor names follow the language, typed ones are kept', () {
    appLang = AppLang.zh;
    expect(floorDisplayName('一楼'), '一楼');
    appLang = AppLang.ru;
    expect(floorDisplayName('一楼'), '1-й этаж');
    expect(floorDisplayName('二楼 副本'), '2-й этаж (копия)');
    expect(floorDisplayName('Мансарда'), 'Мансарда');
    appLang = AppLang.kk;
    expect(floorDisplayName('二楼'), '2-қабат');
  });

  test('the two-storey template has a first and a second floor', () {
    var n = 0;
    final doc = createTemplate('two', '2026-11-19T00:00:00Z', () => 't${n++}');
    expect([for (final f in doc.floors) f.name], ['一楼', '二楼']);
  });

  test('a place is not printed twice', () {
    appLang = AppLang.ru;
    expect(placeText('esik', 'Есик'), 'Есик');
    expect(placeText('talgar', 'Талгар, северная часть'),
        'Талгар, северная часть');
    expect(placeText('talgar', 'северная часть'), 'Талгар · северная часть');
    expect(placeText('talgar', ''), 'Талгар');
  });

  test('square metres and dates are written the local way', () {
    final day = DateTime(2026, 12, 2);
    appLang = AppLang.zh;
    expect((sqm, unitLabel('m3'), fmtDay(day)), ('m²', 'm³', '2026-12-02'));
    for (final lang in [AppLang.kk, AppLang.ru]) {
      appLang = lang;
      expect((sqm, unitLabel('m3'), fmtDay(day)), ('м²', 'м³', '02.12.2026'));
    }
  });
}
