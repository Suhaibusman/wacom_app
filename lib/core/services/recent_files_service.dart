import 'package:shared_preferences/shared_preferences.dart';

class RecentFilesService {
  static const String _key = 'recent_files';

  Future<List<String>> getRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> addRecentFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> files = prefs.getStringList(_key) ?? [];

    // Remove if exists to move to top
    files.remove(path);
    files.insert(0, path);

    // Keep only last 10
    if (files.length > 10) {
      files = files.sublist(0, 10);
    }

    await prefs.setStringList(_key, files);
  }

  Future<void> removeRecentFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> files = prefs.getStringList(_key) ?? [];
    files.remove(path);
    await prefs.setStringList(_key, files);
  }
}
