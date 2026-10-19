import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/schedule_model.dart';
import 'models/situation_model.dart';
import 'screens/calendar_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/situation_screen.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BygoApp());
}

class BygoApp extends StatefulWidget {
  const BygoApp({super.key});

  @override
  State<BygoApp> createState() => _BygoAppState();
}

class _BygoAppState extends State<BygoApp> {
  final StorageService _storage = StorageService();
  final PageController _pageController = PageController();

  List<Schedule> _schedules = [];
  List<Situation> _situations = [];
  ThemeMode _themeMode = ThemeMode.system;
  int _seedColorValue = Colors.indigo.toARGB32();
  bool _showTips = true;
  int _currentIndex = 0;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final schedules = await _storage.loadSchedules();
    final situations = await _storage.loadSituations();
    final themeMode = await _storage.loadThemeMode();
    final seedColor = await _storage.loadSeedColor();
    final showTips = await _storage.loadShowTips();

    if (!mounted) return;
    setState(() {
      _schedules = schedules;
      _situations = situations;
      _themeMode = themeMode;
      _seedColorValue = seedColor;
      _showTips = showTips;
      _isLoaded = true;
    });
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isBlackAndWhite =
        _seedColorValue == SettingsScreen.blackAndWhiteColorValue;

    if (isBlackAndWhite) {
      final isDark = brightness == Brightness.dark;
      final bwScheme = isDark
          ? const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              primaryContainer: Color(0xFF2C2C2C),
              onPrimaryContainer: Colors.white,
              secondary: Color(0xFFD0D0D0),
              onSecondary: Colors.black,
              surface: Color(0xFF121212),
              onSurface: Colors.white,
              surfaceContainerHighest: Color(0xFF262626),
            )
          : const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              primaryContainer: Color(0xFFE6E6E6),
              onPrimaryContainer: Colors.black,
              secondary: Color(0xFF333333),
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              surfaceContainerHighest: Color(0xFFEEEEEE),
            );

      return ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: bwScheme,
        scaffoldBackgroundColor: bwScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: bwScheme.surface,
          foregroundColor: bwScheme.onSurface,
          elevation: 0,
        ),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: Color(_seedColorValue),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bygo',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: !_isLoaded
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Bygo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                centerTitle: false,
              ),
              body: PageView(
                controller: _pageController,
                onPageChanged: (idx) {
                  setState(() => _currentIndex = idx);
                },
                children: [
                  CalendarScreen(
                    schedules: _schedules,
                    situations: _situations,
                    showTips: _showTips,
                    onSchedulesChanged: (updated) {
                      setState(() => _schedules = List.from(updated));
                      _storage.saveSchedules(_schedules);
                    },
                    onSituationsChanged: (updated) {
                      setState(() => _situations = List.from(updated));
                      _storage.saveSituations(_situations);
                    },
                  ),
                  SituationScreen(
                    situations: _situations,
                    schedules: _schedules,
                    showTips: _showTips,
                    onSituationsChanged: (updated) {
                      setState(() => _situations = List.from(updated));
                      _storage.saveSituations(_situations);
                    },
                    onSchedulesChanged: (updated) {
                      setState(() => _schedules = List.from(updated));
                      _storage.saveSchedules(_schedules);
                    },
                  ),
                  SettingsScreen(
                    themeMode: _themeMode,
                    seedColorValue: _seedColorValue,
                    showTips: _showTips,
                    onThemeModeChanged: (mode) {
                      setState(() => _themeMode = mode);
                      _storage.saveThemeMode(mode);
                    },
                    onSeedColorChanged: (colorVal) {
                      setState(() => _seedColorValue = colorVal);
                      _storage.saveSeedColor(colorVal);
                    },
                    onShowTipsChanged: (val) {
                      setState(() => _showTips = val);
                      _storage.saveShowTips(val);
                    },
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (idx) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = idx);
                  _pageController.animateToPage(
                    idx,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                  );
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month),
                    label: '캘린더',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.checklist_rtl_outlined),
                    selectedIcon: Icon(Icons.checklist_rtl),
                    label: '상황·체크리스트',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: '설정',
                  ),
                ],
              ),
            ),
    );
  }
}