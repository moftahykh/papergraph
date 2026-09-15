import 'package:flutter/material.dart';

@immutable
class ThemeState {
  final ThemeMode themeMode;
  final bool isDark;

  const ThemeState({this.themeMode = ThemeMode.dark, this.isDark = true});

  ThemeState copyWith({ThemeMode? themeMode, bool? isDark}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      isDark: isDark ?? this.isDark,
    );
  }
}
