import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModePrefKey = 'hofa_admin_theme_mode';

/// Chế độ sáng/tối cho toàn app — mặc định theo hệ thống, nhớ lựa chọn thủ công qua
/// SharedPreferences (cùng cách device_repository.dart lưu device_id cục bộ) để mở lại app
/// vẫn giữ đúng lựa chọn, không phải bật lại mỗi lần.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModePrefKey);
    if (saved == 'light') {
      state = ThemeMode.light;
    } else if (saved == 'dark') {
      state = ThemeMode.dark;
    }
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeModePrefKey,
      next == ThemeMode.dark ? 'dark' : 'light',
    );
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
      (ref) => ThemeModeController(),
    );
