import 'package:flutter/material.dart';
import '../support/test_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/mock/mock_backend.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/demand/pages/publish.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/actions/actions.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/model/form.dart';
import 'package:yusal/features/voice/state/screen.dart';

import '../storage_test.dart' show MemoryFiles;

class _Form extends StatefulWidget {
  const _Form();
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> with VoiceScreen {
  final wage = TextEditingController();
  final note = TextEditingController();
  String unit = 'day';
  int sent = 0;

  @override
  String get screenId => 'test.form';

  @override
  List<VoiceField> get fields => [
        VoiceField.number('wage', const L3('工资', 'Жалақы', 'Ставка', 'Wage'), wage),
        VoiceField.text('note', const L3('说明', 'Қосымша', 'Комментарий', 'Note'), note),
        VoiceField.choice('unit', const L3('单位', 'Бірлік', 'Единица', 'Unit'),
            const ['day', 'month'], (v) => setState(() => unit = v)),
      ];

  @override
  Future<void> Function()? get voiceSubmit => () async => sent++;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  final repos = MockBackend(latency: Duration.zero)..signInAs(SeedIds.owner);
  var approve = true;
  final executor =
      ActionExecutor(appActions, confirm: (_, __) async => approve);

  Future<ActionResult> say(String id, [Map<String, Object?> args = const {}]) =>
      executor.run(
          id, args, VoiceScreens.context(voiceRepos(repos), loggedIn: true),
          source: Source.voice);

  testWidgets('one sentence fills several fields and sends nothing', (t) async {
    await t.pumpWidget(const MaterialApp(home: _Form()));
    final form = t.state<_FormState>(find.byType(_Form));

    final filled = await say('form.fill', {
      'values': {'wage': 15000.0, 'note': '下周一开工', 'unit': 'month'}
    });
    expect(filled.changed, ['wage', 'note', 'unit']);
    expect(form.wage.text, '15000');
    expect(form.note.text, '下周一开工');
    expect(form.unit, 'month');
    expect(form.sent, 0);

    await say('form.fill', {
      'values': {'wage': 12.5}
    });
    expect(form.wage.text, '12.5');
  });

  testWidgets('one bad value and no field changes', (t) async {
    await t.pumpWidget(const MaterialApp(home: _Form()));
    final form = t.state<_FormState>(find.byType(_Form));
    final bad = <String, Object?>{
      'wage': 'a lot',
      'unit': 'year',
      'colour': 'red',
    };
    for (final MapEntry(key: name, :value) in bad.entries) {
      final result = await say('form.fill', {
        'values': {'note': 'ok', name: value}
      });
      expect(result.code, ActionCodes.badArgs, reason: name);
      expect(result.say['field'], name);
    }
    expect(form.note.text, isEmpty);
    expect(
        (await say('form.fill', {'values': 'wage'})).code, ActionCodes.badArgs);
  });

  testWidgets('sending waits for the user to confirm', (t) async {
    await t.pumpWidget(const MaterialApp(home: _Form()));
    final form = t.state<_FormState>(find.byType(_Form));
    approve = false;
    expect((await say('form.submit')).code, ActionCodes.declined);
    expect(form.sent, 0);
    approve = true;
    expect((await say('form.submit')).ok, isTrue);
    expect(form.sent, 1);
  });

  testWidgets('a page without inputs offers no form actions', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect((await say('form.fill', {'values': {}})).code,
        ActionCodes.notAvailable);
    expect((await say('form.submit')).code, ActionCodes.notAvailable);
  });

  testWidgets('the publish page takes a hire request in one go', (t) async {
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(TestScope(
        repos: repos,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: const MaterialApp(home: PublishPage())));
    await t.pumpAndSettle();
    expect(VoiceScreens.current!.screenId, 'demand.publish');

    final filled = await say('form.fill', {
      'values': {'type': DemandType.hire.name, 'headcount': 2, 'wage': 15000}
    });
    expect(filled.ok, isTrue, reason: '${filled.code} ${filled.say}');
    await t.pumpAndSettle();
    // The wizard reaches the wage on its second step.
    expect(find.text('15000'), findsNothing);
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    expect(find.text('15000'), findsOneWidget);
  });
}
