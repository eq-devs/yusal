import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/settings.dart';
import 'app/tokens.dart';
import 'features/house_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const ProviderScope(child: HouseApp()));
}

class HouseApp extends StatelessWidget {
  const HouseApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return MaterialApp(
            title: tr('自建房设计', 'Үй жобалау'),
            debugShowCheckedModeBanner: false,
            theme: buildTheme(settings.theme == ThemeChoice.night
                ? Tokens.night
                : Tokens.light),
            darkTheme: buildTheme(settings.theme == ThemeChoice.day
                ? Tokens.light
                : Tokens.night),
            themeMode: switch (settings.theme) {
              ThemeChoice.auto => ThemeMode.system,
              ThemeChoice.day => ThemeMode.light,
              ThemeChoice.night => ThemeMode.dark
            },
            builder: (context, child) => AppScope(child: child!),
            home: const HouseHome());
      });
}
