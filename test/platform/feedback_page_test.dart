import 'dart:convert';

import '../support/test_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yusal/service/settings/settings.dart';
import '../support/mock/mock_backend.dart';
import 'package:yusal/features/me/pages/feedback.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/service/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

Future<Map<String, String>> _details() async => {
      'app_version': '0.4.0 (5)',
      'device': 'Google Pixel 8 Pro',
      'os_version': 'Android 16',
      'platform': 'android',
      'language': 'zh',
    };

Future<void> _open(WidgetTester t, MockBackend b) async {
  appLang = AppLang.zh;
  await t.pumpWidget(TestScope(
      repos: b,
      store: ProjectStore(fileSystem: MemoryFiles()),
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  const FeedbackPage(loadContext: _details))),
                      child: const Text('open')))))));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows what it attaches and sends it', (t) async {
    final b = MockBackend(latency: Duration.zero);
    await _open(t, b);
    expect(find.textContaining('Pixel 8 Pro'), findsOneWidget);
    expect(
        t.widget<BusyButton>(find.byKey(const Key('feedback-send'))).onPressed,
        isNull,
        reason: 'nothing to send yet');
    await t.enterText(find.byKey(const Key('feedback-text')), ' 门窗不好拖 ');
    await t.pump();
    await t.tap(find.byKey(const Key('feedback-send')));
    await t.pumpAndSettle();
    final sent = b.feedback.values.single;
    expect(sent.text, '门窗不好拖');
    expect(sent.context?['device'], 'Google Pixel 8 Pro');
    expect(find.byType(FeedbackPage), findsNothing,
        reason: 'closed after send');
  });

  testWidgets('switched off, nothing about the device is sent', (t) async {
    final b = MockBackend(latency: Duration.zero);
    await _open(t, b);
    await t.tap(find.byKey(const Key('feedback-attach')));
    await t.enterText(find.byKey(const Key('feedback-text')), 'hi');
    await t.pump();
    await t.tap(find.byKey(const Key('feedback-send')));
    await t.pumpAndSettle();
    expect(b.feedback.values.single.context, isNull);
  });

  testWidgets('offline keeps the text and retries with the same id', (t) async {
    final b = MockBackend(latency: Duration.zero)..simulateOffline = true;
    await _open(t, b);
    await t.enterText(find.byKey(const Key('feedback-text')), '保存很慢');
    await t.pump();
    await t.tap(find.byKey(const Key('feedback-send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feedback-error')), findsOneWidget);
    expect(find.text('保存很慢'), findsOneWidget, reason: 'text kept');
    expect(find.text('重试'), findsOneWidget);
    b.simulateOffline = false;
    await t.tap(find.byKey(const Key('feedback-send')));
    await t.pumpAndSettle();
    expect(b.feedback.values.single.text, '保存很慢');
    expect(find.byType(FeedbackPage), findsNothing);
  });

  test('the API gets the text, context and request id', () async {
    Map<String, dynamic>? body;
    final b = TestHttp('https://api.test', client: MockClient((r) async {
      expect(r.url.path, '/client/feedback');
      body = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('{"success":true,"data":{"id":"f1"}}', 200);
    }));
    await b.feedback.sendFeedback(
        requestId: 'r1', text: 'hi', context: {'device': 'iPhone16,2'});
    expect(body, {
      'request_id': 'r1',
      'text': 'hi',
      'context': {'device': 'iPhone16,2'}
    });
  });
}
