import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const RealBuzzingIdeApp());
}

class RealBuzzingIdeApp extends StatelessWidget {
  const RealBuzzingIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RealBuzzingIdentifier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF252526),
          elevation: 0,
        ),
        fontFamily: 'monospace',
      ),
      home: const HomeScreen(),
    );
  }
}
