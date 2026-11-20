import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationItem {
  final String title;
  final String message;
  final DateTime time;
  final bool isRead;

  NotificationItem({
    required this.title,
    required this.message,
    required this.time,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'message': message,
      'time': time.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      time: DateTime.tryParse(json['time'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
    );
  }

  NotificationItem copyWith({
    String? title,
    String? message,
    DateTime? time,
    bool? isRead,
  }) {
    return NotificationItem(
      title: title ?? this.title,
      message: message ?? this.message,
      time: time ?? this.time,
      isRead: isRead ?? this.isRead,
    );
  }
}

class NotificationService {
  static const String _storageKey = 'roadresq_notifications';

  /// §54 — user preference. Defaults to on, matching the pre-toggle behaviour.
  static const String enabledKey = 'roadresq_notifications_enabled';

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, enabled);
    } catch (_) {
      // best effort
    }
  }

  static void show(
    BuildContext context,
    String message, {
    String title = 'RoadResQ',
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  static Future<void> push({
    required String title,
    required String message,
  }) async {
    // Respect the Settings toggle: a muted user must not keep accumulating
    // unread items that they have explicitly switched off.
    if (!await isEnabled()) return;

    final prefs = await SharedPreferences.getInstance();
    final items = await getAll();

    final updated = [
      NotificationItem(
        title: title,
        message: message,
        time: DateTime.now(),
        isRead: false,
      ),
      ...items,
    ];

    final encoded = updated.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, encoded);
  }

  static Future<List<NotificationItem>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];

    return rawList.map((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      return NotificationItem.fromJson(map);
    }).toList();
  }

  static Future<int> getUnreadCount() async {
    final items = await getAll();
    return items.where((e) => !e.isRead).length;
  }

  static Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getAll();

    final updated = items.map((e) => e.copyWith(isRead: true)).toList();
    final encoded = updated.map((e) => jsonEncode(e.toJson())).toList();

    await prefs.setStringList(_storageKey, encoded);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
