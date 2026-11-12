import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart' as motor;
import '../../app/settings.dart';
import 'backup/backup_page.dart';
import 'chat/inbox_page.dart';
import 'explore/explore_page.dart';
import 'me/me_page.dart';
import 'projects/projects_page.dart';
import 'components.dart';
import 'theme.dart';
import 'scope.dart';
import '../../motion/motion.dart';

/// Tabs of the app shell, in order.
abstract final class ShellTab {
  static const explore = 0, houses = 1, messages = 2, me = 3;
}

/// The app shell: Discover, My houses, Messages and Me. Every business
/// object hangs off one house: Discover shows houses, work and people;
/// My houses shows where each of my houses stands. The design tool keeps
/// the drafting look; everything else uses the platform look.
class PlatformShell extends StatefulWidget {
  const PlatformShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  late int tab = widget.initialTab;

  /// The bar tucks into a smaller, icon-only pill while the reader scrolls
  /// down a page, and opens again on the way back up or near the top.
  bool compact = false;

  /// Each tab's main list, so tapping the open tab again goes back to the
  /// top.
  final scrollers = [for (var i = 0; i < 4; i++) ScrollController()];
  final reload = ReloadNotifier();
  final segment = ValueNotifier<int?>(null);
  final newDesign = ReloadNotifier();

  @override
  void dispose() {
    reload.dispose();
    segment.dispose();
    newDesign.dispose();
    for (final c in scrollers) {
      c.dispose();
    }
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final delta = n.scrollDelta ?? 0;
    final next = n.metrics.pixels <= 48
        ? false
        : delta > 4
            ? true
            : delta < -4
                ? false
                : compact;
    if (next != compact) setState(() => compact = next);
    return false;
  }

  /// Switches tab with a tick; on the open tab, scrolls it back to the top.
  void _select(int i) {
    if (i == tab) {
      final c = scrollers[i];
      if (!c.hasClients) return;
      HapticFeedback.selectionClick();
      for (final position in c.positions) {
        if (position.pixels <= 0) continue;
        position.animateTo(0, duration: Motion.slow, curve: Motion.settle);
      }
      if (compact) setState(() => compact = false);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      tab = i;
      compact = false;
    });
  }

  /// Keeps the pages' state when the window crosses the wide breakpoint
  /// and the navigation moves between the bottom bar and the side rail.
  final _pagesKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final drafting = Theme.of(context);
    final destinations = [
      (
        const Icon(Icons.explore_outlined),
        const Icon(Icons.explore),
        tr3('发现', 'Шолу', 'Обзор')
      ),
      (
        const Icon(Icons.home_work_outlined),
        const Icon(Icons.home_work),
        tr3('我的房子', 'Үйлерім', 'Мои дома')
      ),
      (
        const InboxNavIcon(),
        const InboxNavIcon(selected: true),
        tr3('消息', 'Хабар', 'Чаты')
      ),
      (
        const Icon(Icons.person_outline),
        const Icon(Icons.person),
        tr3('我的', 'Менің', 'Профиль')
      ),
    ];
    void select(int i) => _select(i);
    // Each tab is its own entrance: its first rows rise in once.
    Widget page(int i, Widget child) => StaggerScope(
        child: PrimaryScrollController(controller: scrollers[i], child: child));
    return PlatformReload(
        notifier: reload,
        child: ShellNav(
            go: (i, {exploreSegment}) => setState(() {
                  tab = i;
                  if (exploreSegment != null) segment.value = exploreSegment;
                }),
            drafting: drafting,
            newDesign: () {
              setState(() => tab = ShellTab.houses);
              // Let the houses tab build before opening its picker.
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => newDesign.bump());
            },
            child: PlatformTheme(child: Builder(builder: (context) {
              final t = YTokens.of(context);
              // Phones get the bottom bar; tablets and desktop a side rail,
              // so four icons are not spread across a wide window.
              final wide = MediaQuery.sizeOf(context).width >= yWide;
              final pages = MotionIndexedStack(
                  key: _pagesKey,
                  index: tab,
                  children: [
                    page(ShellTab.explore, ExplorePage(segment: segment)),
                    page(
                        ShellTab.houses,
                        ProjectsPage(
                            drafting: drafting,
                            reload: reload,
                            createRequest: newDesign)),
                    page(ShellTab.messages, const InboxPage()),
                    page(ShellTab.me, const MePage()),
                  ]);
              return Scaffold(
                  // The bar floats over the pages, which scroll under its
                  // glass; the scaffold reports its height as padding.
                  extendBody: !wide,
                  body: Column(children: [
                    if (context.isDemo)
                      ColoredBox(
                          color: t.surface,
                          child: const SafeArea(
                              bottom: false, child: DemoNotice())),
                    Expanded(
                        // The demo notice already sits below the status
                        // bar; neither the pages nor the side rail may
                        // leave room for it a second time.
                        child: MediaQuery.removePadding(
                            context: context,
                            removeTop: context.isDemo,
                            child: wide
                                ? Row(children: [
                                SafeArea(
                                    right: false,
                                    child: NavigationRail(
                                        key: const Key('shell-rail'),
                                        selectedIndex: tab,
                                        onDestinationSelected: select,
                                        labelType:
                                            NavigationRailLabelType.all,
                                        groupAlignment: -0.9,
                                        minWidth: 88,
                                        destinations: [
                                          for (final (icon, selected, label)
                                              in destinations)
                                            NavigationRailDestination(
                                                icon: icon,
                                                selectedIcon: selected,
                                                label: Text(label)),
                                        ])),
                                VerticalDivider(width: 1, color: t.line),
                                Expanded(child: pages),
                              ])
                                : NotificationListener<
                                        ScrollUpdateNotification>(
                                    onNotification: _onScroll,
                                    child: pages))),
                  ]),
                  bottomNavigationBar: wide
                      ? null
                      : ShellBar(
                          key: const Key('shell-bar'),
                          selected: tab,
                          compact: compact,
                          onSelect: select,
                          destinations: destinations));
            }))));
  }
}

