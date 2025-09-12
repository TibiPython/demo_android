// lib/core/prefs.dart
import 'package:shared_preferences/shared_preferences.dart';

class AppPrefs {
  static const _kDefaultLoanMode = 'default_loan_mode'; // 'auto' | 'manual'

  static Future<String?> getDefaultLoanMode() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kDefaultLoanMode);
  }

  static Future<void> setDefaultLoanMode(String mode) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kDefaultLoanMode, mode);
  }

  static Future<void> clearDefaultLoanMode() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kDefaultLoanMode);
  }
}
