import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart' as w3;
import 'package:waliki_app/chain.dart';
import 'package:waliki_app/config.dart';
import 'package:waliki_app/wallet.dart';

const _addr = '0x00112233445566778899aabbccddeeff00112233';

String _selector(String signature) =>
    w3.bytesToHex(w3.keccakAscii(signature)).substring(0, 8);

String _topic0(String signature) =>
    '0x${w3.bytesToHex(w3.keccakAscii(signature))}';

void main() {
  /// The app carries no ABI: these hexes ARE the interface. A parameter
  /// reordered upstream changes them, and nothing here throws -- the history
  /// just comes back empty and a payment never turns the screen green.
  ///
  /// This catches a mistyped constant. It cannot catch a signature that was
  /// changed in the contract and updated here to match; that is what the
  /// regression test in contracts/test/waliki.test.ts is for, because it reads
  /// the compiled ABI.
  group('selectores y topic0', () {
    test('cada selector es el keccak de su firma', () {
      expect(
        _selector('registerMerchant(address,string)'),
        selRegisterMerchant,
      );
      expect(_selector('addCashier(uint256,address,string)'), selAddCashier);
      expect(_selector('removeCashier(uint256,address)'), selRemoveCashier);
      expect(_selector('merchants(uint256)'), selMerchants);
      expect(_selector('paidAmount(uint256,bytes32)'), selPaidAmount);
      expect(_selector('merchantCount()'), selMerchantCount);
      expect(_selector('isCashier(uint256,address)'), selIsCashier);
    });

    test('cada topic0 es el keccak de su evento', () {
      expect(
        _topic0('PaymentReceived(uint256,bytes32,address,uint256,address)'),
        paymentReceivedTopic,
      );
      expect(
        _topic0('MerchantRegistered(uint256,address,address,string)'),
        merchantRegisteredTopic,
      );
      expect(
        _topic0('CashierAdded(uint256,address,string)'),
        cashierAddedTopic,
      );
      expect(_topic0('CashierRemoved(uint256,address)'), cashierRemovedTopic);
    });
  });

  /// Golden calldata produced independently with ethers. The one that matters
  /// is the string offset: addCashier has three head words (0x60), not the two
  /// of registerMerchant (0x40). Copying that constant does NOT revert -- the
  /// transaction lands and the register ends up with a garbled name, which is
  /// the kind of thing nobody notices for weeks.
  group('calldata', () {
    test('registerMerchant', () {
      expect(
        encodeRegisterMerchant(payout: _addr, name: 'Tienda Demo'),
        '0xa6c8a384'
        '00000000000000000000000000112233445566778899aabbccddeeff00112233'
        '0000000000000000000000000000000000000000000000000000000000000040'
        '000000000000000000000000000000000000000000000000000000000000000b'
        '5469656e64612044656d6f000000000000000000000000000000000000000000',
      );
    });

    test('addCashier', () {
      expect(
        encodeAddCashier(merchantId: 1, cashier: _addr, label: 'Caja 1'),
        '0x7961ffdc'
        '0000000000000000000000000000000000000000000000000000000000000001'
        '00000000000000000000000000112233445566778899aabbccddeeff00112233'
        '0000000000000000000000000000000000000000000000000000000000000060'
        '0000000000000000000000000000000000000000000000000000000000000006'
        '43616a6120310000000000000000000000000000000000000000000000000000',
      );
    });

    test('addCashier con etiqueta vacía: sin palabra de bytes', () {
      expect(
        encodeAddCashier(merchantId: 7, cashier: _addr, label: ''),
        '0x7961ffdc'
        '0000000000000000000000000000000000000000000000000000000000000007'
        '00000000000000000000000000112233445566778899aabbccddeeff00112233'
        '0000000000000000000000000000000000000000000000000000000000000060'
        '0000000000000000000000000000000000000000000000000000000000000000',
      );
    });

    test('addCashier con 33 bytes: dos palabras de relleno', () {
      expect(
        encodeAddCashier(merchantId: 2, cashier: _addr, label: 'A' * 33),
        '0x7961ffdc'
        '0000000000000000000000000000000000000000000000000000000000000002'
        '00000000000000000000000000112233445566778899aabbccddeeff00112233'
        '0000000000000000000000000000000000000000000000000000000000000060'
        '0000000000000000000000000000000000000000000000000000000000000021'
        '4141414141414141414141414141414141414141414141414141414141414141'
        '4100000000000000000000000000000000000000000000000000000000000000',
      );
    });

    test('addCashier con acentos: la longitud es en bytes, no en letras', () {
      expect(
        encodeAddCashier(merchantId: 3, cashier: _addr, label: 'Café Ñandú'),
        '0x7961ffdc'
        '0000000000000000000000000000000000000000000000000000000000000003'
        '00000000000000000000000000112233445566778899aabbccddeeff00112233'
        '0000000000000000000000000000000000000000000000000000000000000060'
        '000000000000000000000000000000000000000000000000000000000000000d'
        '436166c3a920c391616e64c3ba00000000000000000000000000000000000000',
      );
      expect(utf8.encode('Café Ñandú'), hasLength(0x0d));
    });

    test('removeCashier', () {
      expect(
        encodeRemoveCashier(merchantId: 9, cashier: _addr),
        '0xed164620'
        '0000000000000000000000000000000000000000000000000000000000000009'
        '00000000000000000000000000112233445566778899aabbccddeeff00112233',
      );
    });

    test('la dirección se normaliza aunque venga en EIP-55', () {
      final checksummed = '0x00112233445566778899AABBCCDDEEFF00112233';
      expect(
        encodeRemoveCashier(merchantId: 9, cashier: checksummed),
        encodeRemoveCashier(merchantId: 9, cashier: _addr),
      );
    });
  });

  group('saleId', () {
    test('lleva el cajero en los primeros 20 bytes', () {
      final id = buildSaleId(_addr);
      expect(id, matches(RegExp(r'^0x[0-9a-f]{64}$')));
      expect(id.substring(0, 42), _addr);
    });

    test('dos ventas seguidas no son la misma', () {
      final ids = {for (var i = 0; i < 100; i++) buildSaleId(_addr)};
      expect(ids, hasLength(100));
    });

    test('cashierOf lo lee de vuelta, igual que el contrato', () {
      expect(cashierOf(buildSaleId(_addr)), _addr);
      // EIP-55 in, lowercase out: every comparison in the app is lowercase
      expect(
        cashierOf(buildSaleId('0x00112233445566778899AABBCCDDEEFF00112233')),
        _addr,
      );
    });
  });

  group('decodificación de PaymentReceived', () {
    /// data layout: amount | payout
    Map<String, dynamic> log({
      required String saleId,
      required String payer,
      required BigInt amount,
    }) => {
      'topics': [
        paymentReceivedTopic,
        '0x${'0' * 63}1',
        saleId,
        '0x${payer.replaceFirst('0x', '').padLeft(64, '0')}',
      ],
      'data':
          '0x${amount.toRadixString(16).padLeft(64, '0')}'
          '${'0' * 24}aabbccddeeff00112233445566778899aabbccdd',
      'transactionHash': '0x${'ab' * 32}',
      'blockNumber': '0x1f4',
    };

    test('el cajero sale del saleId, el pagador del topic', () {
      final saleId = buildSaleId(_addr);
      const payer = '0xcafebabecafebabecafebabecafebabecafebabe';
      final payment = Payment.fromLog(
        log(saleId: saleId, payer: payer, amount: BigInt.from(8688097)),
      );

      expect(payment, isNotNull);
      expect(payment!.cashier, _addr);
      expect(payment.payer, payer);
      expect(payment.amount, BigInt.from(8688097));
      expect(payment.block, BigInt.from(500));
      // The two must never be confused: the payer is the customer, the cashier
      // is the register. Attributing sales to the wrong one is silent.
      expect(payment.cashier, isNot(payment.payer));
    });

    test('sobrevive a la ida y vuelta por la caché', () {
      final original = Payment.fromLog(
        log(
          saleId: buildSaleId(_addr),
          payer: '0xcafebabecafebabecafebabecafebabecafebabe',
          amount: BigInt.from(1250000),
        ),
      )!;
      final restored = Payment.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored, isNotNull);
      expect(restored!.saleId, original.saleId);
      expect(restored.payer, original.payer);
      expect(restored.cashier, original.cashier);
      expect(restored.amount, original.amount);
    });
  });

  test('la clave de la caché incluye el router, no solo el comercio', () {
    // Merchant ids restart at 1 on every redeploy, so a key made of the id
    // alone would mix sales from two different contracts on one device.
    final key = paymentsCacheKey(1);
    final router = WalikiConfig.router.replaceFirst('0x', '').toLowerCase();
    expect(key, contains(router.substring(0, 8)));
    expect(key, isNot('waliki.payments.1'));
    expect(paymentsCacheKey(1), isNot(paymentsCacheKey(2)));
  });
}
