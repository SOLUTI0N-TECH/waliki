import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'abi.dart';
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
    if (res.statusCode != 200) {
      // Rate limits answer 429 with an HTML body: fail with something legible
      // instead of letting jsonDecode throw a FormatException.
      throw Exception('RPC HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['error'] != null) {
      throw Exception(body['error']['message'] ?? 'RPC error');
    }
    return body['result'];
  }
}

// keccak-256 selectors and topic0, precomputed so the app carries no ABI.
// contracts/test/waliki.test.ts asserts all of them against the compiled
// contract, and test/abi_test.dart re-hashes the signatures here.
const String selMerchants = '92c8823b'; // merchants(uint256)
const String selPaidAmount = '9378fd0b'; // paidAmount(uint256,bytes32)
const String selMerchantCount = '89105185'; // merchantCount()
const String selIsCashier = '909cf575'; // isCashier(uint256,address)

/// topic0 of PaymentReceived(uint256,bytes32,address,uint256,address)
const String paymentReceivedTopic =
    '0x0b385fcca75fcb7ea5db933cc6da0cc478e6a99e11d3596eedb8fde3897caff7';

/// topic0 of MerchantRegistered(uint256,address,address,string)
const String merchantRegisteredTopic =
    '0x037fddc1b3113ac1da8bedf43384dd2830a0409fdb349f3cd03c79f9c0a09dbc';

/// topic0 of CashierAdded(uint256,address,string)
const String cashierAddedTopic =
    '0xe3343999af5709fd77744d1e75d1f52604472c522e29a62cde2e4e284cba55ec';

/// topic0 of CashierRemoved(uint256,address)
const String cashierRemovedTopic =
    '0x54a78a91dea4745892ac90c82e3b81b4bbff52f2d6bececff18bff4fc2608fc7';

/// A fresh sale id: the cashier in the first 20 bytes, 12 random after it.
///
/// The router reads that prefix and refuses to settle unless it is one of the
/// shop's authorized cashiers, so the attribution is sealed into a field the
/// payer cannot rewrite without simply paying a different sale -- one no cash
/// register is waiting for.
String buildSaleId(String cashier) {
  final rnd = Random.secure();
  final tail = List.generate(
    12,
    (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '0x${cashier.replaceFirst('0x', '').toLowerCase()}$tail';
}

/// The cashier a sale belongs to. Mirrors cashierOf() in the contract.
String cashierOf(String saleId) =>
    '0x${saleId.replaceFirst('0x', '').toLowerCase().substring(0, 40)}';

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

/// A register authorized by a shop. The label is only ever in the event log --
/// the contract does not store it -- so it can be missing while isCashier
/// still says the address is good.
class Cashier {
  final String address;
  final String label;
  final bool active;

  const Cashier({
    required this.address,
    required this.label,
    required this.active,
  });
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

  /// The register that issued this sale, read out of the sale id exactly like
  /// the contract does. Derived rather than stored on purpose: it can never
  /// drift from the sale id, it costs nothing in the cache, and sales cached
  /// before cashiers existed still answer correctly.
  String get cashier => cashierOf(saleId);

  /// One `eth_getLogs` entry for PaymentReceived. Returns null instead of
  /// throwing so one malformed log cannot empty a whole history.
  ///
  /// topics: topic0 | merchantId | saleId | payer
  /// data:   amount | payout
  static Payment? fromLog(Object? log) {
    if (log is! Map) return null;
    try {
      final topics = log['topics'] as List<dynamic>;
      final data = log['data'] as String;
      return Payment(
        saleId: topics[2] as String,
        payer: abiAddr(abiWordHex(topics[3] as String)),
        amount: abiUint(data.substring(2, 66)),
        txHash: log['transactionHash'] as String,
        block: BigInt.parse(
          (log['blockNumber'] as String).substring(2),
          radix: 16,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    's': saleId,
    'p': payer,
    't': txHash,
    'a': amount.toString(),
    'b': block.toString(),
    if (timestamp != null) 'ts': timestamp,
  };

  /// Returns null rather than throwing: one bad entry must not cost the whole
  /// cache, it just falls back to reading that sale from the chain again.
  static Payment? fromJson(Object? json) {
    if (json is! Map) return null;
    final saleId = json['s'];
    final payer = json['p'];
    final txHash = json['t'];
    final amount = BigInt.tryParse('${json['a']}');
    final block = BigInt.tryParse('${json['b']}');
    if (saleId is! String ||
        payer is! String ||
        txHash is! String ||
        amount == null ||
        block == null) {
      return null;
    }
    return Payment(
      saleId: saleId,
      payer: payer,
      txHash: txHash,
      amount: amount,
      block: block,
      timestamp: json['ts'] is int ? json['ts'] as int : null,
    );
  }
}

/// Cache key for a shop's sales. It includes the router because merchant ids
/// restart at 1 on every redeploy: keyed by the id alone, a device that had
/// shop #1 cached would merge sales from two different contracts, inflate the
/// home total, and never correct itself.
String paymentsCacheKey(int merchantId) {
  final router = WalikiConfig.router.replaceFirst('0x', '').toLowerCase();
  return 'waliki.p2.${router.substring(0, 8)}.$merchantId';
}

/// Sales already read from the chain, kept on the device.
///
/// Without this, every time the register opens it re-reads the whole history
/// from the deploy block: 47 windowed `eth_getLogs` calls today, and about
/// four more for every further day the chain runs. Sequentially that measured
/// 33 s, and a window refused by the public RPC's rate limit silently costs
/// real sales. With it the first open pays that once and later ones ask only
/// for the blocks that appeared since.
class _PaymentCache {
  /// How far back to re-read instead of trusting the cache right up to the
  /// head, so a short reorg cannot leave a sale behind that no longer exists.
  static const int reorgDepth = 300;

  static String _listKey(int id) => paymentsCacheKey(id);
  static String _blockKey(int id) => '${paymentsCacheKey(id)}.block';

  /// The stored sales and the block they were read up to.
  static Future<(List<Payment>, BigInt?)> load(int id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_listKey(id));
      final upTo = BigInt.tryParse(p.getString(_blockKey(id)) ?? '');
      if (raw == null || upTo == null) return (const <Payment>[], null);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return (const <Payment>[], null);
      final list = <Payment>[];
      for (final entry in decoded) {
        final payment = Payment.fromJson(entry);
        if (payment != null) list.add(payment);
      }
      return (list, upTo);
    } catch (_) {
      // a corrupt cache is not worth a crash; it just rescans from the deploy
      return (const <Payment>[], null);
    }
  }

  static Future<void> save(int id, List<Payment> list, BigInt upTo) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _listKey(id),
        jsonEncode([for (final e in list) e.toJson()]),
      );
      await p.setString(_blockKey(id), upTo.toString());
    } catch (_) {
      // persistence is optional: the read already succeeded
    }
  }

  /// Rewrites the sales without moving the scanned-to mark. Used once the
  /// block timestamps are resolved, so they are not fetched again next time.
  static Future<void> update(int id, List<Payment> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_blockKey(id)) == null) return;
      await p.setString(
        _listKey(id),
        jsonEncode([for (final e in list) e.toJson()]),
      );
    } catch (_) {
      // persistence is optional
    }
  }
}

