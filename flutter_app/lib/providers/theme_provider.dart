import 'package:flutter/material.dart';
import '../core/services/hive_service.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDark = true;

  ThemeProvider() {
    _loadTheme();
  }

  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  void _loadTheme() {
    _isDark = HiveService.isDarkMode();
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    await HiveService.setDarkMode(_isDark);
    notifyListeners();
  }
}
