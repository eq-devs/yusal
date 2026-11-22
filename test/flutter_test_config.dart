import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:yusal/services/api/session_store.dart';

/// Every test starts signed out: an empty keystore and an empty session box
/// in a temporary folder.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final dir = await Directory.systemTemp.createTemp('yusal_hive');
  Hive.init(dir.path);
  final box = await Hive.openBox<dynamic>(SessionStore.boxName);
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await box.clear();
  });
  await testMain();
}
