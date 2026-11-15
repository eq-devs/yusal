import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/actions.dart';
import 'package:yusal/voice/actions_design.dart';
import 'package:yusal/voice/executor.dart';
import 'package:yusal/voice/screen.dart';
import 'package:yusal/voice/session.dart';

import '../storage_test.dart' show MemoryFiles;

/// Plays the server: hands out the scripted turns in order and records
/// what the app sent.
class ScriptedBackend implements VoiceBackend {
  ScriptedBackend(this.script);
  final List<Object> script;
  final said = <({String text, bool spoken, Map<String, Object?> context})>[];
  final reported = <({String turnId, List<Map<String, Object?>> results})>[];

  VoiceTurn _next() {
    final next = script.removeAt(0);
    if (next is VoiceTurn) return next;
    throw next;
  }

  @override
  Future<VoiceTurn> say(
      {required String sessionId,
      required String text,
      required bool spoken,
      required Map<String, Object?> context}) async {
    said.add((text: text, spoken: spoken, context: context));
    return _next();
  }

  @override
  Future<VoiceTurn> results(
      {required String turnId,
      required List<Map<String, Object?>> results,
      required Map<String, Object?> context}) async {
    reported.add((turnId: turnId, results: results));
    return _next();
  }
}

/// A server that answers when the test lets it.
class SlowBackend implements VoiceBackend {
  final pending = <Completer<VoiceTurn>>[];
  final said = <String>[];
  final reported = <String>[];

  Future<VoiceTurn> _wait() {
    pending.add(Completer());
    return pending.last.future;
  }

  @override
  Future<VoiceTurn> say(
      {required String sessionId,
      required String text,
      required bool spoken,
      required Map<String, Object?> context}) {
    said.add(text);
    return _wait();
  }

  @override
  Future<VoiceTurn> results(
      {required String turnId,
      required List<Map<String, Object?>> results,
      required Map<String, Object?> context}) {
    reported.add(turnId);
    return _wait();
  }
}

VoiceTurn act(String turnId, List<(String, Map<String, Object?>)> calls) =>
    VoiceTurn(turnId: turnId, calls: [
      for (final (i, (action, args)) in calls.indexed)
        ActionCall('c$i', action, args)
    ]);

