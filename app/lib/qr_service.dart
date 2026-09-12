import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A bank QR issued by the Waliki backend, plus the settlement it triggers.
///
/// The customer pays bolivianos through the banking rail; the backend then
/// releases tUSDT to the shop. Those are two different moments, and this type
/// keeps them apart: [completed] is the bank saying the Bs arrived, while
/// [transferred] is the tUSDT having actually left.
class FiatQr {
  final String id;

  /// Yesca's own: pending · completed · expired · cancelled.
  final String status;

  /// The tUSDT reached the shop. This is what turns the screen green.
  final bool transferred;
  final String? txHash;

  /// Why the settlement failed, if it did. The backend retries on the next
  /// status call, so this is informative, not final.
  final String? lastError;
  final DateTime? expiresAt;

  const FiatQr({
    required this.id,
    required this.status,
    required this.transferred,
    this.txHash,
    this.lastError,
    this.expiresAt,
  });

  bool get completed => status.toLowerCase() == 'completed';
  bool get dead =>
      status.toLowerCase() == 'expired' || status.toLowerCase() == 'cancelled';

  static FiatQr parse(Map<String, dynamic> json) => FiatQr(
    id: '${json['id']}',
    status: '${json['status'] ?? 'pending'}',
    transferred: json['transferred'] == true,
    txHash: json['txHash'] as String?,
    lastError: json['lastError'] as String?,
    expiresAt: DateTime.tryParse('${json['expires_at']}')?.toLocal(),
  );

  /// The QR image, which only the create call carries.
  static Uint8List? image(Map<String, dynamic> json) {
    final raw = json['base64'];
    if (raw is! String || raw.isEmpty) return null;
    // Yesca may or may not prefix it as a data: URL.
    final comma = raw.indexOf(',');
    final payload = raw.startsWith('data:') && comma > 0
        ? raw.substring(comma + 1)
        : raw;
    try {
      return base64Decode(payload.trim());
    } catch (_) {
      return null;
    }
  }
}

/// Raised with a message already fit to show a cashier.
class QrServiceException implements Exception {
  final String message;
  const QrServiceException(this.message);
  @override
  String toString() => message;
}

/// Client for the Waliki backend that issues bank QRs.
class QrService {
  static const String baseUrl = String.fromEnvironment(
    'WALIKI_BACKEND',
    defaultValue: 'https://waliki.ficct.online',
  );

  /// Creating asks the gateway for a QR, so it gets more room than a poll.
  static const Duration _createTimeout = Duration(seconds: 20);
  static const Duration _statusTimeout = Duration(seconds: 12);

  /// Issues the QR. [saleId] and [merchantId] make the backend settle through
  /// WalikiRouter, which is what puts the sale in the app's own history.
  static Future<(FiatQr, Uint8List?)> create({
    required double bs,
    required BigInt units,
    required String destinationWallet,
    required int merchantId,
    required String saleId,
    String? description,
  }) async {
    final body = <String, dynamic>{
      'amount': double.parse(bs.toStringAsFixed(2)),
      // The backend rejects more than 6 decimals, and float division can
      // produce 8.688096999999999 out of an exact 8.688097.
      'cryptoAmount': double.parse((units.toDouble() / 1e6).toStringAsFixed(6)),
      'destinationWallet': destinationWallet,
      'merchantId': merchantId,
      'saleId': saleId,
      if (description != null && description.isNotEmpty)
        'description': description,
    };
    final json = await _send(
      () => http.post(
        Uri.parse('$baseUrl/qr'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode(body),
      ),
      _createTimeout,
      'No se pudo generar el QR',
    );
    return (FiatQr.parse(json), FiatQr.image(json));
  }

  /// Asking also settles: the backend releases the tUSDT the first time it
  /// sees the QR paid, and retries here if that failed.
  static Future<FiatQr> status(String id) async {
    final json = await _send(
      () => http.get(
        Uri.parse('$baseUrl/qr/$id/status'),
        headers: const {'accept': 'application/json'},
      ),
      _statusTimeout,
      'No se pudo consultar el cobro',
    );
    return FiatQr.parse(json);
  }

  static Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() call,
    Duration timeout,
    String whenFailing,
  ) async {
    final http.Response res;
    try {
      res = await call().timeout(timeout);
    } catch (_) {
      throw QrServiceException('$whenFailing: sin conexión con el servicio.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      throw QrServiceException('$whenFailing: respuesta inesperada.');
    }
    throw QrServiceException('$whenFailing: ${_message(decoded, res)}');
  }

  /// Nest answers `{message: string | string[], error, statusCode}`.
  static String _message(Object? decoded, http.Response res) {
    if (decoded is Map) {
      final m = decoded['message'];
      if (m is String && m.isNotEmpty) return m;
      if (m is List && m.isNotEmpty) return m.join(' · ');
      final e = decoded['error'];
      if (e is String && e.isNotEmpty) return e;
    }
    return 'error ${res.statusCode}';
  }
}
