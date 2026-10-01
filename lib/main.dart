import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/house_editor.dart';

void main() => runApp(const ProviderScope(child: HouseApp()));

class HouseApp extends StatelessWidget {
  const HouseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: '自建房设计',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorSchemeSeed: const Color(0xff526b5b),
          scaffoldBackgroundColor: const Color(0xfff6f7f3),
          useMaterial3: true),
      home: const HouseHome());
}
