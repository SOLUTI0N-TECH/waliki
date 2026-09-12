import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/chain.dart';

void main() {
  // The device cache is only as trustworthy as this round trip: a sale that
  // does not survive it is a sale the register stops showing.
  final sale = Payment(
    saleId: '0x${'ab' * 32}',
    payer: '0xbe5d6249ef221495db1469348e694f824bd7e22d',
    txHash: '0x${'cd' * 32}',
    amount: BigInt.from(8688097),
    block: BigInt.from(46709527),
    timestamp: 1789185129,
  );

  test('a sale survives being stored and read back', () {
    final back = Payment.fromJson(sale.toJson())!;
    expect(back.saleId, sale.saleId);
    expect(back.payer, sale.payer);
    expect(back.txHash, sale.txHash);
    expect(back.amount, sale.amount);
    expect(back.block, sale.block);
    expect(back.timestamp, sale.timestamp);
  });

  test('amounts and blocks keep full precision as text', () {
    // Past 2^53 a JSON number would round; these are written as strings.
    final big = Payment(
      saleId: '0x01',
      payer: '0x02',
      txHash: '0x03',
      amount: BigInt.parse('123456789012345678901234567890'),
      block: BigInt.parse('9007199254740993'),
    );
    final back = Payment.fromJson(big.toJson())!;
    expect(back.amount, big.amount);
    expect(back.block, big.block);
  });

  test('a sale without a resolved time round-trips as null', () {
    final back = Payment.fromJson(sale.withTime(null).toJson())!;
    expect(back.timestamp, isNull);
    expect(back.date, isNull);
  });

  test('a broken entry is dropped, not thrown', () {
    expect(Payment.fromJson(null), isNull);
    expect(Payment.fromJson('nope'), isNull);
    expect(Payment.fromJson(<String, dynamic>{}), isNull);
    expect(
      Payment.fromJson({'s': 1, 'p': '0x', 't': '0x', 'a': '1', 'b': '1'}),
      isNull,
    );
    expect(
      Payment.fromJson({'s': '0x', 'p': '0x', 't': '0x', 'a': 'x', 'b': '1'}),
      isNull,
    );
  });
}
