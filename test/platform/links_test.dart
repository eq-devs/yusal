import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/ui/links.dart';

void main() {
  test('house links round-trip through the web route', () {
    expect(houseLink('post_aigerim'),
        'https://yusal-web.web.app/#/h/post_aigerim');
    expect(houseIdFromRoute('/h/post_aigerim'), 'post_aigerim');
    expect(houseIdFromRoute('/h/post_aigerim/'), 'post_aigerim');
    expect(houseIdFromRoute('/'), isNull);
    expect(houseIdFromRoute('/h/'), isNull);
    expect(houseIdFromRoute('/h/../x'), isNull);
    expect(houseIdFromRoute(null), isNull);
  });
}
