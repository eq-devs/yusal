import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/motion/motion.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
    home: Builder(
        builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(body: child))));

/// The scale the finder's widget is painted at, whatever applies it.
double _scaleOf(WidgetTester tester, Finder f) {
  final box = tester.renderObject<RenderBox>(f);
  // x scale only: a 2D scale leaves z at 1.
  return box.getTransformTo(null).entry(0, 0);
}

void main() {
  testWidgets('Stagger keeps its row alive and ends fully opaque',
      (tester) async {
    await tester.pumpWidget(_app(Column(children: [
      for (var i = 0; i < 3; i++) Stagger(index: i + 1, child: Text('row $i')),
    ])));
    final fade = find.ancestor(
        of: find.text('row 2'), matching: find.byType(FadeTransition));
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, lessThan(1));
    final before = tester.element(find.text('row 2'));
    await tester.pumpAndSettle();
    // The same element: the reveal ending must not rebuild the row anew.
    expect(tester.element(find.text('row 2')), same(before));
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
  });

  testWidgets('Stagger shows rows at once under reduce motion', (tester) async {
    await tester.pumpWidget(
        _app(const Stagger(index: 2, child: Text('row')), reduced: true));
    expect(find.ancestor(of: find.text('row'), matching: find.byType(Opacity)),
        findsNothing);
    expect(
        find.ancestor(of: find.text('row'), matching: find.byType(Transform)),
        findsNothing);
  });

  testWidgets('Stagger skips rows past the cap', (tester) async {
    await tester.pumpWidget(
        _app(const Stagger(index: Motion.staggerCap + 1, child: Text('late'))));
    expect(find.ancestor(of: find.text('late'), matching: find.byType(Opacity)),
        findsNothing);
  });

  testWidgets('Pressable shrinks while held and returns to 1 on release',
      (tester) async {
    await tester.pumpWidget(_app(Center(
        child: Pressable(
            child: Container(
                width: 120,
                height: 80,
                color: Colors.red,
                child: const Text('card'))))));
    final g = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump(Motion.pressDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_scaleOf(tester, find.text('card')), lessThan(1));
    await g.up();
    await tester.pumpAndSettle();
    expect(_scaleOf(tester, find.text('card')), closeTo(1, 1e-3));
  });

  testWidgets('Pressable does nothing when disabled', (tester) async {
    await tester.pumpWidget(_app(Center(
        child: Pressable(
            enabled: false,
            child: Container(
                width: 120, height: 80, child: const Text('card'))))));
    final g = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scaleOf(tester, find.text('card')), closeTo(1, 1e-3));
    await g.up();
  });

  testWidgets('PopOnActive hops above 1 mid-way and lands on 1',
      (tester) async {
    Widget build(bool on) => _app(Center(
        child: PopOnActive(active: on, child: const Icon(Icons.favorite))));
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pump(Motion.pop * 0.35);
    expect(_scaleOf(tester, find.byIcon(Icons.favorite)), greaterThan(1));
    await tester.pumpAndSettle();
    expect(_scaleOf(tester, find.byIcon(Icons.favorite)), closeTo(1, 1e-3));
  });

  testWidgets('PopOnActive stays still on un-save', (tester) async {
    Widget build(bool on) => _app(Center(
        child: PopOnActive(active: on, child: const Icon(Icons.favorite))));
    await tester.pumpWidget(build(true));
    await tester.pumpWidget(build(false));
    await tester.pump(Motion.pop * 0.35);
    expect(_scaleOf(tester, find.byIcon(Icons.favorite)), closeTo(1, 1e-3));
  });

  testWidgets('same HeroSource key twice on a screen pushes cleanly',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: ListView(children: [
                  for (final label in ['carousel', 'list'])
                    GestureDetector(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                    body: HeroTarget(
                                        heroKey: 'house:1',
                                        borderRadius: BorderRadius.circular(24),
                                        child: Container(
                                            height: 300,
                                            color: Colors.blue,
                                            child: const Text('detail')))))),
                        child: HeroSource(
                            heroKey: 'house:1',
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                                height: 120,
                                color: Colors.blue,
                                child: Text(label)))),
                ])))));
    expect(find.byType(Hero), findsNWidgets(2));
    await tester.tap(find.text('list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.ancestor(of: find.text('detail'), matching: find.byType(Hero)),
        findsOneWidget);

    // Back, then open again from elsewhere without a touch: no flight.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('HeroTarget without a touched source has no Hero',
      (tester) async {
    await tester.pumpWidget(
        _app(const HeroTarget(heroKey: 'house:9', child: Text('detail'))));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('StateSwitcher and FadeSwitcher settle on the new child',
      (tester) async {
    Widget build(bool done) => _app(Column(children: [
          StateSwitcher(
              child: KeyedSubtree(
                  key: ValueKey(done),
                  child: Text(done ? 'applied' : 'apply'))),
          FadeSwitcher(
              child: done
                  ? const Text('content', key: ValueKey('loaded'))
                  : const Text('skeleton', key: ValueKey('loading'))),
        ]));
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(find.text('applied'), findsOneWidget);
    expect(find.text('apply'), findsNothing);
    expect(find.text('content'), findsOneWidget);
    expect(find.text('skeleton'), findsNothing);
  });

  testWidgets('showMotionSheet staggers rows inside its scope', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    var scoped = false;
    showMotionSheet<void>(
        context: ctx,
        haptic: false,
        builder: (c) {
          scoped = StaggerScope.of(c);
          return const Text('sheet');
        });
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(scoped, isTrue);
    expect(StaggerScope.of(ctx), isFalse);
  });

  testWidgets('MotionIndexedStack builds pages lazily and keeps them',
      (tester) async {
    Widget page(String name) => Text(name);
    Widget build(int i) =>
        _app(MotionIndexedStack(index: i, children: [page('a'), page('b')]));
    await tester.pumpWidget(build(0));
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b', skipOffstage: false), findsNothing);
    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
    await tester.pumpWidget(build(0));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('MotionTabView follows its TabController', (tester) async {
    await tester.pumpWidget(_app(DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'one'), Tab(text: 'two')]),
          const Expanded(
              child: MotionTabView(
                  children: [Text('page one'), Text('page two')])),
        ]))));
    expect(find.text('page one'), findsOneWidget);
    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();
    expect(find.text('page two'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
