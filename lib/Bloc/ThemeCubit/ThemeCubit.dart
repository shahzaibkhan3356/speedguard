import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/AppTheme.dart'; // ✅ Correct import with same case

class ThemeCubit extends Cubit<ThemeData> {
  static const _themeKey = 'app_theme_mode';

  ThemeCubit() : super(AppTheme.darkTheme) {
    _loadTheme();
  }

  bool get isDark => state == AppTheme.darkTheme;

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (isDark) {
      emit(AppTheme.lightTheme); // ✅ Now accessible
      await prefs.setBool(_themeKey, false);
    } else {
      emit(AppTheme.darkTheme);
      await prefs.setBool(_themeKey, true);
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool(_themeKey) ?? true;
    emit(isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme);
  }
}
