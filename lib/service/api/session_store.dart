import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// What a signed-in device keeps on disk:
///
/// * the two tokens in the platform keystore (Keychain, Android Keystore);
/// * the account as the server last sent it, as a JSON map in a Hive box, so
///   a cold start shows who is signed in before, or without, the network.
class SessionStore {
  const SessionStore();

  static const _vault = FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _accountKey = 'account';
  static const boxName = 'yusal_session';

  static Future<Box<dynamic>>? _opening;

  static Future<Box<dynamic>> _box() => _opening ??= () async {
        if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
        await Hive.initFlutter();
        return Hive.openBox<dynamic>(boxName);
      }();

  /// The saved session, or null when nobody is signed in on this device.
  Future<StoredSession?> read() async {
    final refresh = await _vault.read(key: _refreshKey);
    if (refresh == null) return null;
    final account = (await _box()).get(_accountKey);
    return StoredSession(
        refresh: refresh,
        access: await _vault.read(key: _accessKey),
        account: account is Map ? account.cast<String, dynamic>() : null);
  }

  Future<void> saveTokens(String? access, String? refresh) async {
    await _vault.write(key: _accessKey, value: access);
    await _vault.write(key: _refreshKey, value: refresh);
  }

  /// [account] is the server's user JSON, kept as sent.
  Future<void> saveAccount(Map<String, dynamic> account) async =>
      (await _box()).put(_accountKey, account);

  Future<void> clear() async {
    await _vault.delete(key: _accessKey);
    await _vault.delete(key: _refreshKey);
    await (await _box()).delete(_accountKey);
  }
}

/// A session read back from disk.
class StoredSession {
  const StoredSession({required this.refresh, this.access, this.account});
  final String refresh;
  final String? access;
  final Map<String, dynamic>? account;
}
