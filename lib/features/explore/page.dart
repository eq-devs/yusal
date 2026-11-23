import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/discover/page.dart';
import 'package:yusal/features/home/page.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/explore/widgets/create_sheet.dart';
import 'package:yusal/features/shared/motion/motion.dart';
import 'package:yusal/features/shared/brand/brand.dart';
import 'package:yusal/features/shared/brand/yicon.dart';
import 'package:yusal/features/shared/ui/widgets.dart' show ExploreInset;

/// Segments of Discover, in order.
abstract final class ExploreSegment {
  static const houses = 0;
  static const work = 1;
  static const people = 2;
}

/// First tab. One header (wordmark, messages, ＋) and three segments:
/// houses (the plan library), work (open demands) and people (pros).
/// People with a pro card open on "work"; everyone else on "houses".
/// A segment picked by hand wins until the app restarts.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, this.segment});

  /// Lets other pages switch the segment (e.g. "＋ → pick from library").
  final ValueNotifier<int?>? segment;
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  int current = ExploreSegment.houses;
  bool picked = false;
  String? decidedFor;

  @override
  void initState() {
    super.initState();
    widget.segment?.addListener(_external);
  }

  @override
  void dispose() {
    widget.segment?.removeListener(_external);
    _scrolled.dispose();
    super.dispose();
  }

  void _external() {
    final v = widget.segment?.value;
    if (v == null) return;
    _dropKeyboard();
    setState(() {
      _showSegment(v);
      picked = true;
    });
  }

  /// Chooses the default segment once per signed-in account.
  Future<void> _decide() async {
    final me = context.session.currentAccount?.id;
    if (picked || decidedFor == (me ?? '')) return;
    decidedFor = me ?? '';
    if (me == null) {
      if (current != ExploreSegment.houses) {
        setState(() => _showSegment(ExploreSegment.houses));
      }
      return;
    }
    try {
      final pros = await context.read(profileRepositoryProvider).myProfiles();
      if (!mounted || picked) return;
      setState(() => _showSegment(
          pros.isEmpty ? ExploreSegment.houses : ExploreSegment.work));
    } catch (_) {}
  }

  void select(int i) {
    _dropKeyboard();
    setState(() {
      _showSegment(i);
      picked = true;
    });
  }

  /// A search field on the segment being left keeps its focus while it is
  /// hidden: the keyboard would stay up over the new segment and type into
  /// the old one.
  void _dropKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  /// How far the open segment's list has scrolled; the wordmark row
  /// slides away with it and the segment bar stays pinned at the top.
  final _scrolled = ValueNotifier<double>(0);
  final _offsets = <int, double>{};

  /// Heights of the wordmark row and of the whole header, measured after
  /// layout. Until then a close guess keeps the first frame in place.
  double _logoHeight = 60;
  double _headerHeight = 124;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final px = n.metrics.pixels;
    _offsets[current] = px;
    _scrolled.value = px;
    return false;
  }

  void _showSegment(int i) {
    current = i;
    _scrolled.value = _offsets[i] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _decide();
    });
    final t = YTokens.of(context);
    final labels = [
      (YIcon.plan, tr3('房子', 'Үйлер', 'Дома', 'Houses', ky: 'Үйлөр', uz: 'Uylar')),
      (YIcon.contract, tr3('找活', 'Жұмыс', 'Работа', 'Jobs', ky: 'Иштер', uz: 'Ishlar')),
      (YIcon.hire, tr3('找人', 'Шеберлер', 'Мастера', 'Pros', ky: 'Адистер', uz: 'Mutaxassislar')),
    ];
    final logoRow = _Measure(
        onSize: (s) => _logoHeight = s.height,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
            child: Row(children: [
              const Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: YusalLogo(height: 26))),
              IconButton(
                  key: const Key('explore-create'),
                  tooltip: tr3('发布', 'Жариялау', 'Создать', 'Create', ky: 'Түзүү', uz: 'Yaratish'),
                  icon: const YusalIcon(YIcon.add, size: 26),
                  onPressed: () => showCreateSheet(context)),
            ])));
    final tabs = Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
                child: _Segment(
                    key: Key('explore-seg-$i'),
                    icon: labels[i].$1,
                    label: labels[i].$2,
                    selected: current == i,
                    onTap: () => select(i))),
        ]));
    final header = _Measure(
        onSize: (s) {
          if ((s.height - _headerHeight).abs() < 0.5) return;
          setState(() => _headerHeight = s.height);
        },
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [logoRow, tabs]))));
    return Scaffold(
        body: SafeArea(
            bottom: false,
            child: Stack(children: [
              Positioned.fill(
                  child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: ExploreInset(
                          top: _headerHeight,
                          child: MotionIndexedStack(
                              index: current,
                              children: const [
                                HomePage(embedded: true),
                                DiscoverPage(embedded: true, people: false),
                                DiscoverPage(embedded: true, people: true),
                              ])))),
              // The header floats over the list: the wordmark row scrolls
              // off with the page and the segment bar sticks at the top.
              ValueListenableBuilder<double>(
                  valueListenable: _scrolled,
                  child: header,
                  builder: (context, px, header) {
                    final hide = px.clamp(0.0, _logoHeight);
                    final stuck = px >= _logoHeight;
                    return Positioned(
                        top: -hide,
                        left: 0,
                        right: 0,
                        child: AnimatedContainer(
                            duration: Motion.fast,
                            decoration: BoxDecoration(
                                color: t.bg,
                                boxShadow: [
                                  if (stuck)
                                    BoxShadow(
                                        color: t.shadow,
                                        blurRadius: 12,
                                        offset: const Offset(0, 2)),
                                ]),
                            child: header));
                  }),
            ])));
  }
}

/// Reports its child's size after each layout.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({required this.onSize, super.child});
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onSize);
  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) =>
      renderObject.onSize = onSize;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}

class _Segment extends StatelessWidget {
  const _Segment(
      {super.key,
      required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final YIcon icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
            onTap: onTap,
            child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: selected ? t.ink : t.line,
                            width: selected ? 2 : 1))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  YusalIcon(icon,
                      size: 22,
                      color: selected ? t.ink : t.muted,
                      mono: !selected),
                  const SizedBox(height: 2),
                  // With large system text a label would break inside a
                  // word and push its underline below the others': it
                  // stays on one line and shrinks to its third instead.
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: YFont.small,
                              color: selected ? t.ink : t.muted))),
                ]))));
  }
}
