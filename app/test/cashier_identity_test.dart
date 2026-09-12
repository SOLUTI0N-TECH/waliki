import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/caja_code.dart';
import 'package:waliki_app/cashier_identity.dart';

Uint8List _seed(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  /// Computed independently with ethers (keccak256("waliki-cashier-v1" ||
  /// seed || 0x00), then the secp256k1 address of that key).
  ///
  /// These are the most important assertions in the app. The owner authorizes
  /// an address on-chain and the cashier's phone re-derives it from the same
  /// code: if this scheme ever drifts, every register already linked derives a
  /// different address, none of them is authorized any more, and every sale
  /// they issue is rejected by the router. Nothing about that failure looks
  /// like a code change.
  const vectors = {
    '00010203040506070809': '0x99ea3bdd77dc1857a0e4fa4e11d1da1173c49bab',
    'ffffffffffffffffffff': '0xd69ff62267ff7dd3def7ed7a8ff451e4eca01d17',
    '9f1c3a7b2d5e8f04c6a1': '0x68b7e67700f4f013c731b8e6095b8e1ee0cefa51',
  };

  test('la derivación está clavada a estos vectores', () {
    vectors.forEach((seedHex, address) {
      expect(deriveCashier(_seed(seedHex)).address, address, reason: seedHex);
    });
  });

  test('la misma semilla da siempre la misma dirección', () {
    final seed = _seed('9f1c3a7b2d5e8f04c6a1');
    final first = deriveCashier(seed).address;
    for (var i = 0; i < 20; i++) {
      expect(deriveCashier(seed).address, first);
    }
  });

  test('semillas distintas dan direcciones distintas', () {
    final addresses = <String>{};
    for (var i = 0; i < 50; i++) {
      addresses.add(deriveCashier(newCajaSeed()).address);
    }
    expect(addresses, hasLength(50));
  });

  test('la dirección viene en minúsculas y con el largo de una address', () {
    final identity = deriveCashier(newCajaSeed());
    expect(identity.address, matches(RegExp(r'^0x[0-9a-f]{40}$')));
    expect(identity.privateKey, hasLength(32));
  });

  test('el código de caja lleva a la identidad y de vuelta', () {
    final seed = newCajaSeed();
    final code = encodeCajaCode(7, seed);

    // What the owner's phone does...
    final owner = deriveCashier(seed);
    // ...and what the cashier's phone does with the code they were handed.
    final parsed = parseCajaCode(code)!;
    final cashier = deriveCashier(parsed.seed);

    expect(parsed.merchantId, 7);
    expect(cashier.address, owner.address);
  });
}
