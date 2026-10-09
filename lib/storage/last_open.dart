import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which design is open in the editor, so a page reload or an app
/// restart can bring the user straight back to it. Cleared when the user
/// leaves the editor normally. Failures are ignored: this is a convenience.
class LastOpenProject {
  static const _key = 'editing-project';

  static Future<String?> read() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, id);
      }
    } catch (_) {}
  }
}
