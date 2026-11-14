import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/data/repositories.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  http.Response json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json'});

  test('a sentence and its results go to /voice and /voice/results', () async {
    final seen = <(String, Map<String, dynamic>)>[];
    final api = HttpBackend('https://api.test', client: MockClient((r) async {
      seen.add((r.url.path, jsonDecode(r.body) as Map<String, dynamic>));
      return json({
        'success': true,
        'data': r.url.path == '/voice'
            ? {
                'reply': '',
                'events': [
                  {
                    'type': 'run_actions',
                    'turn_id': 't1',
                    'calls': [
                      {'id': 'c1', 'action': 'design.add_floor', 'args': {}}
                    ]
                  }
                ]
              }
            : {'reply': 'Қабат қосылды.', 'events': []}
      });
    }));

    final first = await api.say(
        sessionId: 's1',
        text: 'бір қабат қос',
        spoken: true,
        context: {'screen': 'editor.plan'});
    expect(
        (first.turnId, first.calls.single.action), ('t1', 'design.add_floor'));
    final last = await api.results(turnId: 't1', results: [
      {'id': 'c1', 'ok': true}
    ], context: {
      'screen': 'editor.plan'
    });
    expect((last.turnId, last.reply), (null, 'Қабат қосылды.'));

    expect(seen.map((s) => s.$1), ['/voice', '/voice/results']);
    expect(seen.first.$2, {
      'session_id': 's1',
      'text': 'бір қабат қос',
      'input': 'voice',
      'context': {'screen': 'editor.plan'}
    });
    expect(seen.last.$2['turn_id'], 't1');
    expect(seen.last.$2['results'], [
      {'id': 'c1', 'ok': true}
    ]);
  });

  test('a refusal from the server keeps its code', () async {
    final api = HttpBackend('https://api.test',
        client: MockClient((_) async => json(
            {'success': false, 'code': 'RATE_LIMITED', 'msg': 'slow down'},
            429)));
    await expectLater(
        api.say(sessionId: 's', text: 'x', spoken: false, context: {}),
        throwsA(
            isA<ApiFailure>().having((e) => e.code, 'code', 'RATE_LIMITED')));
  });
}
