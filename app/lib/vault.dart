import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the register seeds live.
///
/// Thin on purpose: `flutter_secure_storage` ships no mock, so every test that
/// walks the linking flow would otherwise have to reach into the plugin's
/// platform instance. With this interface a test swaps in [MemoryVault] and
/// moves on -- and if the plugin ever has to go, only [SecureVault] changes.
abstract class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android: AES-GCM blob in the app's own preferences, wrapped by a key in the
/// Keystore. iOS: the Keychain. Both are gone when the app is uninstalled on
/// Android, which is why `main.dart` checks that the seed is still there
/// before letting a linked register open.
class SecureVault implements Vault {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // A restored backup leaves a blob no Keystore key can open. The plugin
      // clears it and we treat it as absent, which sends the register back to
      // linking instead of into a session with no identity.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryVault implements Vault {
  final Map<String, String> _values = {};

  MemoryVault([Map<String, String>? initial]) {
    if (initial != null) _values.addAll(initial);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// The vault the app uses. Tests assign a [MemoryVault] here.
class Vaults {
  static Vault instance = SecureVault();

  /// Seed of the identity this device charges with. Present on a cashier's
  /// phone; the owner signs with their own wallet and does not need one.
  static const String cashierSeedKey = 'waliki.cashier.seed';

  /// Registers this owner created, so their codes can be shown again without
  /// paying for a second `addCashier` signature.
  static String cashiersKey(int merchantId) => 'waliki.cashiers.$merchantId';

  /// A seed written down BEFORE its `addCashier` was signed. Without this, an
  /// app killed mid-signature leaves an address authorized on-chain whose seed
  /// exists nowhere: a register nobody can ever link.
  static String pendingCashierKey(int merchantId) =>
      'waliki.pendingCashier.$merchantId';
}
