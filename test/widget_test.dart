import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/main.dart';

void main() {
  testWidgets('shows the house design app home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HouseApp()));
    expect(find.text('自建房设计工具'), findsOneWidget);
  });
}
