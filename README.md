# Waliki

**Pasarela de pagos no-custodial en USDT para negocios bolivianos.**
El cliente paga desde su propia billetera, el dinero llega **directo a la billetera del dueño** y la
plataforma verifica cada venta **leyendo la blockchain**. Proyecto para el **ETH Bolivia Buildathon
2026** (UNIVALLE Tiquipaya, Cochabamba · 11–13 de septiembre).

> **Fuente de verdad del plan**: Google Doc "Waliki — Plan de Proyecto (v4)" (31/08/2026).
> **Regla de oro**: el riel de pagos **nunca** custodia fondos.

## Las 3 fases (cada fase = un producto funcional)

| Fase | Producto | Núcleo |
|------|----------|--------|
| **1 — Pasarela de cobro** | La caja USDT, distribuible a cualquier negocio (alcance del Buildathon) | Pasarela **100% web** (el QR es una URL) · la **app Flutter se muestra en el demo**: caja funcional (solo lectura) + mockups de las fases 2–3 |
| **2 — Modo Fácil** | Billetera propia sin frase semilla + compra de saldo (QR bancario/tarjeta vía rampas asociadas) + KYC | Stablecoin propia: **decisión pendiente** (v4 §6.3; recomendación: "pesificación visual" sobre USDT) |
| **3 — Comercio** | E-commerce con los productos del negocio + deliveries | Escrow con **liquidación dividida on-chain**: el repartidor cobra al instante |

Capa transversal: ventas verificadas → puntaje comercial → **microcrédito con repago automático**.

## Fase 1 — el flujo de una venta

| Rol | ¿Conecta wallet? | Qué hace |
|-----|------------------|----------|
| **Dueño** | Sí (una vez) | Registra el comercio on-chain; su firma **canda** la dirección de cobro |
| **Cajero** | No (solo PIN) | Ingresa Bs → QR → espera la pantalla verde. Ve todo, no toca nada |
| **Cliente** | Sí | Escanea el QR → página de pago → `approve` + `pay` → comprobante |

La pantalla verde la dispara el **evento `PaymentReceived`** leído de la cadena — nunca una captura
del cliente. La wallet se conecta **solo para firmar**; para mirar o recibir, nunca.

## Stack
- **Contratos**: Solidity 0.8.28 · Hardhat · OpenZeppelin · red **Base Sepolia** (chainId 84532)
- **Web**: Vite + React + TypeScript · wagmi + viem + Reown AppKit · el QR es la URL de `/pay/:saleId`
- **App Waliki** (Flutter vía **FVM**, última estable): en el demo — caja de solo lectura (JSON-RPC)
  + mockups navegables; firma en app (Reown AppKit Flutter) post-evento
- Convención: **comentarios de código en inglés**; UI, documentación y comunicación en español

## Estructura (monorepo)
```
waliki/
  contracts/   # TestUSDT (ERC-20, 6 decimales, faucet con cooldown) + WalikiRouter
               # (registerMerchant / setPayoutAddress / pay + evento PaymentReceived)
               # test/ (7 tests) · scripts/deploy.ts → deployments/<red>.json
  web/         # /caja (cobro Bs→QR→verde) y /pay/:saleId (página de pago del cliente)
  backend/     # (experimento, fuera del riel no-custodial) NestJS: QR bancario en Bs
               # vía la Yesca API + liquidación automática en tUSDT
  packages/    # (futuro) ABI + tipos compartidos
  docs/        # PASO-0.md (checklist de cuentas) y siguientes
```

> 👉 **¿Te acabas de sumar al proyecto?** Empieza por **[`docs/HANDOFF.md`](docs/HANDOFF.md)**:
> estado real, arranque en 10 minutos, mapa del repo, reglas y trampas conocidas.

## Cómo correr el proyecto (dev)

**Prerequisitos**: Node 22+ · para la app: FVM (`dart pub global activate fvm`) — la versión de
Flutter la fija `app/.fvmrc` y `fvm install` la descarga sola.

Los contratos ya están desplegados en Base Sepolia (direcciones commiteadas en
`contracts/deployments/`), así que **no necesitas claves ni deploys para correr la web y la app**.

```bash
# Web — caja (/caja) y página de pago (/pay/:saleId)
cd web
cp .env.example .env       # pide el VITE_REOWN_PROJECT_ID por el grupo del equipo
npm install
npm run dev -- --host      # --host: para que un teléfono en tu WiFi pueda pagar

# App Flutter (caja solo-lectura + mockups)
cd app
fvm install                # primera vez: descarga el SDK pineado
fvm flutter run -d chrome  # o un dispositivo Android conectado

# Contratos — tests locales (no requiere .env)
cd contracts
npm install && npm test
```

Datos del demo: PIN de la caja **1234** · comercio #1 "Tienda Demo CBBA" · el QR de la app
codifica la URL de la web de pago y se cambia con el lápiz en la pantalla de cobro. Para
desplegar contratos o correr scripts on-chain sí necesitas `contracts/.env` (ver `.env.example`).

## Plan del spike y estado
- [x] **Paso 0 — Cuentas**: Reown projectId · MetaMask PC + 2 teléfonos · gas de Base Sepolia
- [x] **Paso 1 — Scaffolding**: `contracts/` compila y testea · `web/` build verificado
- [x] **Paso 2 — Contratos**: `TestUSDT` + `WalikiRouter` testeados (7/7) y **desplegados en
  Base Sepolia** — direcciones en `contracts/deployments/baseSepolia.json`
- [x] **Paso 3 — Página de pago**: completa y **probada con wallets reales** en escritorio y
  teléfono (01/09) — conectar, red forzada, faucet, `approve` + `pay`, comprobante, "ya pagada"
- [x] **Paso 4 — Caja**: completa y **circuito probado en dispositivos reales** (01/09): PIN →
  Bs → QR → pago desde teléfono → **pantalla verde con sonido disparada por el evento**
- [ ] **Paso 4b — App Waliki (Flutter)**: **implementada** — PIN, ventas reales leídas de la cadena,
  cobrar (Bs → QR → verde), historial on-chain y mockups de las fases 2-3; falta probarla en
  teléfono (APK requiere Android SDK)
- [ ] **Paso 5 — Prueba real**: deploy a Vercel + pago desde un teléfono que escanea el QR

**Criterios de "hecho" del spike**: conectar en escritorio Y en teléfono desde el QR · red forzada a
Base Sepolia · `approve` + `pay` reales · verde disparado por el EVENTO (no por "salió la tx") ·
manejo del rechazo del usuario y del cambio de cuenta.
