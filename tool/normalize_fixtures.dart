import 'dart:io';
import '../lib/core/house_core.dart';

void main() {
  for (final name in ['minimal_flat', 'full_two_floor_gable']) {
    final file = File('test/fixtures/$name.house');
    final result = loadHouse(file.readAsBytesSync());
    if (!result.isSuccess) throw StateError('Invalid fixture: $name');
    file.writeAsStringSync(encodeHouse(result.document!));
  }
}
