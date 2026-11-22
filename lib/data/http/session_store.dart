import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a signed-in device keeps on disk, split by how sensitive it is:
///
/// * the two tokens go to the platform keystore (Keychain, Android Keystore,
///   encrypted on the web);
/// * the account as the server last sent it goes to plain preferences, so a
///   cold start shows who is signed in before, or without, the network.
///
/// Where no keystore exists (tests, an old desktop) the tokens fall back to
/// preferences; a token left there by an older build moves to the keystore
/// on the next save.
class SessionStore {
  const SessionStore();

  static const _vault = FlutterSecureStorage();
  static const _refreshKey = 'yusal_api.refresh_token';
  static const _accessKey = 'yusal_api.access_token';
  static const _accountKey = 'yusal_api.account';

  /// The saved session, or null when nobody is signed in on this device.
  Future<StoredSession?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = await _read(prefs, _refreshKey);
    if (refresh == null) return null;
    Map<String, dynamic>? account;
    try {
      final raw = prefs.getString(_accountKey);
      if (raw != null) account = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // A record this build cannot read: the next /me rewrites it.
    }
    return StoredSession(
        refresh: refresh,
        access: await _read(prefs, _accessKey),
        account: account);
  }

  Future<void> saveTokens(String? access, String? refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await _write(prefs, _accessKey, access);
    await _write(prefs, _refreshKey, refresh);
  }

  /// [account] is the server's user JSON, kept as sent.
  Future<void> saveAccount(Map<String, dynamic>? account) async {
    final prefs = await SharedPreferences.getInstance();
    if (account == null) {
      await prefs.remove(_accountKey);
    } else {
      await prefs.setString(_accountKey, jsonEncode(account));
    }
  }

  Future<void> clear() async {
    await saveTokens(null, null);
    await saveAccount(null);
  }

  static Future<String?> _read(SharedPreferences prefs, String key) async {
    try {
      final v = await _vault.read(key: key);
      if (v != null) return v;
    } catch (_) {
      // No keystore here.
    }
    return prefs.getString(key);
  }

  static Future<void> _write(
      SharedPreferences prefs, String key, String? value) async {
    try {
      if (value == null) {
        await _vault.delete(key: key);
      } else {
        await _vault.write(key: key, value: value);
      }
      await prefs.remove(key);
      return;
    } catch (_) {
      // No keystore: keep it in preferences.
    }
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

/// A session read back from disk.
class StoredSession {
  const StoredSession({required this.refresh, this.access, this.account});
  final String refresh;
  final String? access;

  /// The account JSON as last saved; null for a session saved by a build
  /// that did not keep it.
  final Map<String, dynamic>? account;
}
