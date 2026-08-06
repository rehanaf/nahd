import 'package:flutter/material.dart';

import '../core/project_storage.dart';

/// App-level state: theme mode + profile name.
class AppController extends ChangeNotifier {
  String _themeMode = 'device';
  String _profileName = 'Guest';

  String get themeMode => _themeMode;
  String get profileName => _profileName;

  bool isDark(String themeMode) {
    if (themeMode == 'light') return false;
    if (themeMode == 'dark') return true;
    return ThemeMode.system == ThemeMode.dark;
  }

  Brightness brightness(BuildContext context) {
    if (_themeMode == 'light') return Brightness.light;
    if (_themeMode == 'dark') return Brightness.dark;
    return Theme.of(context).brightness;
  }

  static Future<AppController> load() async {
    final c = AppController();
    c._themeMode = await ProjectStorage.getThemeMode();
    c._profileName = await ProjectStorage.getProfileName();
    return c;
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    notifyListeners();
    await ProjectStorage.setThemeMode(mode);
  }

  Future<void> setProfileName(String name) async {
    _profileName = name.trim().isEmpty ? 'Guest' : name.trim();
    notifyListeners();
    await ProjectStorage.setProfileName(_profileName);
  }

  void reset() {
    _themeMode = 'device';
    _profileName = 'Guest';
    notifyListeners();
  }
}
