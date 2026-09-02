# Waliki — app (demo del Buildathon)

Caja de cobro **de solo lectura** (JSON-RPC a Base Sepolia — la app jamás firma ni guarda
llaves) + mockups navegables de las fases 2-3. El cliente paga en la página web que abre el QR.

## Correr

```bash
fvm install                # primera vez: descarga el Flutter pineado en .fvmrc
fvm flutter run -d chrome  # o un dispositivo Android conectado
```

- PIN del cajero: `1234` (en `lib/config.dart`)
- El QR codifica `WalikiConfig.payBaseUrl` — editable en la pantalla de cobro (icono lápiz);
  debe apuntar a la web de pago (IP de red en dev, la URL de Vercel en producción)
- RPC de respaldo opcional (día del evento): `fvm flutter run --dart-define=WALIKI_RPC=https://...`

## Qué es real y qué es concepto

**Real** (lecturas de la blockchain): PIN, inicio con ventas verificadas, COBRAR
(Bs → QR → pantalla verde disparada por la cadena), historial.
**Concepto** (banda morada): Modo Fácil (F2), Comercio (F3) y Puntaje — mockups navegables.
