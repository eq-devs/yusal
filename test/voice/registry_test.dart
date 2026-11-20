import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/data/mock/mock_backend.dart';
import 'package:yusal/data/mock/mock_clock.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/registry.dart';

const _name = L3('动作', 'Әрекет', 'Действие');

AppAction action(String id,
        {L3 title = _name,
        L3 examples = _name,
        Risk risk = Risk.read,
        Map<String, Param> params = const {},
        bool Function(ActionContext)? when}) =>
    AppAction(
        id: id,
        title: title,
        examples: examples,
        risk: risk,
        params: params,
        when: when,
        run: (_, __) async => const ActionResult.ok());

void main() {
  test('a well-formed registry has no problems', () {
    final registry = ActionRegistry([
      action('demand.pause', params: const {'demand': Param.entity('demand')}),
      action('design.add_window', params: const {
        'side': Param.choice(['north'])
      }),
    ]);
    expect(registry.problems(), isEmpty);
    expect(registry['demand.pause']!.id, 'demand.pause');
    expect(registry['nope'], isNull);
  });

  test('the same id cannot be registered twice', () {
    expect(() => ActionRegistry([action('a.b'), action('a.b')]),
        throwsArgumentError);
  });

  test('problems names every malformed action', () {
    final registry = ActionRegistry([
      action('Pause'),
      action('a.title', title: const L3('暂停', '', 'Пауза')),
      action('a.examples', examples: const L3('暂停', 'Тоқтат', ' ')),
      action('a.param', params: const {'Wall Id': Param.text()}),
      action('a.choice', params: const {'side': Param.choice([])}),
    ]);
    expect(registry.problems(), [
      'Pause: id is not dotted lower case',
      'a.title: title lacks a language',
      'a.examples: examples lack a language',
      'a.param: param Wall Id is not lower case',
      'a.choice: param side has no choices',
    ]);
  });

  test('voice is offered what is available and not touch-only', () {
    final registry = ActionRegistry([
      action('a.always'),
      action('a.manual', risk: Risk.manual),
      action('a.logged_in', when: (ctx) => ctx.loggedIn),
      action('a.room', when: (ctx) => ctx.has('room')),
    ]);
    final repos = MockBackend(
        clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
        latency: Duration.zero,
        seed: false);
    List<String> offered(ActionContext ctx) =>
        [for (final a in registry.offered(ctx)) a.id];

    expect(offered(ActionContext(repos: repos, loggedIn: false)), ['a.always']);
    expect(
        offered(ActionContext(
            repos: repos,
            loggedIn: true,
            entities: const [Entity('room', 'id', alias: 'r1')])),
        ['a.always', 'a.logged_in', 'a.room']);
  });

  test('tool definitions carry the argument schema and skip touch-only', () {
    final tools = ActionRegistry([
      action('a.b', risk: Risk.outbound, params: const {
        'room': Param.entity('room'),
        'side': Param.choice(['north', 'south'], optional: true),
        'width': Param.number(optional: true),
      }),
      action('a.manual', risk: Risk.manual),
    ]).tools();
    expect(tools.map((t) => t['name']), ['a.b']);
    expect(tools.single['risk'], 'outbound');
    expect(tools.single['parameters'], {
      'type': 'object',
      'properties': {
        'room': {'type': 'string', 'entity': 'room'},
        'side': {
          'type': 'string',
          'enum': ['north', 'south']
        },
        'width': {'type': 'number'},
      },
      'required': ['room'],
    });
  });

  // The AI gateway loads docs/voice_tools.json. After changing an action,
  // rewrite it with: UPDATE_VOICE_TOOLS=1 flutter test test/voice/registry_test.dart
  test('docs/voice_tools.json matches the app\'s actions', () {
    final file = File('docs/voice_tools.json');
    final now =
        '${const JsonEncoder.withIndent('  ').convert(appActions.tools())}\n';
    if (Platform.environment['UPDATE_VOICE_TOOLS'] == '1') {
      file.writeAsStringSync(now);
    }
    expect(file.readAsStringSync(), now);
  });
}
