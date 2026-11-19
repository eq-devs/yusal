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
  // A row at rest: fully opaque and in place.
  double opacityOf(WidgetTester tester, String text) => tester
      .widgetList<Opacity>(
          find.ancestor(of: find.text(text), matching: find.byType(Opacity)))
      .fold(1.0, (o, w) => o * w.opacity);
  double liftOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('Stagger rises rows in one after another and rests at 1',
      (tester) async {
    await tester.pumpWidget(_app(Column(children: [
      for (var i = 0; i < 3; i++) Stagger(index: i + 1, child: Text('row $i')),
    ])));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, 'row 0'), greaterThan(opacityOf(tester, 'row 2')));
    expect(opacityOf(tester, 'row 2'), lessThan(1));
    final rest = <double>[];
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(opacityOf(tester, 'row $i'), 1);
      rest.add(liftOf(tester, 'row $i'));
    }
    // Rebuilding a rested row keeps it still: the entrance plays once.
    await tester.pumpWidget(_app(Column(children: [
      for (var i = 0; i < 3; i++) Stagger(index: i + 1, child: Text('row $i')),
    ])));
    expect(opacityOf(tester, 'row 2'), 1);
    expect(liftOf(tester, 'row 2'), rest[2]);
  });

  testWidgets('Stagger keeps its child\'s state through the entrance',
      (tester) async {
    final key = GlobalKey<State<StatefulWidget>>();
    await tester.pumpWidget(_app(Stagger(
        index: 1,
        child: StatefulBuilder(key: key, builder: (_, __) => const Text('row')))));
    final before = key.currentState;
    await tester.pumpAndSettle();
    expect(key.currentState, same(before));
  });

  testWidgets('Stagger shows rows at once under reduce motion', (tester) async {
    await tester.pumpWidget(
        _app(const Stagger(index: 2, child: Text('row')), reduced: true));
    expect(opacityOf(tester, 'row'), 1);
  });

  testWidgets('Stagger skips rows past the cap', (tester) async {
    await tester.pumpWidget(
        _app(const Stagger(index: Motion.staggerCap + 1, child: Text('late'))));
    expect(opacityOf(tester, 'late'), 1);
  });

  testWidgets('a scope rises its first burst in and lets later rows appear',
      (tester) async {
    final more = ValueNotifier(false);
    await tester.pumpWidget(_app(StaggerScope(
        child: ValueListenableBuilder<bool>(
            valueListenable: more,
            builder: (_, show, __) => Column(children: [
                  const Stagger(child: Text('first')),
                  const Stagger(child: Text('second')),
                  if (show) const Stagger(child: Text('late')),
                ])))));
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacityOf(tester, 'second'), lessThan(1));
    await tester.pumpAndSettle();
    // The burst is measured on the wall clock.
    await tester.runAsync(() => Future<void>.delayed(Motion.burst));
    more.value = true;
    await tester.pump();
    expect(opacityOf(tester, 'late'), 1);
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

  testWidgets('PopOnActive dips, bounces past 1 and lands on 1',
      (tester) async {
    Widget build(bool on) => _app(Center(
        child: PopOnActive(active: on, child: const Icon(Icons.favorite))));
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    // Dips first, then the bouncy spring carries it past 1.
    await tester.pump(const Duration(milliseconds: 16));
    expect(_scaleOf(tester, find.byIcon(Icons.favorite)), lessThan(1));
    var peak = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _scaleOf(tester, find.byIcon(Icons.favorite));
      if (s > peak) peak = s;
    }
    expect(peak, greaterThan(1));
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

  testWidgets('a cover moved by a GlobalKey mid-flight keeps the flight',
      (tester) async {
    // The house page swaps its skeleton for the loaded page while the
    // card's picture is still flying; the cover moves under a GlobalKey.
    final loaded = ValueNotifier(false);
    final cover = GlobalKey();
    Widget target() => HeroTarget(
        key: cover,
        heroKey: 'house:2',
        cropInFlight: false,
        child: Container(
            height: 300, color: Colors.blue, child: const Text('detail')));
    Widget page(BuildContext _) => ValueListenableBuilder<bool>(
        valueListenable: loaded,
        builder: (_, done, __) => done
            ? Scaffold(body: Column(children: [target(), const Text('facts')]))
            : Scaffold(
                body: Padding(padding: EdgeInsets.zero, child: target())));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: GestureDetector(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: page)),
                    child: HeroSource(
                        heroKey: 'house:2',
                        child: Container(
                            height: 120,
                            color: Colors.blue,
                            child: const Text('card'))))))));
    await tester.tap(find.text('card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    loaded.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    // Still one picture: the flying one. A rebuilt target would show its
    // own copy at the landing spot while the flight fades out.
    expect(find.text('detail'), findsOneWidget);
    // Not cropped: laid out at the flight's size.
    expect(
        find.ancestor(
            of: find.text('detail'), matching: find.byType(FittedBox)),
        findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('facts'), findsOneWidget);
    expect(find.text('detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('PressTint: a quick tap shows one even tint, then clears',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            splashFactory: PressTint.splashFactory,
            highlightColor: Colors.transparent),
        home: Scaffold(
            body: Center(
                child: InkWell(
                    onTap: () => taps++,
                    borderRadius: BorderRadius.circular(12),
                    child: const SizedBox(
                        width: 120, height: 48, child: Text('press')))))));
    final ink = Material.of(tester.element(find.text('press')));
    List<InkFeature> features() =>
        (ink as dynamic).debugInkFeatures as List<InkFeature>? ?? const [];

    await tester.tap(find.text('press'));
    await tester.pump();
    expect(taps, 1);
    expect(features().whereType<PressTint>(), hasLength(1));
    expect(features().whereType<InkSplash>(), isEmpty);
    expect(features().whereType<InkRipple>(), isEmpty);
    expect(features().whereType<InkSparkle>(), isEmpty);
    // Released at once, it still comes all the way up before fading.
    await tester.pump(Motion.press ~/ 2);
    expect(features().whereType<PressTint>(), hasLength(1));
    await tester.pumpAndSettle();
    expect(features().whereType<PressTint>(), isEmpty);
  });

  testWidgets('PressTint holds while pressed and fades when it scrolls away',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: PressTint.splashFactory),
        home: Scaffold(
            body: ListView(children: [
          for (var i = 0; i < 30; i++)
            ListTile(title: Text('row $i'), onTap: () {}),
        ]))));
    final ink = Material.of(tester.element(find.text('row 1')));
    List<InkFeature> features() =>
        (ink as dynamic).debugInkFeatures as List<InkFeature>? ?? const [];
    final g = await tester.startGesture(tester.getCenter(find.text('row 1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(features().whereType<PressTint>(), hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(features().whereType<PressTint>(), hasLength(1));
    await g.moveBy(const Offset(0, -80));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(features().whereType<PressTint>(), isEmpty);
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