class Chain {
  static Future<BigInt> blockNumber() async {
    final res = await Rpc.call('eth_blockNumber', []) as String;
    return BigInt.parse(res.substring(2), radix: 16);
  }

  static Future<int> merchantCount() async {
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': '0x$selMerchantCount'},
      'latest',
    ]) as String;
    return abiUint(res.substring(2)).toInt();
  }

  /// Full merchant record. Return layout: owner | payout | offset | len | bytes
  static Future<Merchant> merchant(int id) async {
    final data = '0x$selMerchants${abiWord(BigInt.from(id))}';
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
      owner: abiAddr(hex.substring(0, 64)),
      payout: abiAddr(hex.substring(64, 128)),
      name: abiString(hex.substring(64 * 3)),
    );
  }

  static Future<String> merchantName(int id) async =>
      (await merchant(id)).displayName;

  static Future<BigInt> paidAmount(int merchantId, String saleId) async {
    final data =
        '0x$selPaidAmount${abiWord(BigInt.from(merchantId))}${abiWordHex(saleId)}';
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': data},
      'latest',
    ]) as String;
    return abiUint(res.substring(2));
  }

  /// Is this address authorized to issue sales for the shop? The one answer
  /// that never lies: storage, not a replay of events.
  static Future<bool> isCashier(int merchantId, String address) async {
    final data =
        '0x$selIsCashier${abiWordInt(merchantId)}${abiWordHex(address)}';
    final res = await Rpc.call('eth_call', [
      {'to': WalikiConfig.router, 'data': data},
      'latest',
    ]) as String;
    return abiUint(res.substring(2)) != BigInt.zero;
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

  /// One window, retried with a growing pause.
  ///
  /// The history spans dozens of windows and they go out in bursts, so the
  /// public RPC rate-limits one now and then. Without this a single refused
  /// window would throw away every payment the others found.
  static Future<List<dynamic>> _getLogsRetrying(
    List<dynamic> topics,
    BigInt from,
    BigInt to,
  ) async {
    Object error = Exception('RPC sin respuesta');
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _getLogs(topics, from, to);
      } catch (e) {
        error = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw error;
  }

  /// Scans in windows of <=9,900 blocks to respect the public RPC limit.
  static Future<List<dynamic>> _scanLogs(
    List<dynamic> topics, {
    bool recentOnly = false,
    BigInt? fromBlock,
    BigInt? to,
  }) async {
    final latest = to ?? await blockNumber();
    final range = BigInt.from(_logRange);
    final windows = <List<BigInt>>[];
    if (recentOnly) {
      final from = latest > range ? latest - range : BigInt.zero;
      windows.add([from, latest]);
    } else {
      var from = fromBlock ?? BigInt.from(WalikiConfig.deployBlock);
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
        for (final w in windows.sublist(i, end))
          _getLogsRetrying(topics, w[0], w[1]),
      ]);
      for (final r in results) {
        all.addAll(r);
      }
    }
    return all;
  }

  /// All PaymentReceived logs for a merchant (optionally a single sale).
  static Future<List<Payment>> payments({
    required int merchantId,
    String? saleId,
  }) async {
    final id = merchantId;
    final topics = <dynamic>[
      paymentReceivedTopic,
      '0x${abiWord(BigInt.from(id))}',
      if (saleId != null) '0x${abiWordHex(saleId)}',
    ];
    // Asking about one sale is a question about right now: it skips the cache
    // and only looks at recent blocks.
    if (saleId != null) {
      return _decodePayments(await _scanLogs(topics, recentOnly: true));
    }

    final (cached, scannedTo) = await _PaymentCache.load(id);
    final head = await blockNumber();
    var from = BigInt.from(WalikiConfig.deployBlock);
    if (scannedTo != null) {
      final resume = scannedTo - BigInt.from(_PaymentCache.reorgDepth);
      if (resume > from) from = resume;
    }
    final fresh = _decodePayments(
      await _scanLogs(topics, fromBlock: from, to: head),
    );

    // Everything from `from` upwards is re-derived by this scan, so the cache
    // only contributes what sits below it — a reorged-out sale disappears
    // instead of lingering. The contract allows one payment per saleId, so
    // that id is the identity.
    final merged = <String, Payment>{
      for (final p in cached)
        if (p.block < from) p.saleId: p,
      for (final p in fresh) p.saleId: p,
    };
    final list = merged.values.toList()
      ..sort((a, b) => a.block.compareTo(b.block));
    await _PaymentCache.save(id, list, head);
    return list;
  }

  static List<Payment> _decodePayments(List<dynamic> logs) => [
    for (final l in logs) ?Payment.fromLog(l),
  ];

  /// Every register the shop ever had, with its label and whether it is still
  /// active.
  ///
  /// Rebuilt from the logs and then CONFIRMED one by one. The logs alone are
  /// not enough: an alta-baja-alta cycle reads as whatever event happens to
  /// come last if they are replayed out of order, and a window the public RPC
  /// refused leaves the list short without an error. isCashier decides; the
  /// logs only supply the labels, which the contract does not store.
  static Future<List<Cashier>> cashiers(int merchantId) async {
    final logs = await _scanLogs(<dynamic>[
      [cashierAddedTopic, cashierRemovedTopic],
      '0x${abiWordInt(merchantId)}',
    ]);
    logs.sort((a, b) {
      final byBlock = _hexInt(a['blockNumber'])
          .compareTo(_hexInt(b['blockNumber']));
      return byBlock != 0
          ? byBlock
          : _hexInt(a['logIndex']).compareTo(_hexInt(b['logIndex']));
    });

    final labels = <String, String>{};
    final order = <String>[];
    for (final l in logs) {
      final topics = l['topics'] as List<dynamic>;
      if (topics.length < 3) continue;
      final address = abiAddr(abiWordHex(topics[2] as String));
      if (!order.contains(address)) order.add(address);
      // Re-adding an active cashier is how a register gets renamed, so the
      // last CashierAdded wins.
      if (topics[0] == cashierAddedTopic) {
        final data = (l['data'] as String).substring(2);
        labels[address] = data.length > 64 ? abiString(data.substring(64)) : '';
      }
    }

    final active = <bool>[];
    for (var i = 0; i < order.length; i += 8) {
      final end = (i + 8 > order.length) ? order.length : i + 8;
      active.addAll(
        await Future.wait([
          for (final a in order.sublist(i, end)) isCashier(merchantId, a),
        ]),
      );
    }

    return [
      for (var i = 0; i < order.length; i++)
        Cashier(
          address: order[i],
          label: labels[order[i]] ?? '',
          active: active[i],
        ),
    ];
  }

  static BigInt _hexInt(Object? hex) =>
      hex is String ? BigInt.parse(hex.substring(2), radix: 16) : BigInt.zero;

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
      '0x${abiWordHex(owner)}',
    ];
    final logs = await _scanLogs(topics);
    final out = <Merchant>[];
    for (final l in logs) {
      // data layout: payout | string offset | length | bytes
      final data = (l['data'] as String).substring(2);
      out.add(
        Merchant(
          id: abiUint(abiWordHex(l['topics'][1] as String)).toInt(),
          owner: owner,
          payout: abiAddr(data.substring(0, 64)),
          name: data.length > 128 ? abiString(data.substring(128)) : '',
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
  static Future<List<Payment>> paymentsWithTime({
    required int merchantId,
  }) async {
    final list = await payments(merchantId: merchantId);
    if (list.isEmpty) return list;
    // A block's timestamp never changes, so only the ones still missing cost a
    // round trip — the rest came back from the cache already resolved.
    final missing = [
      for (final p in list)
        if (p.timestamp == null) p.block,
    ];
    if (missing.isEmpty) return list;
    final times = await blockTimes(missing);
    final filled = [
      for (final p in list)
        p.timestamp == null ? p.withTime(times[p.block]) : p,
    ];
    await _PaymentCache.update(merchantId, filled);
    return filled;
  }
}
