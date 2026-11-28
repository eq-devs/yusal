import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/service/settings/settings.dart';

void main() {
  test('amounts are grouped by a space in every language', () {
    final before = appLang;
    addTearDown(() => appLang = before);
    for (final lang in AppLang.values) {
      appLang = lang;
      expect(groupDigits(1250000), '1 250 000', reason: lang.name);
      expect(groupDigits(-999.6), '-1 000', reason: lang.name);
      expect(money(1250000), '1 250 000 ₸', reason: lang.name);
    }
    expect(money(null), '—');
  });
}
