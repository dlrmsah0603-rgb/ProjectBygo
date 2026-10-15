import 'package:flutter/material.dart';
import 'screens/calendar_screen.dart';
import 'screens/situation_screen.dart';

void main() {
  runApp(const BygoApp());
}

class BygoApp extends StatelessWidget {
  const BygoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Bygo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainTabScreen(),
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentIndex == 0
          ? const CalendarScreen()
          : const SituationScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: '캘린더 (001)',
          ),
          NavigationDestination(
            icon: Icon(Icons.backpack_outlined),
            label: '상황/소지품 (002)',
          ),
        ],
      ),
    );
  }
}