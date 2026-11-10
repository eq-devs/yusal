import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../discover/discover_page.dart';
import '../home/home_page.dart';
import '../scope.dart';
import '../theme.dart';
import 'create_sheet.dart';
import '../../../motion/motion.dart';

/// Segments of Discover, in order.
abstract final class ExploreSegment {
  static const houses = 0, work = 1, people = 2;
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
    super.dispose();
  }

  void _external() {
    final v = widget.segment?.value;
    if (v == null) return;
    setState(() {
      current = v;
      picked = true;
    });
  }

  /// Chooses the default segment once per signed-in account.
  Future<void> _decide() async {
    final me = context.repos.currentAccount?.id;
    if (picked || decidedFor == (me ?? '')) return;
    decidedFor = me ?? '';
    if (me == null) {
      if (current != ExploreSegment.houses)
        setState(() => current = ExploreSegment.houses);
      return;
    }
    try {
      final pros = await context.repos.myProfiles();
      if (!mounted || picked) return;
      setState(() =>
          current = pros.isEmpty ? ExploreSegment.houses : ExploreSegment.work);
    } catch (_) {}
  }

  void select(int i) => setState(() {
        current = i;
        picked = true;
      });

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _decide();
    });
    final labels = [
      (Icons.home_outlined, tr3('房子', 'Үйлер', 'Дома')),
      (Icons.work_outline, tr3('找活', 'Жұмыс', 'Работа')),
      (Icons.groups_outlined, tr3('找人', 'Шеберлер', 'Мастера')),
    ];
    return Scaffold(
        body: SafeArea(
            bottom: false,
            child: Column(children: [
              Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                  child:
                                      Text('Yusal', style: wordmark(t.accent))),
                              IconButton(
                                  key: const Key('explore-create'),
                                  tooltip: tr3('发布', 'Жариялау', 'Создать'),
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => showCreateSheet(context)),
                            ]),
                            const SizedBox(height: 6),
                            Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Row(children: [
                                  for (var i = 0; i < labels.length; i++)
                                    Expanded(
                                        child: _Segment(
                                            key: Key('explore-seg-$i'),
                                            icon: labels[i].$1,
                                            label: labels[i].$2,
                                            selected: current == i,
                                            onTap: () => select(i))),
                                ])),
                          ])))),
              Expanded(
                  child: MotionIndexedStack(index: current, children: const [
                HomePage(embedded: true),
                DiscoverPage(embedded: true, people: false),
                DiscoverPage(embedded: true, people: true),
              ])),
            ])));
  }
}

class _Segment extends StatelessWidget {
  const _Segment(
      {super.key,
      required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
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
                  Icon(icon, size: 22, color: selected ? t.ink : t.muted),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: YFont.small,
                          color: selected ? t.ink : t.muted)),
                ]))));
  }
}
