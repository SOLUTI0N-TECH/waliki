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
    String url,
    String method,
    List<dynamic> params,
  ) async {
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
//   merchantCount()             -> 0x89105185
const String _selMerchants = '92c8823b';
const String _selPaidAmount = '9378fd0b';
const String _selMerchantCount = '89105185';

/// topic0 of PaymentReceived(uint256,bytes32,address,uint256,address)
const String paymentReceivedTopic =
    '0x0b385fcca75fcb7ea5db933cc6da0cc478e6a99e11d3596eedb8fde3897caff7';

/// topic0 of MerchantRegistered(uint256,address,address,string)
const String merchantRegisteredTopic =
    '0x037fddc1b3113ac1da8bedf43384dd2830a0409fdb349f3cd03c79f9c0a09dbc';

String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');

String _wordFromHex(String h) =>
    h.replaceFirst('0x', '').toLowerCase().padLeft(64, '0');

BigInt _uint(String word) => BigInt.parse(word, radix: 16);

/// Last 20 bytes of a 32-byte word, as a 0x address.
String _addr(String word) => '0x${word.substring(24)}';

/// Decodes a dynamic string laid out as: length word, then UTF-8 bytes.
String _string(String hexFromLength) {
  if (hexFromLength.length < 64) return '';
  final len = _uint(hexFromLength.substring(0, 64)).toInt();
  if (len == 0 || hexFromLength.length < 64 + len * 2) return '';
  final bytesHex = hexFromLength.substring(64, 64 + len * 2);
  final bytes = <int>[
    for (var i = 0; i < bytesHex.length; i += 2)
      int.parse(bytesHex.substring(i, i + 2), radix: 16),
  ];
  return utf8.decode(bytes, allowMalformed: true);
}

class Merchant {
  final int id;
  final String owner;
  final String payout;
  final String name;

  const Merchant({
    required this.id,
    required this.owner,
    required this.payout,
    required this.name,
  });

  String get displayName => name.isEmpty ? 'Comercio #$id' : name;
}

class Payment {
  final String saleId;
  final String payer;
  final String txHash;
  final BigInt amount;
  final BigInt block;

  /// Unix seconds. Logs carry no timestamp, so this is resolved separately.
  final int? timestamp;

  const Payment({
    required this.saleId,
    required this.payer,
    required this.txHash,
    required this.amount,
    required this.block,
    this.timestamp,
  });

  Payment withTime(int? t) => Payment(
    saleId: saleId,
    payer: payer,
    txHash: txHash,
    amount: amount,
    block: block,
    timestamp: t,
  );

  DateTime? get date => timestamp == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(timestamp! * 1000);
}

class Chain {
  static Future<BigInt> blockNumber() async {
    final res = await Rpc.call('eth_blockNumber', []) as String;
    return BigInt.parse(res.substring(2), radix: 16);
  }

  static Future<int> merchantCount() async {
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': '0x$_selMerchantCount'},
      'latest',
    ]) as String;
    return _uint(res.substring(2)).toInt();
  }

  /// Full merchant record. Return layout: owner | payout | offset | len | bytes
  static Future<Merchant> merchant(int id) async {
    final data = '0x$_selMerchants${_word(BigInt.from(id))}';
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': data},
      'latest',
    ]) as String;
    final hex = res.substring(2);
    if (hex.length < 64 * 4) {
      return Merchant(id: id, owner: '', payout: '', name: '');
    }
    return Merchant(
      id: id,
      owner: _addr(hex.substring(0, 64)),
      payout: _addr(hex.substring(64, 128)),
      name: _string(hex.substring(64 * 3)),
    );
  }

  static Future<String> merchantName(int id) async =>
      (await merchant(id)).displayName;

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
    List<dynamic> topics,
    BigInt from,
    BigInt to,
  ) async {
    return await Rpc.call('eth_getLogs', [
      {
        'address': WalikiConfig.router,
        'fromBlock': '0x${from.toRadixString(16)}',
        'toBlock': '0x${to.toRadixString(16)}',
        'topics': topics,
      },
    ]) as List<dynamic>;
  }

  /// Scans in windows of <=9,900 blocks to respect the public RPC limit.
  static Future<List<dynamic>> _scanLogs(
    List<dynamic> topics, {
    bool recentOnly = false,
  }) async {
    final latest = await blockNumber();
    final range = BigInt.from(_logRange);
    final windows = <List<BigInt>>[];
    if (recentOnly) {
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
    return all;
  }

  /// All PaymentReceived logs for a merchant (optionally a single sale).
  static Future<List<Payment>> payments({
    int? merchantId,
    String? saleId,
  }) async {
    final id = merchantId ?? WalikiConfig.merchantId;
    final topics = <dynamic>[
      paymentReceivedTopic,
      '0x${_word(BigInt.from(id))}',
      if (saleId != null) '0x${_wordFromHex(saleId)}',
    ];
    final logs = await _scanLogs(topics, recentOnly: saleId != null);
    return [
      for (final l in logs)
        Payment(
          saleId: l['topics'][2] as String,
          payer: _addr(_wordFromHex(l['topics'][3] as String)),
          amount: _uint((l['data'] as String).substring(2, 66)),
          txHash: l['transactionHash'] as String,
          block: BigInt.parse(
            (l['blockNumber'] as String).substring(2),
            radix: 16,
          ),
        ),
    ];
  }

  /// Every shop registered by this owner.
  ///
  /// Two strategies. While the registry is small, enumerating ids straight
  /// from storage costs one round trip per batch of 10 and stays fast forever;
  /// once it grows past the cap, filtering MerchantRegistered logs by the
  /// indexed `owner` topic is cheaper than reading every record.
  static Future<List<Merchant>> merchantsOf(String owner) async {
    final want = owner.toLowerCase();
    const enumerateUpTo = 200;
    final count = await merchantCount();
    if (count <= enumerateUpTo) {
      final found = <Merchant>[];
      for (var i = 1; i <= count; i += 10) {
        final end = (i + 10 > count + 1) ? count + 1 : i + 10;
        final batch = await Future.wait([
          for (var id = i; id < end; id++) merchant(id),
        ]);
        found.addAll(batch.where((m) => m.owner.toLowerCase() == want));
      }
      return found;
    }
    return _merchantsOfViaLogs(owner);
  }

  static Future<List<Merchant>> _merchantsOfViaLogs(String owner) async {
    final topics = <dynamic>[
      merchantRegisteredTopic,
      null,
      '0x${_wordFromHex(owner)}',
    ];
    final logs = await _scanLogs(topics);
    final out = <Merchant>[];
    for (final l in logs) {
      // data layout: payout | string offset | length | bytes
      final data = (l['data'] as String).substring(2);
      out.add(
        Merchant(
          id: _uint(_wordFromHex(l['topics'][1] as String)).toInt(),
          owner: owner,
          payout: _addr(data.substring(0, 64)),
          name: data.length > 128 ? _string(data.substring(128)) : '',
        ),
      );
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  /// Resolves real block timestamps (logs carry none). Deduplicates and caps
  /// the round-trips; anything past the cap is estimated from Base's ~2s
  /// block time, anchored on the oldest block actually fetched.
  static Future<Map<BigInt, int>> blockTimes(Iterable<BigInt> blocks) async {
    final unique = blocks.toSet().toList()..sort((a, b) => b.compareTo(a));
    final out = <BigInt, int>{};
    const cap = 60;
    final fetch = unique.take(cap).toList();
    for (var i = 0; i < fetch.length; i += 6) {
      final end = (i + 6 > fetch.length) ? fetch.length : i + 6;
      final res = await Future.wait([
        for (final b in fetch.sublist(i, end))
          Rpc.call('eth_getBlockByNumber', ['0x${b.toRadixString(16)}', false]),
      ]);
      for (var j = 0; j < res.length; j++) {
        final ts = res[j]?['timestamp'] as String?;
        if (ts != null) {
          out[fetch[i + j]] = int.parse(ts.substring(2), radix: 16);
        }
      }
    }
    if (unique.length > cap && out.isNotEmpty) {
      final anchorBlock = out.keys.reduce((a, b) => a < b ? a : b);
      final anchorTime = out[anchorBlock]!;
      for (final b in unique.skip(cap)) {
        out[b] = anchorTime - ((anchorBlock - b).toInt() * 2);
      }
    }
    return out;
  }

  /// Payments with their real dates attached — what the reports screen needs.
  static Future<List<Payment>> paymentsWithTime({int? merchantId}) async {
    final list = await payments(merchantId: merchantId);
    if (list.isEmpty) return list;
    final times = await blockTimes(list.map((p) => p.block));
    return [for (final p in list) p.withTime(times[p.block])];
  }
}
