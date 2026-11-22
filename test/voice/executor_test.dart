import 'package:flutter_test/flutter_test.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_clock.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/state/registry.dart';

const _name = L3('动作', 'Әрекет', 'Действие');

void main() {
  late List<Args> ran;
  late List<String> asked;
  var approve = true;

  AppAction action(String id, Risk risk,
          {Map<String, Param> params = const {},
          bool Function(ActionContext)? when}) =>
      AppAction(
        id: id,
        title: _name,
        examples: _name,
        params: params,
        when: when,
        risk: risk,
        run: (ctx, args) async {
          ran.add(args);
          return ActionResult.ok(changed: [id]);
        },
      );

  final registry = ActionRegistry([
    action('test.read', Risk.read),
    action('test.undoable', Risk.undoable),
    action('test.outbound', Risk.outbound),
    action('test.manual', Risk.manual),
    action('test.logged_in', Risk.read, when: (ctx) => ctx.loggedIn),
    action('test.params', Risk.read, params: const {
      'text': Param.text(),
      'width': Param.number(),
      'count': Param.integer(),
      'on': Param.flag(),
      'side': Param.choice(['north', 'south']),
      'room': Param.entity('room'),
      'note': Param.text(optional: true),
    }),
    AppAction(
        id: 'test.throws',
        title: _name,
        examples: _name,
        risk: Risk.read,
        run: (_, __) => throw StateError('boom')),
  ]);

  final executor = ActionExecutor(registry, confirm: (action, _) async {
    asked.add(action.id);
    return approve;
  });

  final ctx = ActionContext(
      repos: MockBackend(
          clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
          latency: Duration.zero,
          seed: false),
      loggedIn: false,
      entities: const [
        Entity('room', 'room-uuid-1', alias: 'r1', title: '客厅'),
        Entity('wall', 'wall-uuid-3', alias: 'w3'),
      ]);

  const good = <String, Object?>{
    'text': 'hello',
    'width': 1.5,
    'count': 2,
    'on': true,
    'side': 'north',
    'room': 'r1',
  };

  Future<ActionResult> run(String id,
          {Map<String, Object?> args = const {},
          Source source = Source.voice}) =>
      executor.run(id, args, ctx, source: source);

  setUp(() {
    ran = [];
    asked = [];
    approve = true;
  });

  group('risk', () {
    test('read and undoable run from voice without asking', () async {
      expect((await run('test.read')).changed, ['test.read']);
      expect((await run('test.undoable')).ok, isTrue);
      expect(asked, isEmpty);
    });

    test('outbound from voice runs only after the user confirms', () async {
      approve = false;
      expect((await run('test.outbound')).code, ActionCodes.declined);
      expect(ran, isEmpty);

      approve = true;
      expect((await run('test.outbound')).ok, isTrue);
      expect(asked, ['test.outbound', 'test.outbound']);
      expect(ran, hasLength(1));
    });

    test('outbound from a button is not asked twice', () async {
      expect((await run('test.outbound', source: Source.touch)).ok, isTrue);
      expect(asked, isEmpty);
    });

    test('manual never runs from voice but does from a button', () async {
      expect((await run('test.manual')).code, ActionCodes.manualOnly);
      expect(ran, isEmpty);
      expect((await run('test.manual', source: Source.touch)).ok, isTrue);
    });
  });

  test('an unknown id fails', () async {
    expect((await run('test.nope')).code, ActionCodes.unknownAction);
  });

  test('an action whose condition is false does not run', () async {
    expect((await run('test.logged_in')).code, ActionCodes.notAvailable);
    expect(ran, isEmpty);
  });

  test('an action that throws reports failure', () async {
    final result = await run('test.throws');
    expect(result.code, ActionCodes.failed);
    expect(result.say['error'], contains('boom'));
  });

  group('arguments', () {
    test('valid arguments arrive typed, entities resolved by alias', () async {
      expect((await run('test.params', args: good)).ok, isTrue);
      final args = ran.single;
      expect(args.text('text'), 'hello');
      expect(args.number('width'), 1.5);
      expect(args.integer('count'), 2);
      expect(args.flag('on'), isTrue);
      expect(args.choice('side'), 'north');
      expect(args.id('room'), 'room-uuid-1');
      expect(args.has('note'), isFalse);
    });

    test('an entity can also be named by its id', () async {
      await run('test.params', args: {...good, 'room': 'room-uuid-1'});
      expect(ran.single.entity('room').alias, 'r1');
    });

    test('a whole number sent as a double is an integer', () async {
      await run('test.params', args: {...good, 'count': 2.0});
      expect(ran.single.integer('count'), 2);
    });

    final bad = <String, Map<String, Object?>>{
      'missing required': {...good}..remove('text'),
      'wrong type': {...good, 'width': 'wide'},
      'fractional integer': {...good, 'count': 2.5},
      'not finite': {...good, 'width': double.nan},
      'choice outside the list': {...good, 'side': 'up'},
      'argument that is not declared': {...good, 'colour': 'red'},
    };
    for (final MapEntry(key: name, value: args) in bad.entries) {
      test('$name is rejected before the action runs', () async {
        expect(
            (await run('test.params', args: args)).code, ActionCodes.badArgs);
        expect(ran, isEmpty);
      });
    }

    test('an entity of the wrong kind or not on screen is unknown', () async {
      for (final ref in ['w3', 'r9']) {
        final result = await run('test.params', args: {...good, 'room': ref});
        expect(result.code, ActionCodes.unknownEntity);
        expect(result.say['param'], 'room');
      }
      expect(ran, isEmpty);
    });

    test('bad arguments are caught before the user is asked', () async {
      final r = ActionRegistry([
        action('test.send', Risk.outbound, params: const {'to': Param.text()})
      ]);
      final e = ActionExecutor(r, confirm: (a, _) async {
        asked.add(a.id);
        return true;
      });
      final result = await e.run('test.send', {}, ctx, source: Source.voice);
      expect(result.code, ActionCodes.badArgs);
      expect(asked, isEmpty);
    });
  });
}
