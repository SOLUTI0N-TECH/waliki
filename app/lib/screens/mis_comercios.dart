import 'package:flutter/material.dart';

import '../chain.dart';
import '../session.dart';
import '../ui.dart';
import '../skeletons.dart';
import '../wallet.dart';
import '../wallet_gate.dart';
import 'crear_comercio.dart';
import 'home.dart';
import 'cajeros.dart';
import 'welcome.dart';

/// Owner panel: every shop registered by the connected address, read straight
/// from MerchantRegistered logs (owner is an indexed topic).
class MisComerciosScreen extends StatefulWidget {
  final Session session;
  const MisComerciosScreen({super.key, required this.session});

  @override
  State<MisComerciosScreen> createState() => _MisComerciosScreenState();
}

class _MisComerciosScreenState extends State<MisComerciosScreen> {
  late Future<List<Merchant>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Chain.merchantsOf(widget.session.ownerAddress ?? '');
  }

  /// Pull to refresh; the builder below renders any failure on its own.
  Future<void> _refresh() async {
    setState(_reload);
    await _future.catchError((Object _) => <Merchant>[]);
  }

  Future<void> _crear() async {
    final created = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => CrearComercioScreen(session: widget.session),
      ),
    );
    if (!mounted) return;
    setState(_reload);
    if (created != null) _abrir(created);
  }

  void _abrir(int merchantId) {
    widget.session.merchantId = merchantId;
    widget.session.save();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            HomeScreen(session: widget.session, merchantId: merchantId),
      ),
    );
  }

  Future<void> _reconectar() async {
    final problema = await requireWallet(context, widget.session);
    if (!mounted) return;
    if (problema != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problema)));
      return;
    }
    // The owner may have come back on another account, which changes whose
    // shops these are.
    setState(_reload);
  }

  Future<void> _salir() async {
    await Wallet.instance.disconnect();
    await widget.session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => WelcomeScreen(session: widget.session)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.session.ownerAddress ?? '';
    return Scaffold(
      appBar: WalikiBar(
        title: 'Mis comercios',
        actions: [
          IconButton(
            tooltip: 'Desconectar',
            icon: const Icon(Icons.logout_rounded, size: 19, color: kInkSoft),
            onPressed: _salir,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(14),
              ),
              // The address alone used to be the whole story, and it comes off
              // disk: it said "Conectado" to owners whose wallet session was
              // long gone, which is why signing surprised them. The live flag
              // is the one that decides whether the next signature will work.
              child: ValueListenableBuilder<String?>(
                valueListenable: Wallet.instance.connection,
                builder: (context, _, _) {
                  final live = Wallet.instance.isConnected;
                  return Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 17,
                        color: live ? kBrand : kInkSoft,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        live ? 'Conectado como' : 'Billetera desconectada',
                        style: wk(size: 12.5, weight: 500, color: kInkSoft),
                      ),
                      const Spacer(),
                      if (live)
                        Text(
                          short(owner),
                          style: wk(size: 12.5, weight: 600, mono: true),
                        )
                      else
                        GestureDetector(
                          onTap: _reconectar,
                          child: Text(
                            'Reconectar',
                            style: wk(
                              size: 12.5,
                              weight: 700,
                              color: kBrandInk,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: kBrand,
                child: FutureBuilder<List<Merchant>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _Message(
                        icon: Icons.cloud_off_rounded,
                        title: 'Sin conexión con la cadena',
                        body: '${snap.error}',
                      );
                    }
                    if (!snap.hasData) {
                      return const MisComerciosSkeleton();
                    }
                    final list = snap.data!;
                    if (list.isEmpty) {
                      return _Message(
                        icon: Icons.storefront_outlined,
                        title: 'Todavía no tienes comercios',
                        body:
                            'Crea el primero: es una sola firma y tu negocio queda '
                            'registrado en la blockchain, con tu dirección de cobro candada.',
                      );
                    }
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      itemCount: list.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final m = list[i];
                        return _MerchantCard(
                          merchant: m,
                          onOpen: () => _abrir(m.id),
                          onLink: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CajerosScreen(
                                session: widget.session,
                                merchant: m,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: PrimaryButton('Crear comercio', onTap: _crear),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantCard extends StatelessWidget {
  final Merchant merchant;
  final VoidCallback onOpen;
  final VoidCallback onLink;

  const _MerchantCard({
    required this.merchant,
    required this.onOpen,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return WCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  merchant.displayName,
                  style: wk(size: 17, weight: 700, tracking: -0.02),
                ),
              ),
              WChip('#${merchant.id}', bg: kSurface2, fg: kInkSoft),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 13, color: kInkSoft),
              const SizedBox(width: 5),
              Text(
                'cobra en ${short(merchant.payout)}',
                style: wk(size: 11.5, weight: 500, color: kInkSoft, mono: true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Abrir caja',
                      style: wk(size: 14, weight: 700, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onLink,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kLine, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cajeros',
                      style: wk(size: 14, weight: 700, color: kBrandInk),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: kInkSoft),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: wk(size: 17, weight: 700),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            textAlign: TextAlign.center,
            style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.5),
          ),
        ],
      ),
    ),
  );
}
