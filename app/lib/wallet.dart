import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'config.dart';

/// Real wallet connection over WalletConnect (Reown AppKit).
///
/// Mobile only: the package ships Android/iOS implementations, so on web this
/// service reports `available == false` and the UI falls back to pasting the
/// public address. Waliki never holds a key — the wallet signs, we only ask.
class Wallet {
  Wallet._();
  static final Wallet instance = Wallet._();

  ReownAppKitModal? _modal;

  /// The connected address, or null when there is no session.
  String? get address {
    final a = _modal?.session?.getAddress('eip155');
    return a?.toLowerCase();
  }

  bool get isConnected => _modal?.isConnected ?? false;

  /// True once init() succeeded on a platform AppKit supports.
  bool get available => _modal != null;

  /// Safe to call repeatedly; only the first call builds the modal.
  Future<void> init(BuildContext context) async {
    if (_modal != null) return;
    if (WalikiConfig.reownProjectId.isEmpty) return;
    final modal = ReownAppKitModal(
      context: context,
      projectId: WalikiConfig.reownProjectId,
      metadata: const PairingMetadata(
        name: 'Waliki',
        description: 'Cobros en USDT sin custodia',
        url: 'https://waliki-gules.vercel.app',
        icons: ['https://waliki-gules.vercel.app/favicon.svg'],
        redirect: Redirect(native: 'waliki://', universal: null),
      ),
      optionalNamespaces: {
        'eip155': const RequiredNamespace(
          chains: ['eip155:${WalikiConfig.chainId}'],
          methods: [
            'eth_sendTransaction',
            'personal_sign',
            'eth_accounts',
            'wallet_switchEthereumChain',
            'wallet_addEthereumChain',
          ],
          events: ['chainChanged', 'accountsChanged'],
        ),
      },
    );
    await modal.init();
    _modal = modal;
  }

  Future<void> openModal(BuildContext context) async {
    await init(context);
    await _modal?.openModalView();
  }

  /// Drops the WalletConnect session, so the next connect shows the wallet
  /// chooser again instead of the "already connected" view.
  Future<void> disconnect() async {
    final modal = _modal;
    if (modal == null || !modal.isConnected) return;
    try {
      await modal.disconnect();
    } catch (_) {
      // The wallet may be gone already; what matters is that we drop it here.
    }
  }

  /// Sends registerMerchant(payout, name) from the connected wallet and
  /// returns the transaction hash the wallet reports.
  ///
  /// Calldata is hand-encoded so the app keeps zero ABI dependencies:
  ///   selector | payout (32B) | offset 0x40 (32B) | length (32B) | utf8 bytes
  Future<String?> registerMerchant({
    required String payout,
    required String name,
  }) async {
    final modal = _modal;
    if (modal == null || modal.session == null) {
      throw StateError('No hay billetera conectada');
    }
    final from = address;
    if (from == null) throw StateError('No hay dirección conectada');

    final data = _encodeRegisterMerchant(payout: payout, name: name);
    final result = await modal.request(
      topic: modal.session!.topic,
      chainId: 'eip155:${WalikiConfig.chainId}',
      request: SessionRequestParams(
        method: 'eth_sendTransaction',
        params: [
          {
            'from': from,
            'to': WalikiConfig.router,
            'data': data,
            'value': '0x0',
          },
        ],
      ),
    );
    return result?.toString();
  }
}

/// keccak-256 selector of registerMerchant(address,string), precomputed with
/// viem so the app needs no hashing library.
const String _selRegisterMerchant = 'a6c8a384';

String _pad(String hexNoPrefix) => hexNoPrefix.padLeft(64, '0');

String _encodeRegisterMerchant({required String payout, required String name}) {
  final addr = _pad(payout.replaceFirst('0x', '').toLowerCase());
  const offset =
      '0000000000000000000000000000000000000000000000000000000000000040';
  final bytes = utf8.encode(name);
  final len = _pad(bytes.length.toRadixString(16));
  final body = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  // right-pad the string body to a whole 32-byte word
  final padded = body.padRight(((body.length + 63) ~/ 64) * 64, '0');
  return '0x$_selRegisterMerchant$addr$offset$len$padded';
}
