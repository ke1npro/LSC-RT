import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageDataSource {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<bool?> getBool(String key) async {
    try {
      final p = await _prefs;
      return p.getBool(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> setBool(String key, bool value) async {
    try {
      final p = await _prefs;
      return await p.setBool(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<int?> getInt(String key) async {
    try {
      final p = await _prefs;
      return p.getInt(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> setInt(String key, int value) async {
    try {
      final p = await _prefs;
      return await p.setInt(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<String?> getString(String key) async {
    try {
      final p = await _prefs;
      return p.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> setString(String key, String value) async {
    try {
      final p = await _prefs;
      return await p.setString(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> remove(String key) async {
    try {
      final p = await _prefs;
      return await p.remove(key);
    } catch (_) {
      return false;
    }
  }

  Future<String> loadAssetString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return '';
    }
  }
}
