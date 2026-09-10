import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'config.dart';

/// Root navigator key.
///
/// AppKit stores the BuildContext it is built with and, once that context
/// unmounts, `modalContext` returns null and `openModalView` logs an error and
/// returns without opening anything. Screens come and go — the root navigator
/// does not — so the modal is built on this one instead.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Real wallet connection over WalletConnect (Reown AppKit).
///
/// Mobile only: the package ships Android/iOS implementations, so on web this
/// service reports `available == false` and the UI falls back to pasting the
/// public address. Waliki never holds a key — the wallet signs, we only ask.
class Wallet {
  Wallet._();
  static final Wallet instance = Wallet._();

  ReownAppKitModal? _modal;

  /// Carries the connected address as AppKit reports it, so screens react to
  /// the wallet instead of guessing when it will answer.
  final ValueNotifier<String?> connection = ValueNotifier<String?>(null);

  /// True while AppKit's own sheet is on screen.
  bool get isModalOpen => _modal?.isOpen ?? false;

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
      context: rootNavigatorKey.currentContext ?? context,
      projectId: WalikiConfig.reownProjectId,
      metadata: const PairingMetadata(
        name: 'Waliki',
        description: 'Cobros en USDT sin custodia',
        url: 'https://waliki-gules.vercel.app',
        icons: ['https://waliki-gules.vercel.app/favicon.png'],
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
    modal.onModalConnect.subscribe(_onConnect);
    modal.onModalDisconnect.subscribe(_onDisconnect);
    await _pinChain();
  }

  /// Pins AppKit's selected chain to Waliki's network.
  ///
  /// Left null, several of its own screens blow up on `selectedChain!` — the
  /// account view crashes on open (`wallet_features_page.dart:144`) and again
  /// on the receive button (`receive_page.dart:37`).
  Future<void> _pinChain() async {
    final modal = _modal;
    if (modal == null || modal.selectedChain != null) return;
    final chain = ReownAppKitModalNetworks.getNetworkInfo(
      'eip155',
      '${WalikiConfig.chainId}',
    );
    if (chain != null) await modal.selectChain(chain);
  }

  void _onConnect(ModalConnect? event) {
    _pinChain();
    // Waliki has no use for AppKit's account view: the wallet is here to sign,
    // not to be browsed. Close the sheet the moment the session exists, which
    // also keeps the user away from the crashing screens above.
    _modal?.closeModal();
    connection.value = address;
  }

  void _onDisconnect(ModalDisconnect? event) => connection.value = null;

  Future<void> openModal(BuildContext context) async {
    await init(context);
    final modal = _modal;
    if (modal == null) throw StateError('La billetera no esta disponible aqui');
    if (modal.modalContext == null) {
      // AppKit would just log and return, leaving the caller waiting forever.
      throw StateError(
        'La pantalla de la billetera se perdio, reinicia la app',
      );
    }
    // disconnect() clears AppKit's selected chain, so re-pin it here: from the
    // second connection onwards it would otherwise be null again.
    await _pinChain();
    await modal.openModalView();
  }

  /// Drops the WalletConnect session, so the next connect shows the wallet
  /// chooser again instead of the "already connected" view.
  Future<void> disconnect() async {
    final modal = _modal;
    // isConnected can still be false while a stored session is being restored,
    // and that half-session is enough for openModalView to show the account
    // view instead of the wallet chooser.
    if (modal == null || (!modal.isConnected && modal.session == null)) return;
    try {
      await modal.disconnect();
    } catch (_) {
      // The wallet may be gone already; what matters is that we drop it here.
    }
    // A WalletConnect session is not cleared by disconnect() itself. The
    // package says so: "if sessionService.isWC then _cleanSession() is being
    // called on sessionDelete event" — an event that arrives from the relay
    // after this await returns. Until it lands, openModalView still believes
    // it is connected and forces its account view instead of the chooser, so
    // wait for the flag rather than race the network.
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (modal.isConnected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    connection.value = null;
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
