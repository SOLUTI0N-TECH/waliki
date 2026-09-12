import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' as w3;

/// The identity of a register, derived from the seed inside its code.
///
/// The cashier never signs anything and never pays gas: this address is just
/// an identifier. The owner authorizes it on-chain with `addCashier()`, the
/// charge screen stamps it into the first 20 bytes of every sale id, and the
/// router refuses to settle a sale whose stamp is not an authorized cashier.
/// That is what makes the attribution impossible for the payer to forge.
///
/// A real private key is derived anyway, so the address is a proper account
/// rather than a dead end: anything sent there by mistake is recoverable, and
/// a future "the cashier signs their own closing report" has somewhere to go.
/// Its strength is capped by the 80 bits of the seed, which is fine precisely
/// because it never custodies anything.
class CashierIdentity {
  final Uint8List seed;
  final Uint8List privateKey;

  /// Lowercase `0x…`, the form every comparison in the app uses.
  final String address;

  const CashierIdentity({
    required this.seed,
    required this.privateKey,
    required this.address,
  });
}

/// Version tag of the derivation scheme. It is mixed into the hash so the
/// seed can never be reused for something else by accident, and so a future
/// scheme can coexist instead of silently producing different addresses for
/// every cashier already out there.
const String cashierDerivationDomain = 'waliki-cashier-v1';

/// Order of the secp256k1 group.
final BigInt _n = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);

/// Same seed in, same address out -- forever. `test/cashier_identity_test.dart`
/// pins that with known vectors: if this ever drifts, every cashier already
/// linked would derive a different address and none of them would be
/// authorized any more.
CashierIdentity deriveCashier(Uint8List seed) {
  final domain = utf8.encode(cashierDerivationDomain);
  // The counter is part of the preimage from the very first round, so there is
  // no special case to get wrong. It only ever advances on a hash that falls
  // outside the curve order, which is a 1-in-2^128 event.
  for (var counter = 0; counter < 256; counter++) {
    final preimage = Uint8List.fromList([...domain, ...seed, counter]);
    final key = w3.keccak256(preimage);
    final d = w3.bytesToUnsignedInt(key);
    if (d > BigInt.zero && d < _n) {
      final publicKey = w3.privateKeyBytesToPublic(key);
      final address = w3.publicKeyToAddress(publicKey);
      return CashierIdentity(
        seed: seed,
        privateKey: key,
        address: '0x${w3.bytesToHex(address)}',
      );
    }
  }
  throw StateError('No se pudo derivar la identidad de la caja');
}