void main() {
  final repos = MockBackend(latency: Duration.zero, seed: false);

  VoiceSession session(ScriptedBackend backend) => VoiceSession(
      backend: backend,
      executor: ActionExecutor(appActions, confirm: (_, __) async => true),
      repos: repos,
      loggedIn: () => true,
      sessionId: 's1');

  Future<DesignHost> openEditor(WidgetTester t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var sequence = 0;
    final doc = createHouse(
        name: '会话',
        width: 10000,
        depth: 8000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-11-14T00:00:00Z',
        newId: () => 'id${sequence++}');
    await t.pumpWidget(MaterialApp(
        home: HouseEditor(
            entry: ProjectEntry('project', doc),
            store: ProjectStore(fileSystem: MemoryFiles()))));
    await t.pumpAndSettle();
    return VoiceScreens.current! as DesignHost;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  test('a turn parses from the server and ignores unknown events', () {
    final turn = VoiceTurn.fromJson({
      'reply': '哪一间？',
      'events': [
        {'type': 'scene_updated'},
        {
          'type': 'run_actions',
          'turn_id': 't1',
          'calls': [
            {
              'id': 'c1',
              'action': 'design.add_floor',
              'args': {'floor': 'f1'}
            },
            {'id': 'c2', 'action': 'editor.undo'}
          ]
        },
        {
          'type': 'options',
          'options': ['主卧', '次卧']
        },
      ]
    });
    expect(turn.reply, '哪一间？');
    expect(turn.turnId, 't1');
    expect([for (final c in turn.calls) (c.id, c.action)],
        [('c1', 'design.add_floor'), ('c2', 'editor.undo')]);
    expect([
      for (final c in turn.calls) c.args
    ], [
      {'floor': 'f1'},
      <String, Object?>{}
    ]);
    expect(turn.options, ['主卧', '次卧']);
    expect(VoiceTurn.fromJson({}).turnId, isNull);
  });

  testWidgets('one sentence runs several steps and undoes as one', (t) async {
    final host = await openEditor(t);
    final backend = ScriptedBackend([
      act('t1', [
        ('design.add_floor', {}),
        ('design.rename_room', {'room': 'r1', 'name': '书房'}),
      ]),
      act('t2', [
        (
          'design.add_opening',
          {'room': 'r1', 'side': 'north', 'kind': 'window'}
        )
      ]),
      const VoiceTurn(reply: '加好了。'),
    ]);
    final s = session(backend);
    final phases = <VoicePhase>[];
    s.addListener(() {
      if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
    });

    await s.say('加一层楼，把这间叫书房，再在北墙加窗', spoken: true);
    await t.pump();

    expect(phases, [
      VoicePhase.thinking,
      VoicePhase.acting,
      VoicePhase.thinking,
      VoicePhase.acting,
      VoicePhase.thinking,
      VoicePhase.done
    ]);
    expect(s.reply, '加好了。');
    expect(s.steps.map((x) => (x.action!.id, x.result.ok)), [
      ('design.add_floor', true),
      ('design.rename_room', true),
      ('design.add_opening', true)
    ]);

    // What the server was told: the screen with aliases, not ids.
    final sent = backend.said.single;
    expect((sent.text, sent.spoken), ('加一层楼，把这间叫书房，再在北墙加窗', true));
    expect(sent.context['screen'], 'editor.plan');
    // Only what can run on this screen is offered to the model.
    expect(sent.context['actions'], contains('design.add_floor'));
    expect(sent.context['actions'], isNot(contains('form.submit')));
    expect(sent.context['entities'], contains(containsPair('id', 'r1')));
    expect('${sent.context}', isNot(contains('id0')));
    expect(backend.reported.map((r) => r.turnId), ['t1', 't2']);
    expect(backend.reported.map((r) => r.results), [
      [
        {'id': 'c0', 'ok': true},
        {
          'id': 'c1',
          'ok': true,
          'changed': ['r1']
        }
      ],
      [
        {
          'id': 'c0',
          'ok': true,
          'changed': ['o1']
        }
      ],
    ]);
    // The open design goes along as text.
    expect(sent.context['scene'], contains(' r1 '));
    expect(sent.context['scene'], contains('10000x8000'));

    expect(host.document.floors, hasLength(2));
    expect(host.document.floors.first.openings, hasLength(1));
    expect(host.undoDesign(), isTrue);
    await t.pump();
    expect(host.document.floors, hasLength(1));
    expect(host.document.floors.single.openings, isEmpty);
    expect(host.document.floors.single.rooms.single.name, isNot('书房'));
    expect(host.undoDesign(), isFalse);
    await close(t);
  });

  testWidgets('a failed action stops its batch and the reason goes back',
      (t) async {
    final host = await openEditor(t);
    final backend = ScriptedBackend([
      act('t1', [
        ('design.rename_room', {'room': 'r9', 'name': 'x'}),
        ('design.add_floor', {}),
      ]),
      const VoiceTurn(reply: '没有这个房间。'),
    ]);
    final s = session(backend);
    await s.say('把九号房间改名', spoken: false);

    expect(backend.reported.single.results, [
      {
        'id': 'c0',
        'ok': false,
        'code': ActionCodes.unknownEntity,
        'say': {'param': 'room'}
      },
      {'id': 'c1', 'ok': false, 'code': VoiceCodes.skipped},
    ]);
    expect(host.document.floors, hasLength(1));
    expect(s.phase, VoicePhase.done);
    expect(s.reply, '没有这个房间。');
    await close(t);
  });

  test('a server that never stops asking is cut off', () async {
    final backend = ScriptedBackend([
      for (var i = 0; i <= VoiceSession.maxSteps; i++)
        act('t$i', [
          ('nav.tab', {'tab': 'me'})
        ])
    ]);
    final s = session(backend);
    await s.say('转圈', spoken: false);
    expect(s.phase, VoicePhase.failed);
    expect(s.error, VoiceCodes.tooManySteps);
    expect(backend.reported, hasLength(VoiceSession.maxSteps));
  });

  test('server and network failures end the turn with a code', () async {
    final limited =
        session(ScriptedBackend([const ApiFailure('RATE_LIMITED')]));
    await limited.say('你好', spoken: false);
    expect((limited.phase, limited.error), (VoicePhase.failed, 'RATE_LIMITED'));

    final offline = session(ScriptedBackend([Exception('no route')]));
    await offline.say('你好', spoken: false);
    expect(offline.error, VoiceCodes.network);

    // The next sentence starts clean.
    final again = session(ScriptedBackend([
      Exception('x'),
      const VoiceTurn(reply: '好的', options: ['是', '不'])
    ]));
    await again.say('一', spoken: false);
    await again.say('二', spoken: false);
    expect(
        (again.phase, again.error, again.reply), (VoicePhase.done, null, '好的'));
    expect(again.options, ['是', '不']);
  });

  test('stop skips the actions that have not run', () async {
    final backend = ScriptedBackend([
      act('t1', [
        ('nav.tab', {'tab': 'me'}),
        ('nav.tab', {'tab': 'houses'}),
      ]),
      const VoiceTurn(reply: '已停止。'),
    ]);
    final s = session(backend);
    s.addListener(() {
      if (s.steps.length == 1) s.stop();
    });
    await s.say('去我的，再去房子', spoken: false);
    expect(backend.reported.single.results.map((r) => r['code']),
        [ActionCodes.notAvailable, VoiceCodes.skipped]);
  });

  test('a sentence said while another runs interrupts it', () async {
    final backend = SlowBackend();
    final s = VoiceSession(
        backend: backend,
        executor: ActionExecutor(appActions, confirm: (_, __) async => true),
        repos: repos,
        loggedIn: () => true,
        sessionId: 's1');
    final first = s.say('加一层楼', spoken: true);
    await s.say('不对，加一扇窗', spoken: true);
    expect(s.busy, isTrue);
    expect(s.heard, '不对，加一扇窗');
    expect(backend.said, ['加一层楼']);

    // The first sentence's actions come back too late: none of them run.
    backend.pending[0].complete(act('t1', [('editor.undo', {})]));
    await pumpEventQueue();
    expect(s.steps, isEmpty);
    expect(backend.reported, isEmpty);
    expect(backend.said, ['加一层楼', '不对，加一扇窗']);

    backend.pending[1].complete(const VoiceTurn(reply: '加好了。'));
    await first;
    expect(s.phase, VoicePhase.done);
    expect(s.reply, '加好了。');
  });
}
