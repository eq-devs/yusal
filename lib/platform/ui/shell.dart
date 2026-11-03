import 'package:flutter/material.dart';
import '../../app/settings.dart';
import 'backup/backup_page.dart';
import 'discover/discover_page.dart';
import 'me/me_page.dart';
import 'projects/projects_page.dart';
import 'theme.dart';

/// The app shell: Discover, My projects and Me. The design tool inside
/// "My projects" keeps the drafting look; everything else uses the
/// platform look.
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
        child: PlatformTheme(
            child: Builder(
                builder: (context) => Scaffold(
                    body: IndexedStack(index: tab, children: [
                      const DiscoverPage(),
                      ProjectsPage(drafting: drafting, reload: reload),
                      const MePage(),
                    ]),
                    bottomNavigationBar: NavigationBar(
                        selectedIndex: tab,
                        onDestinationSelected: (i) => setState(() => tab = i),
                        destinations: [
                          NavigationDestination(
                              icon: const Icon(Icons.search),
                              label: tr3('发现', 'Іздеу', 'Поиск')),
                          NavigationDestination(
                              icon: const Icon(Icons.home_work_outlined),
                              selectedIcon: const Icon(Icons.home_work),
                              label: tr3('我的项目', 'Жобалар', 'Проекты')),
                          NavigationDestination(
                              icon: const Icon(Icons.person_outline),
                              selectedIcon: const Icon(Icons.person),
                              label: tr3('我的', 'Менің', 'Профиль')),
                        ])))));
  }
}
