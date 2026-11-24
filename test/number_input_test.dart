import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/number_input.dart';

void main() {
  test('reads decimals with a comma or a dot', () {
    expect(parseNumber('3.6'), 3.6);
    expect(parseNumber('3,6'), 3.6);
    expect(parseNumber(' 12 '), 12);
    expect(parseNumber('.5'), 0.5);
    expect(parseNumber('-2'), -2);
  });

  test('works out simple sums', () {
    expect(parseNumber('3,6+2,4'), 6);
    expect(parseNumber('10-2.5'), 7.5);
    expect(parseNumber('12/3'), 4);
    expect(parseNumber('2+3*4'), 14);
    expect(parseNumber('9 − 1 × 2'), 7);
    expect(parseNumber('-1+3'), 2);
  });

  test('refuses what is not a number', () {
    for (final bad in ['', 'abc', '3..2', '3+', '+3', '1/0', '2(3)', '3,6,1']) {
      expect(parseNumber(bad), isNull, reason: bad);
    }
  });
}
