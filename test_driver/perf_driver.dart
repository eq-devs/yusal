import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

/// Driver for `integration_test/editor_perf_test.dart`; prints the frame
/// figures the test reports and writes them to build/editor_perf.json.
Future<void> main() => integrationDriver(responseDataCallback: (data) async {
      if (data == null) return;
      final text = const JsonEncoder.withIndent('  ').convert(data);
      stdout.writeln('EDITOR_PERF $text');
      await File('build/editor_perf.json').writeAsString(text);
    });
