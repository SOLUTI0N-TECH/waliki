import 'package:shared_preferences/shared_preferences.dart';

enum Role { duenio, cajero }

/// Persisted local session: who is using this device and for which shop.
/// Nothing secret lives here — the owner's address is public, and the PIN
/// only gates the register UI (the cashier can never move funds).
class Session {
  static const _kRole = 'waliki.role';
  static const _kOwner = 'waliki.owner';
  static const _kMerchant = 'waliki.merchantId';
  static const _kPin = 'waliki.pin';
  static const _kRate = 'waliki.rate';

  Role? role;
  String? ownerAddress;
  int? merchantId;
  String? pin;

  /// Last market rate seen, kept so the register can still price a sale
  /// before the quote comes back.
  String rate;

  Session({
    this.role,
    this.ownerAddress,
    this.merchantId,
    this.pin,
    this.rate = '14.00',
  });

  bool get isReady => role != null && merchantId != null;

  static Future<Session> load() async {
    final p = await SharedPreferences.getInstance();
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
      rate: p.getString(_kRate) ?? '14.00',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    if (role != null) {
      await p.setString(_kRole, role!.name);
    } else {
      await p.remove(_kRole);
    }
    if (ownerAddress != null) {
      await p.setString(_kOwner, ownerAddress!);
    } else {
      await p.remove(_kOwner);
    }
    if (merchantId != null) {
      await p.setInt(_kMerchant, merchantId!);
    } else {
      await p.remove(_kMerchant);
    }
    if (pin != null) {
      await p.setString(_kPin, pin!);
    } else {
      await p.remove(_kPin);
    }
    await p.setString(_kRate, rate);
  }

  Future<void> clear() async {
    role = null;
    ownerAddress = null;
    merchantId = null;
    pin = null;
    await save();
  }

  /// Register-linking code the owner hands to a cashier: `<merchantId><pin>`.
  ///
  /// Digits only: the cashier never leaves the number keyboard, and there is
  /// nothing to spell out. The PIN is always four digits, so the shop id is
  /// whatever comes before them.
  static String buildCajaCode(int merchantId, String pin) => '$merchantId$pin';

  /// Parses "74821". A leading `W` and any separator are still accepted, so
  /// codes handed out under the older formats keep working.
  static ({int merchantId, String pin})? parseCajaCode(String raw) {
    // Separated form first: codes handed out before this change, and anything
    // typed with a dash, colon or space out of habit.
    var m = RegExp(r'^\s*[wW]?\s*(\d+)\s*[-: ]\s*(\d{4,8})\s*$')
        .firstMatch(raw);
    // Run together: the PIN is the last four digits, the shop id the rest.
    m ??= RegExp(r'^\s*[wW]?\s*(\d+)(\d{4})\s*$').firstMatch(raw);
    if (m == null) return null;
    final id = int.tryParse(m.group(1)!);
    if (id == null || id <= 0) return null;
    return (merchantId: id, pin: m.group(2)!);
  }
}
