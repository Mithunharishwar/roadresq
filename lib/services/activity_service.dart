import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ActivityService {
  static const String userActivityKey = 'user_recent_activity';
  static const String mechanicActivityKey = 'mechanic_recent_activity';
  static const String lastRequestIdKey = 'last_request_id';

  static Future<void> saveLastRequestId(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastRequestIdKey, requestId);
  }

  static Future<String?> getLastRequestId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastRequestIdKey);
  }

  static Future<void> addUserActivity(String title, String subtitle) async {
    await _addActivity(userActivityKey, title, subtitle);
  }

  static Future<void> addMechanicActivity(String title, String subtitle) async {
    await _addActivity(mechanicActivityKey, title, subtitle);
  }

  static Future<void> _addActivity(
    String key,
    String title,
    String subtitle,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(key) ?? [];

    final item = jsonEncode({
      'title': title,
      'subtitle': subtitle,
      'time': DateTime.now().toIso8601String(),
    });

    final updated = [item, ...existing];
    if (updated.length > 20) {
      updated.removeRange(20, updated.length);
    }

    await prefs.setStringList(key, updated);
  }

  static Future<List<Map<String, dynamic>>> getActivities(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key) ?? [];

    return list.map((e) {
      return jsonDecode(e) as Map<String, dynamic>;
    }).toList();
  }
}
