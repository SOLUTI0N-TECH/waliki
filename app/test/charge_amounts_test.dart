import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/charge_amounts.dart';

void main() {
  group('conversion', () {
    test('typing dollars prices the bolivianos at the market rate', () {
      const a = ChargeAmounts(source: Money.usd, text: '10', rate: 11.51);
      expect(a.units, BigInt.from(10000000));
      expect(a.bs, 115.1);
    });

    test('typing bolivianos keeps the dollars exact to the micro-unit', () {
      const a = ChargeAmounts(source: Money.bs, text: '100', rate: 11.51);
      expect(a.bs, 100);
      // Rounding this to cents first would shortchange the shop.
      expect(a.units, BigInt.from(8688097));
    });

    test('derived bolivianos never carry more than two decimals', () {
      // 1.23 * 11.517 = 14.16591
      const a = ChargeAmounts(source: Money.usd, text: '1,23', rate: 11.517);
      expect(a.bs, 14.17);
    });

    test('without a rate only the typed currency is known', () {
      const usd = ChargeAmounts(source: Money.usd, text: '5');
      expect(usd.units, BigInt.from(5000000));
      expect(usd.bs, isNull);

      const bs = ChargeAmounts(source: Money.bs, text: '50');
      expect(bs.bs, 50);
      expect(bs.units, isNull);
    });

    test('an empty or zero entry charges nothing', () {
      expect(const ChargeAmounts().units, isNull);
      expect(const ChargeAmounts(source: Money.bs, rate: 11.5).bs, isNull);
      expect(
        const ChargeAmounts(source: Money.usd, text: '0', rate: 11.5).units,
        isNull,
      );
      expect(
        const ChargeAmounts(source: Money.usd, text: '0,', rate: 11.5).isEmpty,
        isTrue,
      );
    });
  });

  group('keypad', () {
    String type(String keys) =>
        keys.split('').fold('', (text, key) => ChargeAmounts.press(text, key));

    test('builds an ordinary amount', () {
      expect(type('125,5'), '125,5');
    });

    test('a comma can neither open the amount nor appear twice', () {
      expect(type(','), '');
      expect(type('1,,2'), '1,2');
    });

    test('a third decimal is refused rather than rounded later', () {
      expect(type('8,699'), '8,69');
    });

    test('a lone leading zero gives way to the next digit', () {
      expect(type('05'), '5');
      expect(type('0,5'), '0,5');
    });

    test('backspace removes one character and stops at empty', () {
      expect(ChargeAmounts.press('12', '<'), '1');
      expect(ChargeAmounts.press('', '<'), '');
    });

    test('the amount is capped at nine characters', () {
      expect(type('1234567890'), '123456789');
    });
  });
}
