import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/ui/widgets.dart';

/// Closing a filter sheet keeps the filter; picking "all" clears it.
void main() {
  Future<List<(String?,)?>> run(
      WidgetTester tester, Future<void> Function() act) async {
    final results = <(String?,)?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async => results.add(
                        await pickFilter<String>(
                            context, 'Region', 'All', [('ala', 'Almaty')],
                            selected: 'ala')),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act();
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('closing the sheet returns null', (tester) async {
    final r = await run(tester, () => tester.tapAt(const Offset(10, 10)));
    expect(r, [null]);
  });

  testWidgets('"all" returns an empty choice', (tester) async {
    final r = await run(tester, () => tester.tap(find.text('All')));
    expect(r, [(null,)]);
  });

  testWidgets('a value returns that value', (tester) async {
    final r = await run(tester, () => tester.tap(find.text('Almaty')));
    expect(r, [('ala',)]);
  });
}
