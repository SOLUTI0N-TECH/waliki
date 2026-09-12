import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/qr_service.dart';

void main() {
  // Shape the backend answers with: the Yesca intent plus our crypto side.
  Map<String, dynamic> payload({
    String status = 'pending',
    bool transferred = false,
    String? txHash,
    String? lastError,
  }) {
    final json = <String, dynamic>{
      'id': 'int_abc123',
      'status': status,
      'amount': '175.00',
      'expires_at': '2026-09-12T04:30:00.000Z',
      'token': 'tok_x',
      'cryptoAmount': 15.2,
      'destinationWallet': '0x3ca0e1D199Ef95C2074248613A34a17B90702440',
      'merchantId': 1,
      'saleId': '0x${'ab' * 32}',
      'transferred': transferred,
    };
    if (txHash != null) json['txHash'] = txHash;
    if (lastError != null) json['lastError'] = lastError;
    return json;
  }

  test('a fresh QR is neither paid nor settled', () {
    final qr = FiatQr.parse(payload());
    expect(qr.id, 'int_abc123');
    expect(qr.completed, isFalse);
    expect(qr.transferred, isFalse);
    expect(qr.dead, isFalse);
    expect(qr.expiresAt, isNotNull);
  });

  test('the bank confirming is not the same as the shop being paid', () {
    // The gap that decides when the screen may turn green.
    final banked = FiatQr.parse(payload(status: 'completed'));
    expect(banked.completed, isTrue);
    expect(banked.transferred, isFalse);

    final settled = FiatQr.parse(
      payload(status: 'completed', transferred: true, txHash: '0xdead'),
    );
    expect(settled.transferred, isTrue);
    expect(settled.txHash, '0xdead');
  });

  test('expired and cancelled both end the sale', () {
    expect(FiatQr.parse(payload(status: 'expired')).dead, isTrue);
    expect(FiatQr.parse(payload(status: 'cancelled')).dead, isTrue);
  });

  test('a failed settlement is reported, not hidden', () {
    final qr = FiatQr.parse(
      payload(status: 'completed', lastError: 'insufficient funds'),
    );
    expect(qr.lastError, 'insufficient funds');
    expect(qr.transferred, isFalse);
  });

  test('a missing status does not crash the register', () {
    final qr = FiatQr.parse({'id': 'x', 'transferred': false});
    expect(qr.status, 'pending');
    expect(qr.expiresAt, isNull);
  });

  test('the QR image is read with or without a data: prefix', () {
    final png = base64Encode(List<int>.generate(64, (i) => i));
    expect(FiatQr.image({'base64': png}), isNotNull);
    expect(FiatQr.image({'base64': 'data:image/png;base64,$png'}), isNotNull);
    expect(FiatQr.image({'base64': ''}), isNull);
    expect(FiatQr.image({'base64': 'no es base64 !!'}), isNull);
    expect(FiatQr.image(<String, dynamic>{}), isNull);
  });
}
