import 'package:flutter/material.dart';
import '../../app/settings.dart';
import 'backup/backup_page.dart';
import 'chat/inbox_page.dart';
import 'explore/explore_page.dart';
import 'me/me_page.dart';
import 'projects/projects_page.dart';
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

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final drafting = Theme.of(context);
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
            child: PlatformTheme(
                child: Builder(
                    builder: (context) => Scaffold(
                        body: Column(children: [
                          if (context.isDemo)
                            SafeArea(
                                bottom: false,
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    child: Text(
                                        tr3(
                                            '演示模式 · 平台数据重启后重置，本地设计保留',
                                            'Демо · платформа деректері қайта іске қосқанда өшеді, жергілікті жобалар сақталады',
                                            'Демо · данные платформы сбрасываются, локальные проекты сохраняются'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                YTokens.of(context).muted)))),
                          Expanded(
                              child: MotionIndexedStack(index: tab, children: [
                            ExplorePage(segment: segment),
                            ProjectsPage(
                                drafting: drafting,
                                reload: reload,
                                createRequest: newDesign),
                            const InboxPage(),
                            const MePage(),
                          ])),
                        ]),
                        bottomNavigationBar: NavigationBar(
                            selectedIndex: tab,
                            onDestinationSelected: (i) =>
                                setState(() => tab = i),
                            destinations: [
                              NavigationDestination(
                                  icon: const Icon(Icons.explore_outlined),
                                  selectedIcon: const Icon(Icons.explore),
                                  label: tr3('发现', 'Шолу', 'Обзор')),
                              NavigationDestination(
                                  icon: const Icon(Icons.home_work_outlined),
                                  selectedIcon: const Icon(Icons.home_work),
                                  label: tr3('我的房子', 'Үйлерім', 'Мои дома')),
                              NavigationDestination(
                                  icon: const InboxNavIcon(),
                                  selectedIcon:
                                      const InboxNavIcon(selected: true),
                                  label: tr3('消息', 'Хабар', 'Чаты')),
                              NavigationDestination(
                                  icon: const Icon(Icons.person_outline),
                                  selectedIcon: const Icon(Icons.person),
                                  label: tr3('我的', 'Менің', 'Профиль')),
                            ]))))));
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
