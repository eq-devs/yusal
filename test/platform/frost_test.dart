import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/shared/ui/widgets.dart';

/// Frosted surfaces blur only where the GPU affords it (see [frostedGlass]).
void main() {
  Future<double> pump(WidgetTester t, TargetPlatform platform) async {
    late double alpha;
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(builder: (context) {
          alpha = glassAlpha(context, 0.88);
          return const Frost(sigma: 14, child: SizedBox(height: 40));
        })));
    return alpha;
  }

  testWidgets('iOS keeps the glass blur and its see-through tint', (t) async {
    expect(await pump(t, TargetPlatform.iOS), 0.88);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('Android draws a near-solid tint without a blur', (t) async {
    expect(await pump(t, TargetPlatform.android), 0.96);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('debugFrostedGlass overrides the platform', (t) async {
    debugFrostedGlass = true;
    addTearDown(() => debugFrostedGlass = null);
    await pump(t, TargetPlatform.android);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
