import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'abi.dart';
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

  /// Sends a transaction to the router from the connected wallet and returns
  /// the hash the wallet reports.
  Future<String?> _sendToRouter(String data) async {
    final modal = _modal;
    if (modal == null || modal.session == null) {
      throw StateError('No hay billetera conectada');
    }
    final from = address;
    if (from == null) throw StateError('No hay dirección conectada');

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

  /// registerMerchant(payout, name). Also registers the owner as a cashier of
  /// their own shop, so they can charge from this same phone right away.
  Future<String?> registerMerchant({
    required String payout,
    required String name,
  }) async => _sendToRouter(encodeRegisterMerchant(payout: payout, name: name));

  /// addCashier(merchantId, cashier, label). The cashier signs nothing: the
  /// owner authorizes the address their app derived for that register.
  Future<String?> addCashier({
    required int merchantId,
    required String cashier,
    required String label,
  }) async => _sendToRouter(
    encodeAddCashier(merchantId: merchantId, cashier: cashier, label: label),
  );

  /// removeCashier(merchantId, cashier). Takes effect immediately: sales that
  /// register issued and nobody paid yet stop being payable.
  Future<String?> removeCashier({
    required int merchantId,
    required String cashier,
  }) async => _sendToRouter(
    encodeRemoveCashier(merchantId: merchantId, cashier: cashier),
  );
}

// keccak-256 selectors, precomputed so the app needs no hashing library.
// contracts/test/waliki.test.ts asserts every one of them against the
// compiled contract; test/abi_test.dart pins the calldata these build.
const String selRegisterMerchant = 'a6c8a384';
const String selAddCashier = '7961ffdc';
const String selRemoveCashier = 'ed164620';

/// Offset of the string argument, in bytes: it is the size of the head, so it
/// is 0x40 with two head words and 0x60 with three. Getting this wrong does
/// NOT revert -- the transaction lands and emits a garbled label.
const String _offset2Words =
    '0000000000000000000000000000000000000000000000000000000000000040';
const String _offset3Words =
    '0000000000000000000000000000000000000000000000000000000000000060';

/// selector | payout | offset 0x40 | length | utf8 bytes
String encodeRegisterMerchant({required String payout, required String name}) =>
    '0x$selRegisterMerchant'
    '${abiWordHex(payout)}$_offset2Words${abiStringTail(name)}';

/// selector | merchantId | cashier | offset 0x60 | length | utf8 bytes
String encodeAddCashier({
  required int merchantId,
  required String cashier,
  required String label,
}) =>
    '0x$selAddCashier'
    '${abiWordInt(merchantId)}${abiWordHex(cashier)}'
    '$_offset3Words${abiStringTail(label)}';

/// selector | merchantId | cashier
String encodeRemoveCashier({
  required int merchantId,
  required String cashier,
}) => '0x$selRemoveCashier${abiWordInt(merchantId)}${abiWordHex(cashier)}';
