import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/ui/unsaved_changes_guard.dart';

void main() {
  testWidgets('submitting a draft blocks the leave dialog', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    var busy = true;
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => UnsavedChangesGuard(
                            hasChanges: () => true,
                            isBusy: () => busy,
                            child: Scaffold(
                                appBar: AppBar(), body: const Text('draft'))))),
                child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('draft'), findsOneWidget);
    busy = false;
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
  testWidgets('cancel leave preserves the draft and discard returns',
      (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final input = TextEditingController(text: '施工需求');
    addTearDown(input.dispose);
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => UnsavedChangesGuard(
                            hasChanges: () => input.text.isNotEmpty,
                            child: Scaffold(
                                appBar: AppBar(),
                                body: TextField(controller: input))))),
                child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('继续编辑'));
    await t.pumpAndSettle();
    expect(find.text('施工需求'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('放弃并返回'));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets('a form that becomes dirty while typing asks before leaving',
      (t) async {
    AppSettings.instance.lang = AppLang.zh;
    final title = TextEditingController(), story = TextEditingController();
    addTearDown(title.dispose);
    addTearDown(story.dispose);
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => UnsavedChangesGuard(
                            hasChanges: () => title.text.isNotEmpty,
                            // A new merged listenable on every build, as the
                            // publish pages pass it.
                            changes: Listenable.merge([title, story]),
                            child: Scaffold(
                                appBar: AppBar(),
                                body: TextField(controller: title))))),
                child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '草稿');
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('继续编辑'), findsOneWidget);
  });
}
