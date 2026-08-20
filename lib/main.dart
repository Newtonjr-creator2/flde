import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FldeApp());
}

class FldeApp extends StatelessWidget {
  const FldeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FLDE',
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
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
