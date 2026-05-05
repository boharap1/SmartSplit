import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kLanguage = 'settings_language';
  static const _kTimeZone = 'settings_timezone';
  static const _kCurrency = 'settings_currency';
  static const _kTheme    = 'settings_theme';

  String    _language  = 'English';
  String    _timeZone  = 'Europe/London';
  String    _currency  = 'GBP';
  ThemeMode _themeMode = ThemeMode.light;

  String    get language      => _language;
  String    get timeZone      => _timeZone;
  String    get currency      => _currency;
  ThemeMode get themeMode     => _themeMode;
  bool      get isDarkMode    => _themeMode == ThemeMode.dark;
  String get currencySymbol => _symbols[_currency] ?? _currency;

  String formatAmount(double amount) =>
      '$currencySymbol${amount.toStringAsFixed(2)}';

  // ── Static lookup tables ─────────────────────────────────────────────────

  static const Map<String, String> _symbols = {
    'GBP': '£',
    'USD': '\$',
    'EUR': '€',
    'NPR': 'रु',
    'INR': '₹',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'JPY': '¥',
    'SGD': 'S\$',
    'AED': 'د.إ',
  };

  static const Map<String, String> currencyNames = {
    'GBP': 'British Pound',
    'USD': 'US Dollar',
    'EUR': 'Euro',
    'NPR': 'Nepalese Rupee',
    'INR': 'Indian Rupee',
    'AUD': 'Australian Dollar',
    'CAD': 'Canadian Dollar',
    'JPY': 'Japanese Yen',
    'SGD': 'Singapore Dollar',
    'AED': 'UAE Dirham',
  };

  static const List<Map<String, String>> languages = [
    {'code': 'en',    'name': 'English',    'native': 'English'},
    {'code': 'ne',    'name': 'Nepali',     'native': 'नेपाली'},
    {'code': 'hi',    'name': 'Hindi',      'native': 'हिन्दी'},
    {'code': 'es',    'name': 'Spanish',    'native': 'Español'},
    {'code': 'fr',    'name': 'French',     'native': 'Français'},
    {'code': 'de',    'name': 'German',     'native': 'Deutsch'},
    {'code': 'zh',    'name': 'Chinese',    'native': '中文'},
    {'code': 'ar',    'name': 'Arabic',     'native': 'العربية'},
    {'code': 'pt',    'name': 'Portuguese', 'native': 'Português'},
    {'code': 'ja',    'name': 'Japanese',   'native': '日本語'},
  ];

  static const List<Map<String, String>> timeZones = [
    {'id': 'UTC',                   'label': 'UTC (UTC+0)'},
    {'id': 'Europe/London',         'label': 'London (UTC+0/+1)'},
    {'id': 'Europe/Paris',          'label': 'Paris / Berlin (UTC+1/+2)'},
    {'id': 'Europe/Moscow',         'label': 'Moscow (UTC+3)'},
    {'id': 'Asia/Dubai',            'label': 'Dubai (UTC+4)'},
    {'id': 'Asia/Karachi',          'label': 'Karachi (UTC+5)'},
    {'id': 'Asia/Kolkata',          'label': 'Mumbai / Kolkata (UTC+5:30)'},
    {'id': 'Asia/Kathmandu',        'label': 'Kathmandu (UTC+5:45)'},
    {'id': 'Asia/Dhaka',            'label': 'Dhaka (UTC+6)'},
    {'id': 'Asia/Bangkok',          'label': 'Bangkok / Jakarta (UTC+7)'},
    {'id': 'Asia/Shanghai',         'label': 'Beijing / Singapore (UTC+8)'},
    {'id': 'Asia/Tokyo',            'label': 'Tokyo (UTC+9)'},
    {'id': 'Australia/Sydney',      'label': 'Sydney (UTC+10/+11)'},
    {'id': 'Pacific/Auckland',      'label': 'Auckland (UTC+12/+13)'},
    {'id': 'America/Los_Angeles',   'label': 'Los Angeles (UTC-8/-7)'},
    {'id': 'America/Chicago',       'label': 'Chicago (UTC-6/-5)'},
    {'id': 'America/New_York',      'label': 'New York (UTC-5/-4)'},
    {'id': 'America/Toronto',       'label': 'Toronto (UTC-5/-4)'},
    {'id': 'America/Sao_Paulo',     'label': 'São Paulo (UTC-3)'},
    {'id': 'America/Vancouver',     'label': 'Vancouver (UTC-8/-7)'},
  ];

  // ── Initialise from SharedPreferences ────────────────────────────────────

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString(_kLanguage) ?? 'English';
    _timeZone = prefs.getString(_kTimeZone) ?? 'Europe/London';
    _currency = prefs.getString(_kCurrency) ?? 'GBP';
    final themeStr = prefs.getString(_kTheme) ?? 'light';
    _themeMode = themeStr == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  Future<void> setLanguage(String language) async {
    if (_language == language) return;
    _language = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, language);
    notifyListeners();
  }

  Future<void> setTimeZone(String timeZone) async {
    if (_timeZone == timeZone) return;
    _timeZone = timeZone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTimeZone, timeZone);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    if (_currency == currency) return;
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrency, currency);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, _themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
}