/// Lets pages switch shell tabs (e.g. "＋ → design" opens My houses) and
/// open the design tool with its own drafting look.
class ShellNav extends InheritedWidget {
  const ShellNav(
      {super.key,
      required this.go,
      required this.drafting,
      required this.newDesign,
      required super.child});
  final void Function(int tab, {int? exploreSegment}) go;
  final ThemeData drafting;

  /// Opens My houses with the template picker for a new design.
  final VoidCallback newDesign;

  static ShellNav? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => false;
}

/// ANT's floating tab bar: the sections in one frosted pill and Me apart on
/// the right, so "me" never reads as one more section. The open tab sits
/// on a soft ink highlight (the accent is kept for each screen's main
/// action). While the page scrolls down the bar folds into a smaller,
/// icon-only pill on a spring, and opens again on the way back up.
class ShellBar extends StatelessWidget {
  const ShellBar(
      {super.key,
      required this.selected,
      required this.compact,
      required this.onSelect,
      required this.destinations});
  final int selected;
  final bool compact;
  final ValueChanged<int> onSelect;
  final List<(Widget, Widget, String)> destinations;

  static const motor.Motion _fold =
      motor.CupertinoMotion.smooth(duration: Duration(milliseconds: 420));

  @override
  Widget build(BuildContext context) {
    final sections = destinations.length - 1;
    return SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        // Very large system text would break the pill; labels top out a
        // little above normal and fit themselves from there.
        child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: motor.SingleMotionBuilder(
                motion: _fold,
                value: compact && !Motion.reduced(context) ? 1.0 : 0.0,
                builder: (context, value, _) {
                  final t = value.clamp(0.0, 1.0);
                  final height = lerpDouble(64, 50, t)!;
                  final side = lerpDouble(16, 40, t)!;
                  return Padding(
                      padding: EdgeInsets.fromLTRB(side, 0, side, 4),
                      child: Row(children: [
                        Expanded(
                            child: _GlassPill(
                                height: height,
                                child: Row(children: [
                                  for (var i = 0; i < sections; i++)
                                    ShellBarTab(
                                        icon: destinations[i].$1,
                                        activeIcon: destinations[i].$2,
                                        label: destinations[i].$3,
                                        selected: selected == i,
                                        fold: t,
                                        onTap: () => onSelect(i)),
                                ]))),
                        const SizedBox(width: 10),
                        _GlassPill(
                            height: height,
                            width: lerpDouble(72, 50, t),
                            child: Row(children: [
                              ShellBarTab(
                                  icon: destinations[sections].$1,
                                  activeIcon: destinations[sections].$2,
                                  label: destinations[sections].$3,
                                  selected: selected == sections,
                                  fold: t,
                                  onTap: () => onSelect(sections)),
                            ])),
                      ]));
                })));
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, required this.height, this.width});
  final Widget child;
  final double height;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YRadius.pill),
            boxShadow: [
              BoxShadow(
                  color: t.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(YRadius.pill),
            child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                        color: t.elevated.withValues(alpha: t.dark ? 0.82 : 0.86),
                        borderRadius: BorderRadius.circular(YRadius.pill),
                        border: Border.all(color: t.line.withValues(alpha: 0.6))),
                    child: child))));
  }
}

/// One place in [ShellBar]: its icon, and a label that folds away.
class ShellBarTab extends StatelessWidget {
  const ShellBarTab(
      {super.key,
      required this.icon,
      required this.activeIcon,
      required this.label,
      required this.selected,
      required this.fold,
      required this.onTap});
  final Widget icon, activeIcon;
  final String label;
  final bool selected;

  /// 0 open, 1 folded to icons only.
  final double fold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final color = selected ? t.ink : t.muted;
    final open = 1 - fold;
    return Expanded(
        child: Semantics(
            button: true,
            selected: selected,
            label: label,
            excludeSemantics: true,
            child: InkWell(
                onTap: onTap,
                customBorder: const StadiumBorder(),
                child: Container(
                    margin: EdgeInsets.all(lerpDouble(5, 4, fold)!),
                    decoration: ShapeDecoration(
                        // Selection is a plain state change: the highlight
                        // sits under the open tab, no slide.
                        color: selected
                            ? t.ink.withValues(alpha: t.dark ? 0.12 : 0.07)
                            : Colors.transparent,
                        shape: const StadiumBorder()),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconTheme.merge(
                              data: IconThemeData(color: color, size: 22),
                              child: selected ? activeIcon : icon),
                          // The label fades first, then gives back its
                          // height so the icons settle in the middle.
                          ClipRect(
                              child: Align(
                                  alignment: Alignment.topCenter,
                                  heightFactor: open,
                                  child: Opacity(
                                      opacity:
                                          (1 - fold * 1.8).clamp(0.0, 1.0),
                                      child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              3, 3, 3, 0),
                                          child: Text(label,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: YFont.tab,
                                                  letterSpacing: -0.2,
                                                  fontWeight: selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                                  color: color)))))),
                        ])))));
  }
}
