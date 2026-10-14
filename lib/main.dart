import 'package:flutter/material.dart';
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
  int _currentIndex = 1;

  final List<Widget> _pages = [
    const Center(child: Text('다음 단계에서 구현할 001 캘린더 화면입니다.')),
    const SituationScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
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