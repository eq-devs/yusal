import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() => runApp(const ProviderScope(child: HouseApp()));

class HouseApp extends StatelessWidget {
  const HouseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '自建房设计',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff526b5b),
          useMaterial3: true,
        ),
        home: const Scaffold(
          body: SafeArea(
            child:
                Center(child: Text('自建房设计工具', style: TextStyle(fontSize: 24))),
          ),
        ),
      );
}
