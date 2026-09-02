import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Minimal JSON-RPC client for read-only chain access. The demo app never
/// signs anything: it reads state and event logs, exactly like the web caja.
class Rpc {
  static int _id = 0;

  /// Public RPC first; if it fails and a private fallback was injected
  /// (--dart-define=WALIKI_RPC=...), retry there. Event-day insurance.
  static Future<dynamic> call(String method, List<dynamic> params) async {
    try {
      return await _post(WalikiConfig.rpcUrl, method, params);
    } catch (_) {
      if (WalikiConfig.rpcFallback.isEmpty) rethrow;
      return await _post(WalikiConfig.rpcFallback, method, params);
    }
  }

  static Future<dynamic> _post(
      String url, String method, List<dynamic> params) async {
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': ++_id,
        'method': method,
        'params': params,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['error'] != null) {
      throw Exception(body['error']['message'] ?? 'RPC error');
    }
    return body['result'];
  }
}

// keccak-256 selectors precomputed offline with viem (see contracts/):
//   merchants(uint256)          -> 0x92c8823b
//   paidAmount(uint256,bytes32) -> 0x9378fd0b
const String _selMerchants = '92c8823b';
const String _selPaidAmount = '9378fd0b';

/// topic0 of PaymentReceived(uint256,bytes32,address,uint256,address)
const String paymentReceivedTopic =
    '0x0b385fcca75fcb7ea5db933cc6da0cc478e6a99e11d3596eedb8fde3897caff7';

String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');

String _wordFromHex(String h) =>
    h.replaceFirst('0x', '').toLowerCase().padLeft(64, '0');

BigInt _uint(String word) => BigInt.parse(word, radix: 16);

class Payment {
  final String saleId;
  final String payer;
  final String txHash;
  final BigInt amount;
  final BigInt block;

  const Payment({
    required this.saleId,
    required this.payer,
    required this.txHash,
    required this.amount,
    required this.block,
  });
}

class Chain {
  static Future<BigInt> blockNumber() async {
    final res = await Rpc.call('eth_blockNumber', []) as String;
    return BigInt.parse(res.substring(2), radix: 16);
  }

  static Future<String> merchantName(int id) async {
    final data = '0x$_selMerchants${_word(BigInt.from(id))}';
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': data},
      'latest',
    ]) as String;
    final hex = res.substring(2);
    // Return layout: owner · payout · string offset · string length · bytes
    if (hex.length < 64 * 5) return 'Comercio #$id';
    final len = _uint(hex.substring(64 * 3, 64 * 4)).toInt();
    final bytesHex = hex.substring(64 * 4, 64 * 4 + len * 2);
    final bytes = <int>[
      for (var i = 0; i < bytesHex.length; i += 2)
        int.parse(bytesHex.substring(i, i + 2), radix: 16),
    ];
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<BigInt> paidAmount(int merchantId, String saleId) async {
    final data =
        '0x$_selPaidAmount${_word(BigInt.from(merchantId))}${_wordFromHex(saleId)}';
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': data},
      'latest',
    ]) as String;
    return _uint(res.substring(2));
  }

  /// Public RPCs cap eth_getLogs at 10,000 blocks per request.
  static const int _logRange = 9900;

  static Future<List<dynamic>> _getLogs(
      List<dynamic> topics, BigInt from, BigInt to) async {
    return await Rpc.call('eth_getLogs', [
      {
        'address': WalikiConfig.router,
        'fromBlock': '0x${from.toRadixString(16)}',
        'toBlock': '0x${to.toRadixString(16)}',
        'topics': topics,
      }
    ]) as List<dynamic>;
  }

  /// All PaymentReceived logs for the demo merchant (optionally one sale).
  /// Scans in windows of <=9,900 blocks to respect the public RPC limit.
  static Future<List<Payment>> payments({String? saleId}) async {
    final topics = <dynamic>[
      paymentReceivedTopic,
      '0x${_word(BigInt.from(WalikiConfig.merchantId))}',
      if (saleId != null) '0x${_wordFromHex(saleId)}',
    ];
    final latest = await blockNumber();
    final range = BigInt.from(_logRange);
    final windows = <List<BigInt>>[];
    if (saleId != null) {
      // A live sale just got paid: the recent window is enough
      final from = latest > range ? latest - range : BigInt.zero;
      windows.add([from, latest]);
    } else {
      var from = BigInt.from(WalikiConfig.deployBlock);
      while (from <= latest) {
        var to = from + range;
        if (to > latest) to = latest;
        windows.add([from, to]);
        from = to + BigInt.one;
      }
    }
    final all = <dynamic>[];
    // Modest parallelism to stay under public RPC rate limits
    for (var i = 0; i < windows.length; i += 5) {
      final end = (i + 5 > windows.length) ? windows.length : i + 5;
      final results = await Future.wait([
        for (final w in windows.sublist(i, end)) _getLogs(topics, w[0], w[1]),
      ]);
      for (final r in results) {
        all.addAll(r);
      }
    }
    return [
      for (final l in all)
        Payment(
          saleId: l['topics'][2] as String,
          payer: '0x${(l['topics'][3] as String).substring(26)}',
          amount: _uint((l['data'] as String).substring(2, 66)),
          txHash: l['transactionHash'] as String,
          block: BigInt.parse((l['blockNumber'] as String).substring(2), radix: 16),
        ),
    ];
  }
}
