// lib/providers/locale_provider.dart
//
// LocaleProvider
// • Holds current app Locale (or null for system default)
// • setLocale(Locale?) → updates state and persists to Firestore under users/{uid}.preferences.locale
// • load() → reads saved locale on app start (safe if user not signed in)
// • Supported locales in this app: en, si, ta
//
// Notes:
// • MaterialApp listens to localeProvider.locale. If null, it follows system language.
// • SettingsScreen uses this provider to switch languages at runtime.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocaleProvider extends ChangeNotifier {
  Locale? _locale;
  Locale? get locale => _locale;

  // Optional eager load (call from main if you like). Defaults to system if not called.
  Future<void> load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        // Not signed in → keep system default
        return;
      }
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final prefs = (snap.data()?['preferences'] as Map<String, dynamic>?) ?? const {};
      final code = prefs['locale'] as String?;
      if (code != null && _isSupported(code)) {
        _locale = Locale(code);
        notifyListeners();
      }
    } catch (_) {
      // Ignore errors and keep system default
    }
  }

  /// Set app locale. Pass `null` to use system language.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();

    // Persist (best-effort)
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'preferences': {
          'locale': locale?.languageCode, // 'en' | 'si' | 'ta' | null (system)
        }
      }, SetOptions(merge: true));
    } catch (_) {
      // Silent fail; UI already updated
    }
  }

  // Helper if you ever want to set by language code.
  Future<void> setLanguageCode(String? code) => setLocale(
    (code != null && _isSupported(code)) ? Locale(code) : null,
  );

  bool _isSupported(String code) {
    switch (code) {
      case 'en':
      case 'si':
      case 'ta':
        return true;
      default:
        return false;
    }
  }
}
