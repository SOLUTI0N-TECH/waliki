import 'package:flutter/material.dart';

import 'session.dart';
import 'ui.dart';
import 'wallet.dart';

/// What every screen has to do before asking for a signature.
///
/// Shared because getting it wrong is invisible: a screen that only checks
/// `Wallet.instance.isConnected` sees "not connected" for a wallet that is
/// still paired — the flag lives in process memory, the WalletConnect session
/// lives on disk — and silently does something else instead of signing.
///
/// Returns null when it is safe to sign, or the message to show the owner.
Future<String?> requireWallet(BuildContext context, Session session) async {
  String? address;
  try {
    address = await Wallet.instance.ensureConnected(context);
  } catch (e) {
    return walletErrorMessage(e);
  }

  if (address == null) {
    return 'Necesitas conectar tu billetera para firmar esta operación.';
  }

  final owner = session.ownerAddress?.toLowerCase();
  if (owner == null || owner == address) return null;

  // A different MetaMask account came back. Signing with it while the app
  // keeps watching the chain for the old one means the transaction lands and
  // the screen waits forever, so this has to be resolved before signing.
  if (!context.mounted) return 'Se perdió la pantalla, intenta de nuevo.';
  final cambiar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Otra cuenta', style: wk(weight: 700)),
      content: Text(
        'Tu billetera está en ${short(address!)} y este teléfono quedó '
        'configurado con ${short(owner)}. Si continúas, pasas a usar la '
        'cuenta nueva: verás los comercios de esa cuenta, no los de la '
        'anterior.',
        style: wk(size: 13.5, weight: 500, color: kInkSoft, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancelar', style: wk(weight: 600, color: kInkSoft)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Usar la cuenta nueva', style: wk(weight: 700)),
        ),
      ],
    ),
  );

  if (cambiar != true) {
    return 'Cambia a la cuenta ${short(owner)} en tu billetera, o acepta usar '
        'la nueva.';
  }

  // Both move together: cobrar.dart stamps cashierAddress into every sale id,
  // and the owner is a cashier of their own shops.
  session.ownerAddress = address;
  session.cashierAddress = address;
  await session.save();
  return null;
}
