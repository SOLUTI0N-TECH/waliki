import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/wallet.dart';

void main() {
  test('el fallo de certificado dice qué hacer, no vuelca Java', () {
    // Real error seen on a phone: MetaMask could not reach its own Sentinel
    // service because the network was intercepting HTTPS.
    const real =
        'JsonRpcError(code: 5000, message: Sentinel: java.lang.RuntimeException: '
        'Cronet failed: Exception in CronetUrlRequest: '
        'net::ERR_CERT_AUTHORITY_INVALID, ErrorCode=11, InternalErrorCode=-202, '
        'Retryable=false\n at com.margelo.nitro.nitrofetch.NitroFetchClient\n'
        ' at org.chromium.net.impl.CronetUrlRequest\$g.run(SourceFile:25))';

    final message = walletErrorMessage(Exception(real));
    expect(message, contains('datos móviles'));
    expect(message, contains('fecha y hora'));
    expect(message, isNot(contains('java.lang')));
    expect(message, isNot(contains('SourceFile')));
  });

  test('rechazar la firma no es un error que haya que investigar', () {
    expect(
      walletErrorMessage(Exception('User rejected the request')),
      contains('Rechazaste'),
    );
  });

  test('falta de gas se nombra por lo que es', () {
    expect(
      walletErrorMessage(Exception('insufficient funds for gas * price')),
      contains('ETH de Base Sepolia'),
    );
  });

  test('lo desconocido se acorta a una línea legible', () {
    final message = walletErrorMessage(
      Exception('${'x' * 400}\nsegunda linea\ntercera'),
    );
    expect(message, isNot(contains('\n')));
    expect(message.length, lessThanOrEqualTo(141));
  });
}
