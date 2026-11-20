// FILE: lib/core/i18n/rq_strings.dart
/// Language preference and a small, honest string catalogue.
///
/// Scope is stated plainly: the SHELL labels (tabs, settings, common actions)
/// are translated for English, Hindi and Tamil. Descriptive body copy across
/// the feature screens is still English — a half-filled translation table for
/// 40 screens would be worse than saying so. The preference itself is real: it
/// is persisted and applied to `MaterialApp.locale`, so date, number and
/// Material widget localisation follow it too.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RqLocale {
  RqLocale._();

  static const String _prefKey = 'roadresq_language';
  static const String english = 'en';
  static const String hindi = 'hi';
  static const String tamil = 'ta';

  static const List<Locale> supported = <Locale>[
    Locale(english),
    Locale(hindi),
    Locale(tamil),
  ];

  static const Map<String, String> names = <String, String>{
    english: 'English',
    hindi: 'हिन्दी',
    tamil: 'தமிழ்',
  };

  /// Global notifier read by `main.dart` so a change rebuilds the app.
  static final ValueNotifier<Locale?> locale =
      ValueNotifier<Locale?>(const Locale(english));

  static String get code => locale.value?.languageCode ?? english;

  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      if (stored != null && names.containsKey(stored)) {
        locale.value = Locale(stored);
      }
    } catch (_) {
      // Keep the default; a failed read must not block startup.
    }
  }

  static Future<void> set(String languageCode) async {
    if (!names.containsKey(languageCode)) return;
    locale.value = Locale(languageCode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, languageCode);
    } catch (_) {
      // best effort
    }
  }
}

class RqStrings {
  RqStrings._();

  static const Map<String, Map<String, String>> _table =
      <String, Map<String, String>>{
    // key: {en, hi, ta}
    'home': {'en': 'Home', 'hi': 'होम', 'ta': 'முகப்பு'},
    'track': {'en': 'Track Rescue', 'hi': 'बचाव ट्रैक करें', 'ta': 'மீட்பை கண்காணி'},
    'history': {'en': 'History', 'hi': 'इतिहास', 'ta': 'வரலாறு'},
    'requests': {'en': 'My Requests', 'hi': 'मेरे अनुरोध', 'ta': 'என் கோரிக்கைகள்'},
    'support': {'en': 'Support', 'hi': 'सहायता', 'ta': 'ஆதரவு'},
    'profile': {'en': 'Profile', 'hi': 'प्रोफ़ाइल', 'ta': 'சுயவிவரம்'},
    'passbook': {'en': 'Passbook', 'hi': 'पासबुक', 'ta': 'பாஸ்புக்'},
    'jobs': {'en': 'Jobs', 'hi': 'काम', 'ta': 'வேலைகள்'},
    'settings': {'en': 'Settings', 'hi': 'सेटिंग्स', 'ta': 'அமைப்புகள்'},
    'language': {'en': 'Language', 'hi': 'भाषा', 'ta': 'மொழி'},
    'appearance': {'en': 'Appearance', 'hi': 'रूप', 'ta': 'தோற்றம்'},
    'dark_mode': {'en': 'Dark mode', 'hi': 'डार्क मोड', 'ta': 'இருண்ட பயன்முறை'},
    'notifications': {'en': 'Notifications', 'hi': 'सूचनाएं', 'ta': 'அறிவிப்புகள்'},
    'privacy': {'en': 'Privacy policy', 'hi': 'गोपनीयता नीति', 'ta': 'தனியுரிமை கொள்கை'},
    'logout': {'en': 'Log out', 'hi': 'लॉग आउट', 'ta': 'வெளியேறு'},
    'cancel': {'en': 'Cancel', 'hi': 'रद्द करें', 'ta': 'ரத்து'},
    'save': {'en': 'Save', 'hi': 'सहेजें', 'ta': 'சேமி'},
    'retry': {'en': 'Try again', 'hi': 'पुनः प्रयास', 'ta': 'மீண்டும் முயற்சி'},
    'loading': {'en': 'Loading…', 'hi': 'लोड हो रहा है…', 'ta': 'ஏற்றுகிறது…'},
    'no_data': {
      'en': 'No data yet',
      'hi': 'अभी कोई डेटा नहीं',
      'ta': 'இன்னும் தரவு இல்லை'
    },
    'earnings': {'en': 'Earnings', 'hi': 'कमाई', 'ta': 'வருவாய்'},
    'attendance': {'en': 'Attendance', 'hi': 'उपस्थिति', 'ta': 'வருகை'},
    'ratings': {'en': 'Ratings', 'hi': 'रेटिंग', 'ta': 'மதிப்பீடுகள்'},
    'documents': {'en': 'Documents', 'hi': 'दस्तावेज़', 'ta': 'ஆவணங்கள்'},
  };

  /// Translate [key] for [languageCode], falling back to English and then to
  /// the key itself so a missing entry is visible in development rather than
  /// rendering an empty string.
  static String t(String key, {String? languageCode}) {
    final entry = _table[key];
    if (entry == null) return key;
    final code = languageCode ?? RqLocale.code;
    return entry[code] ?? entry[RqLocale.english] ?? key;
  }

  /// Context convenience: follows the active [RqLocale].
  static String of(String key) => t(key);
}
