import 'package:shared_preferences/shared_preferences.dart';

import 'vault.dart';

enum Role { duenio, cajero }

/// Persisted local session: who is using this device and for which shop.
///
/// Nothing secret lives here. The owner's address is public, the cashier's is
/// an identifier the shop authorized on-chain, and the PIN only locks the
/// register UI on this device — neither can move funds. The one secret, the
/// cashier's seed, lives in [Vaults].
class Session {
  static const _kRole = 'waliki.role';
  static const _kOwner = 'waliki.owner';
  static const _kMerchant = 'waliki.merchantId';
  static const _kPin = 'waliki.pin';
  static const _kRate = 'waliki.rate';
  static const _kCashier = 'waliki.cashierAddress';
  static const _kSchema = 'waliki.schema';

  /// Bumped when a stored session stops meaning what it used to.
  ///
  /// Version 2 is the on-chain cashiers release: the router was redeployed, so
  /// merchant ids point at different shops, and the linking code changed shape
  /// entirely. Carrying an old session forward would open a register against
  /// somebody else's business, so it is cleared instead.
  static const int schemaVersion = 2;

  Role? role;
  String? ownerAddress;
  int? merchantId;
  String? pin;

  /// Address this device issues sales under. The owner's wallet address when
  /// they charge from their own phone; the derived register identity on a
  /// cashier's. It is stamped into every sale id, so without it nothing here
  /// can charge.
  String? cashierAddress;

  /// Last market rate seen, kept so the register can still price a sale
  /// before the quote comes back.
  String rate;

  Session({
    this.role,
    this.ownerAddress,
    this.merchantId,
    this.pin,
    this.cashierAddress,
    this.rate = '14.00',
  });

  bool get isReady =>
      role != null && merchantId != null && cashierAddress != null;

  static Future<Session> load() async {
    final p = await SharedPreferences.getInstance();

    if ((p.getInt(_kSchema) ?? 1) < schemaVersion) {
      await _migrate(p);
    }

    final roleStr = p.getString(_kRole);
    return Session(
      role: roleStr == null
          ? null
          : Role.values.firstWhere(
              (r) => r.name == roleStr,
              orElse: () => Role.cajero,
            ),
      ownerAddress: p.getString(_kOwner),
      merchantId: p.getInt(_kMerchant),
      pin: p.getString(_kPin),
      cashierAddress: p.getString(_kCashier),
      rate: p.getString(_kRate) ?? '14.00',
    );
  }

  /// Drops everything that points at the old router. The rate survives: it is
  /// just the last quote seen and it is right either way.
  static Future<void> _migrate(SharedPreferences p) async {
    for (final key in [_kRole, _kOwner, _kMerchant, _kPin, _kCashier]) {
      await p.remove(key);
    }
    // Sales cached under the old key scheme, which had no router in it
    for (final key in p.getKeys()) {
      if (key.startsWith('waliki.payments') ||
          key.startsWith('waliki.paymentsBlock')) {
        await p.remove(key);
      }
    }
    await Vaults.instance.delete(Vaults.cashierSeedKey);
    await p.setInt(_kSchema, schemaVersion);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await _put(p, _kRole, role?.name);
    await _put(p, _kOwner, ownerAddress);
    await _put(p, _kPin, pin);
    await _put(p, _kCashier, cashierAddress);
    if (merchantId != null) {
      await p.setInt(_kMerchant, merchantId!);
    } else {
      await p.remove(_kMerchant);
    }
    await p.setString(_kRate, rate);
    await p.setInt(_kSchema, schemaVersion);
  }

  static Future<void> _put(
    SharedPreferences p,
    String key,
    String? value,
  ) async {
    if (value != null) {
      await p.setString(key, value);
    } else {
      await p.remove(key);
    }
  }

  Future<void> clear() async {
    role = null;
    ownerAddress = null;
    merchantId = null;
    pin = null;
    cashierAddress = null;
    // The seed goes too: leaving it behind would let a later link silently
    // reuse an identity the owner may have revoked in the meantime.
    await Vaults.instance.delete(Vaults.cashierSeedKey);
    await save();
  }
}
