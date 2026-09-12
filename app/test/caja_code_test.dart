import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/caja_code.dart';

Uint8List _seed(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  group('encodeCajaCode', () {
    test('formato conocido: id en decimal y cuatro grupos de cuatro', () {
      expect(
        encodeCajaCode(7, _seed('9f1c3a7b2d5e8f04c6a1')),
        '7-KWE3-MYSD-BT7G-9HN1',
      );
      // Leading zero bytes have to survive: a code is a bit stream, not a
      // number, and encoding it as one would silently shorten this seed.
      expect(
        encodeCajaCode(1, _seed('00010203040506070809')),
        '1-000G-40R4-0M30-E209',
      );
      expect(
        encodeCajaCode(42, _seed('00000000000000000000')),
        '42-0000-0000-0000-0000',
      );
      expect(
        encodeCajaCode(3, _seed('ffffffffffffffffffff')),
        '3-ZZZZ-ZZZZ-ZZZZ-ZZZZ',
      );
    });

    test('rechaza semillas del largo equivocado', () {
      expect(() => encodeCajaCode(1, _seed('0102')), throwsArgumentError);
    });
  });

  group('parseCajaCode', () {
    test('ida y vuelta con semillas aleatorias', () {
      for (var i = 0; i < 200; i++) {
        final seed = newCajaSeed();
        final merchantId = i + 1;
        final parsed = parseCajaCode(encodeCajaCode(merchantId, seed));
        expect(parsed, isNotNull);
        expect(parsed!.merchantId, merchantId);
        expect(parsed.seed, seed);
      }
    });

    test('tolera cómo se teclea de verdad', () {
      final seed = _seed('9f1c3a7b2d5e8f04c6a1');
      const canonical = '7-KWE3-MYSD-BT7G-9HN1';
      for (final variant in [
        canonical,
        canonical.toLowerCase(),
        '7KWE3MYSDBT7G9HN1', // sin separadores
        '7 KWE3 MYSD BT7G 9HN1',
        '  7-kwe3-mysd-bt7g-9hn1  ',
        '7:KWE3.MYSD_BT7G-9HN1',
        'W7-KWE3-MYSD-BT7G-9HN1', // la W que arrastran los códigos viejos
      ]) {
        final parsed = parseCajaCode(variant);
        expect(parsed, isNotNull, reason: variant);
        expect(parsed!.merchantId, 7, reason: variant);
        expect(parsed.seed, seed, reason: variant);
      }
    });

    test(
      'confunde O con 0 e I/L con 1, que es para lo que se eligió el alfabeto',
      () {
        final esperado = parseCajaCode('10-0011-2233-4455-6677');
        expect(esperado, isNotNull);
        for (final variant in [
          'IO-OOII-2233-4455-6677',
          'lo-ooll-2233-4455-6677',
          'Io-0oI1-2233-4455-6677',
        ]) {
          final parsed = parseCajaCode(variant);
          expect(parsed, isNotNull, reason: variant);
          expect(parsed!.merchantId, esperado!.merchantId, reason: variant);
          expect(parsed.seed, esperado.seed, reason: variant);
        }
      },
    );

    test('rechaza lo que no es un código', () {
      for (final invalid in [
        '',
        '74821', // el código viejo: tiene que fallar claro, no colarse
        '7-KWE3-MYSD-BT7G-9HN', // 15 símbolos
        '7-KWE3-MYSD-BT7G-9HN11', // 17 símbolos
        'KWE3-MYSD-BT7G-9HN1', // sin comercio
        '0-KWE3-MYSD-BT7G-9HN1', // comercio 0
        '7a-KWE3-MYSD-BT7G-9HN1', // comercio que no es un número
        '7-UWE3-MYSD-BT7G-9HN1', // U no está en el alfabeto
        '7-KWE3-MYSD-BT7G-9HN!',
      ]) {
        expect(parseCajaCode(invalid), isNull, reason: invalid);
      }
    });
  });

  test('formatCajaCodeInput deja solo lo que puede formar un código', () {
    expect(formatCajaCodeInput('7-kwe3 mysd'), '7-KWE3MYSD');
    expect(formatCajaCodeInput('¡7!—kwe3'), '7KWE3');
  });
}
