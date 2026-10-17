import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/schedule_model.dart';
import 'models/situation_model.dart';
import 'screens/calendar_screen.dart';
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
  bool _isDarkMode = false;
  int _currentIndex = 0;
  List<Situation> _situations = [];
  List<Schedule> _schedules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  List<Situation> _createDefaultPresets() {
    return [
      Situation(
        id: 'preset_work',
        name: '출근',
        tag: '출근',
        iconCodePoint: Icons.work.codePoint,
        colorValue: Colors.blue.toARGB32(),
        items: [
          ChecklistItem(id: 'w1', name: '지갑 / 사원증'),
          ChecklistItem(id: 'w2', name: '무선 이어폰'),
          ChecklistItem(id: 'w3', name: '노트북 & 충전기'),
          ChecklistItem(id: 'w4', name: '텀블러'),
        ],
      ),
      Situation(
        id: 'preset_gym',
        name: '운동',
        tag: '운동',
        iconCodePoint: Icons.fitness_center.codePoint,
        colorValue: Colors.orange.toARGB32(),
        items: [
          ChecklistItem(id: 'g1', name: '운동복 & 양말'),
          ChecklistItem(id: 'g2', name: '실내 운동화'),
          ChecklistItem(id: 'g3', name: '개인 물통 / 쉐이커'),
          ChecklistItem(id: 'g4', name: '운동 스트랩'),
        ],
      ),
      Situation(
        id: 'preset_trip',
        name: '여행',
        tag: '여행',
        iconCodePoint: Icons.flight_takeoff.codePoint,
        colorValue: Colors.teal.toARGB32(),
        items: [
          ChecklistItem(id: 't1', name: '신분증 / 여권'),
          ChecklistItem(id: 't2', name: '보조배터리 & 케이블'),
          ChecklistItem(id: 't3', name: '세면도구 파우치'),
          ChecklistItem(id: 't4', name: '상비약'),
        ],
      ),
    ];
  }

  Future<void> _loadInitialData() async {
    final isDark = await StorageService.loadIsDarkMode();
    var situations = await StorageService.loadSituations();
    final schedules = await StorageService.loadSchedules();

    if (situations.isEmpty) {
      situations = _createDefaultPresets();
      await StorageService.saveSituations(situations);
    }

    if (!mounted) return;
    setState(() {
      _isDarkMode = isDark;
      _situations = situations;
      _schedules = schedules;
      _isLoading = false;
    });
  }

  Future<void> _toggleDarkMode() async {
    HapticFeedback.selectionClick();
    final nextMode = !_isDarkMode;
    setState(() => _isDarkMode = nextMode);
    await StorageService.saveIsDarkMode(nextMode);
  }

  Future<void> _handleExportBackup(BuildContext context) async {
    HapticFeedback.selectionClick();
    try {
      final path = await StorageService.exportBackupToFile();
      if (!context.mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('백업 파일이 저장되었습니다: $path')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('백업 실패: $e')),
      );
    }
  }

  Future<void> _handleImportBackup(BuildContext context) async {
    HapticFeedback.selectionClick();
    try {
      final success = await StorageService.importBackupFromFile();
      if (!success) return;
      await _loadInitialData();
      if (!context.mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('백업 데이터를 성공적으로 복원했습니다!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복원 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Bygo',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: Builder(
        builder: (innerContext) {
          return Scaffold(
            appBar: AppBar(
              title: const Text( //title
                'Project Bygo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  tooltip: '백업 파일 저장 (.json)',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _handleExportBackup(innerContext),
                ),
                IconButton(
                  tooltip: '백업 파일 불러오기 (.json)',
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: () => _handleImportBackup(innerContext),
                ),
                IconButton(
                  tooltip: _isDarkMode ? '라이트 모드로 전환' : '다크 모드로 전환',
                  icon: Icon(
                    _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  ),
                  onPressed: _toggleDarkMode,
                ),
              ],
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: _currentIndex,
                    children: [
                      CalendarScreen(
                        schedules: _schedules,
                        situations: _situations,
                        onSchedulesChanged: (updated) {
                          setState(() => _schedules = updated);
                          StorageService.saveSchedules(updated);
                        },
                        onSituationsChanged: (updated) {
                          setState(() => _situations = updated);
                          StorageService.saveSituations(updated);
                        },
                      ),
                      SituationScreen(
                        situations: _situations,
                        onSituationsChanged: (updated) {
                          setState(() => _situations = updated);
                          StorageService.saveSituations(updated);
                        },
                      ),
                    ],
                  ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) {
                HapticFeedback.selectionClick();
                setState(() => _currentIndex = idx);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: '캘린더',
                ),
                NavigationDestination(
                  icon: Icon(Icons.backpack_outlined),
                  selectedIcon: Icon(Icons.backpack),
                  label: '상황·소지품',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}