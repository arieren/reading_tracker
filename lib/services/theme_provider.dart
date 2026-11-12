import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _loadTheme();
  }
  ThemeMode _themeMode = ThemeMode.light;
  bool _disposed = false;
  ThemeMode get themeMode => _themeMode;
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _themeMode = (prefs.getBool('isDarkMode') ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
