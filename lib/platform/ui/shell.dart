import 'package:flutter/material.dart';
import '../../app/settings.dart';
import 'backup/backup_page.dart';
import 'discover/discover_page.dart';
import 'me/me_page.dart';
import 'projects/projects_page.dart';
import 'showcase/feed_page.dart';
import 'theme.dart';

/// Shell tabs, in order.
abstract final class ShellTab {
  static const home = 0, design = 1, work = 2, me = 3;
}

/// Lets nested pages switch the shell tab, e.g. "open my copy".
class ShellNav extends InheritedWidget {
  const ShellNav({super.key, required this.go, required super.child});
  final void Function(int tab) go;
  static ShellNav? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNav>();

  /// Closes pushed pages and shows [tab].
  static void goFrom(BuildContext context, int tab) {
    final nav = of(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    nav?.go(tab);
  }

  @override
  bool updateShouldNotify(ShellNav old) => false;
}

/// The app shell. Everything turns around house designs: the home feed of
/// published designs, my own designs, the work board where builders find
/// the houses that are hiring, and Me. The design tool keeps the drafting
/// look; everything else uses the platform look.
class PlatformShell extends StatefulWidget {
  const PlatformShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  late int tab = widget.initialTab;
  final reload = ReloadNotifier();

  @override
  void dispose() {
    reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final drafting = Theme.of(context);
    return PlatformReload(
        notifier: reload,
        child: ShellNav(
            go: (i) => setState(() => tab = i),
            child: PlatformTheme(
                child: Builder(
                    builder: (context) => Scaffold(
                        body: IndexedStack(index: tab, children: [
                          const FeedPage(),
                          ProjectsPage(drafting: drafting, reload: reload),
                          const DiscoverPage(),
                          const MePage(),
                        ]),
                        bottomNavigationBar: DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border(
                                    top: BorderSide(
                                        color: YTokens.of(context).line))),
                            child: NavigationBar(
                                selectedIndex: tab,
                                onDestinationSelected: (i) =>
                                    setState(() => tab = i),
                                destinations: [
                                  NavigationDestination(
                                      icon: const Icon(Icons.explore_outlined),
                                      selectedIcon: const Icon(Icons.explore),
                                      label: tr3('发现', 'Шабыт', 'Идеи')),
                                  NavigationDestination(
                                      icon: const Icon(
                                          Icons.architecture_outlined),
                                      selectedIcon:
                                          const Icon(Icons.architecture),
                                      label: tr3(
                                          '我的设计', 'Жобаларым', 'Мои проекты')),
                                  NavigationDestination(
                                      icon: const Icon(Icons.handyman_outlined),
                                      selectedIcon: const Icon(Icons.handyman),
                                      label: tr3('招工', 'Жұмыс', 'Работа')),
                                  NavigationDestination(
                                      icon: const Icon(Icons.person_outline),
                                      selectedIcon: const Icon(Icons.person),
                                      label: tr3('我的', 'Менің', 'Профиль')),
                                ])))))));
  }
}
