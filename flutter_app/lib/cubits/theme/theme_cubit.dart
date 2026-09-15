import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import 'theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState()) {
    loadTheme();
  }

  void loadTheme() {
    try {
      final isDark = HiveService.isDarkMode();
      emit(
        ThemeState(
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          isDark: isDark,
        ),
      );
    } catch (_) {
      emit(const ThemeState(themeMode: ThemeMode.dark, isDark: true));
    }
  }

  Future<void> toggleTheme() async {
    final newIsDark = !state.isDark;
    try {
      await HiveService.setDarkMode(newIsDark);
    } catch (_) {}
    emit(
      ThemeState(
        themeMode: newIsDark ? ThemeMode.dark : ThemeMode.light,
        isDark: newIsDark,
      ),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final isDark = mode == ThemeMode.dark;
    try {
      await HiveService.setDarkMode(isDark);
    } catch (_) {}
    emit(ThemeState(themeMode: mode, isDark: isDark));
  }
}
