import 'package:flutter/material.dart';
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
  final reload = ReloadNotifier();
  final segment = ValueNotifier<int?>(null);
  final newDesign = ReloadNotifier();

  @override
  void dispose() {
    reload.dispose();
    segment.dispose();
    newDesign.dispose();
    super.dispose();
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
    void select(int i) => setState(() => tab = i);
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
                    ExplorePage(segment: segment),
                    ProjectsPage(
                        drafting: drafting,
                        reload: reload,
                        createRequest: newDesign),
                    const InboxPage(),
                    const MePage(),
                  ]);
              return Scaffold(
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
                                : pages)),
                  ]),
                  bottomNavigationBar: wide
                      ? null
                      : DecoratedBox(
                          decoration: BoxDecoration(
                              border:
                                  Border(top: BorderSide(color: t.line))),
                          child: NavigationBar(
                              key: const Key('shell-bar'),
                              selectedIndex: tab,
                              onDestinationSelected: select,
                              destinations: [
                                for (final (icon, selected, label)
                                    in destinations)
                                  NavigationDestination(
                                      icon: icon,
                                      selectedIcon: selected,
                                      label: label),
                              ])));
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
