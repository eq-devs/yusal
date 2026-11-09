import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/ui/photos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // No compressor in tests, as on platforms without the plugin: the original
  // goes up only when the server will take it.
  test('an uncompressed photo is kept only under the server limit', () async {
    final small = Uint8List(500 * 1024);
    expect(await shrinkPhoto(small), small);
    await expectLater(
        shrinkPhoto(Uint8List(maxPhotoBytes + 1)), throwsStateError);
  });
}
