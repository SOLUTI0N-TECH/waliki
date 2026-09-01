# Waliki — Guía del proyecto (para Claude Code)

> **Qué es**: **pasarela de pagos no-custodial en USDT** para negocios bolivianos, construida por
> **fases-producto**. La Fase 1 (Buildathon) es la caja de cobro web: Bs → USDT → QR → verificación
> del pago **leyendo la blockchain**. Proyecto para el **ETH Bolivia Buildathon 2026** (UNIVALLE
> Tiquipaya, Cochabamba · 11–13 sep). Antes *Cobra.bo*; nombre definitivo **Waliki** ("está bien" en aymara).
> **Fuente de verdad del plan: Google Doc "Waliki — Plan de Proyecto (v4)"** (31/08/2026):
> https://docs.google.com/document/d/1x8mrS3fLbEtHpH7tkNiNacmAkVJC-GqoY0iuL6lE51g/
> Este proyecto NO tiene relación de código con `futures-ai-bot` (otro proyecto del mismo usuario).

## ⚠️ Regla de oro (innegociable)
**El riel de pagos de Waliki nunca custodia dinero**: los USDT viajan directo del pagador a la
billetera del comerciante; la plataforma solo lee la cadena, sugiere y registra. Únicas excepciones
previstas en el plan (NO en la Fase 1): el escrow de la Fase 3 (ejecutado por contrato público) y la
rampa de la Fase 2 (solo vía socios regulados o registro PSAV, previa consulta legal). Si algún
código va a tocar custodia de fondos o dinero fiat → **detente y pregunta**.

## Convenciones de trabajo
- **Responder en español** (idioma del usuario y del equipo). **Comentarios de código en INGLÉS**
  (regla del usuario, 31/08/2026). UI, docs y mensajes al usuario en español.
- **Todo el código de Waliki vive en este repo** (`C:\Yo\SolutionTech\waliki`).
- Secretos (`.env`, claves privadas) **nunca** se commitean (ya en `.gitignore`); jamás pedir la
  clave privada por chat — el usuario la pega él mismo en `contracts/.env`.
- El usuario pide análisis/decisión **antes** de implementar; no adelantarse a crear código sin
  pedido claro. Las preguntas se responden sin editar archivos; ofrecer la edición y esperar el sí.

## Las 3 fases (cada una se entrega como producto funcional, aunque sea MVP)
1. **Pasarela de cobro** (alcance del Buildathon): la pasarela es **100% web** — el QR es una URL
   (a futuro, enlace universal). **La app Flutter es la vitrina y SE MUESTRA EN EL BUILDATHON**:
   modo caja funcional (solo lecturas JSON-RPC: Bs→QR→verde por evento→historial; SIN firma dentro
   de la app) + secciones de Modo Fácil/Comercio/puntaje como **mockups navegables**. El pago del
   cliente es siempre por la página web del QR; firma en app y push llegan post-evento.
2. **Modo Fácil**: billetera propia sin frase semilla (ERC-4337/passkey) + compra de saldo con QR
   bancario o tarjeta vía rampas asociadas + KYC. **Pendiente ratificar** (v4 §6.3): NO emitir
   stablecoin propia — recomendación registrada: "pesificación visual" sobre USDT (el BCB ya trabaja
   su propio "boliviano digital"; emitir una privada colisiona con el ente emisor).
3. **Comercio**: e-commerce con productos del negocio + deliveries con escrow y **liquidación
   dividida on-chain** (el repartidor cobra al instante).
- Transversal: historial verificado → puntaje → microcrédito con repago automático (moat; pendiente
  ratificación del equipo).

## Alcance del MVP Fase 1 (Buildathon) — SIN BACKEND
- **Sin backend**: la cadena es la base de datos; el navegador lee los eventos por RPC (viem).
  WhatsApp, servicio de tasa P2P y PDF se difieren a la fase comercial post-evento.
- **Riel único: modo contrato.** El pagador ejecuta `pay()` desde su billetera. El "modo
  transferencia simple" desde exchange se difiere (necesita servidor: reservas de monto único +
  tolerancia a la comisión que el exchange descuenta).
- **Tasa Bs/USDT manual** (la fija el dueño), con cotización que **vence** (~15 min). Congelada en el QR.
- Extras del MVP: registro on-chain con **candado de la dirección de cobro** · red forzada a Base
  Sepolia en la página de pago · faucet de tUSDT integrado · trazabilidad (hash/bloque/
  confirmaciones/explorador) · semáforo de conexión + estado "pendiente de verificación" · kit demo
  (banner TESTNET, 3 billeteras prefinanciadas, video de respaldo).

### Roles (clave para entender el diseño)
| Rol | ¿Conecta wallet? | Qué hace |
|-----|------------------|----------|
| **Dueño** | Sí, una vez | Registra el comercio on-chain y su dirección de cobro (firma con su wallet) |
| **Cajero** | No — solo PIN | Ingresa Bs → muestra QR → espera la pantalla verde. Ve todo, no toca nada |
| **Cliente** | Sí | Escanea el QR → conecta → `approve` + `pay` → recibe su comprobante |

Principio: **la wallet se conecta SOLO para firmar** (pagar o registrarse). Para mirar/recibir, nunca.

## Stack
- **Contratos**: Solidity 0.8.28 + **Hardhat 2** + OpenZeppelin 5 · red **Base Sepolia** (chainId
  **84532**, RPC `https://sepolia.base.org`)
- **Web**: **Vite + React + TypeScript** · **wagmi + viem + Reown AppKit** (MetaMask extensión +
  móvil vía deep link) · **QR** = URL de `/pay/:saleId`
- **App Waliki** (Flutter vía **FVM**, última estable ~3.47.x — regla del usuario 31/08): en el demo
  del Buildathon con caja solo-lectura (JSON-RPC) + mockups; firma en app (Reown AppKit Flutter) y
  push, post-evento

## Estructura del monorepo
```
waliki/
  contracts/   # TestUSDT (ERC-20, 6 dec, faucet cooldown 1h, 100 tUSDT por claim)
               # WalikiRouter (registerMerchant/setPayoutAddress/pay + evento PaymentReceived;
               #   saleId bytes32; paidAmount evita doble pago; CEI; SafeERC20)
               # test/waliki.test.ts (7 tests) · scripts/deploy.ts → deployments/<red>.json (SÍ se commitea)
  web/         # /caja (cobro Bs→QR→verde) y /pay/:saleId (página de pago del cliente)
  design/      # mockups de la app (.dc.html + canvas.json) — fuente del canvas de Claude Design
  packages/    # (futuro) ABI + tipos compartidos
  docs/        # PASO-0.md (checklist de cuentas)
```

## Estado del plan (spike Fase 1)
- [x] Paso 0 — cuentas · [x] Paso 1 — scaffolding
- [x] **Paso 2 — contratos**: testeados (7/7) y **DESPLEGADOS en Base Sepolia** (01/09/2026).
  Direcciones en `contracts/deployments/baseSepolia.json` · ABIs en `web/src/contracts/waliki.json`
  (regenerar con `npm run export-abi`). `web/.env` ya tiene el projectId de Reown.
- [ ] Paso 3 — página de pago (conectar, forzar red, `approve`+`pay`, comprobante)
- [ ] Paso 4 — caja (Bs → QR → `watchContractEvent(saleId)` → verde)
- [ ] Paso 4b — **app Flutter del demo** (`app/` con FVM): caja solo-lectura (JSON-RPC) + mockups
  navegables de Modo Fácil, Comercio y puntaje
- [ ] Paso 5 — Vercel + pago real desde teléfono · kit demo + video + ensayo del pitch

**Criterios de "hecho"**: conectar en escritorio Y teléfono desde el QR · red forzada
(`switchChain`/`addChain`) · `approve` + `pay` reales · verde disparado por el EVENTO · manejo del
rechazo y del cambio de cuenta. Trampas conocidas: USDT necesita 2 tx (`approve`+`pay`); el pagador
necesita ETH de gas; el sonido en móvil requiere un gesto previo del usuario.

## Notas técnicas
- `contracts/`: Hardhat 2 + `@nomicfoundation/hardhat-toolbox-viem` (tests mocha/chai +
  chai-as-promised con `hre.viem`). Revert strings en español ASCII (sin acentos). Secretos en
  `contracts/.env`.
- `web/`: npm resolvió **Vite 8 · React 19 · TS 6 · wagmi v3** (lo fija el adapter de AppKit).
  ⚠️ wagmi v3 tiene API distinta de v2 — **verificar contra docs oficiales antes del Paso 3**, no
  asumir idioms de v2.

## Contexto de mercado y decisiones (para el pitch — NO es alcance del MVP)
- **Ago-2026**: bancos venden USDT desde sus apps (Bisa, Unión/Yasta, FIE); Peso + Yango Food cobran
  USDT en 2.000+ restaurantes; el gobierno evalúa USDT en el sistema nacional de pagos; 200+
  empresas en registro PSAV (RA UIF 019/2025, ASFI 540/2025 + Circular 885/2025, DS 5384).
  Diferencial de Waliki: **no-custodial + modo empleado ("ningún empleado va a tener la cuenta del
  jefe") + distribuible a cualquier negocio**.
- **Decisiones registradas**: pasarela web (el QR es una URL) = arquitectura resuelta (v4 §3) ·
  **el demo del Buildathon muestra TODO** — pasarela funcional + app (caja funcional solo-lectura +
  mockups de TODAS las fases) = decisión del fundador 31/08/2026, que REVISA la idea previa de
  "app post-evento": no volver a proponerla · stablecoin propia = recomendación NO, pendiente
  ratificación (v4 §6.3) · microcrédito como moat = pendiente ratificación (v4 §8).
- **Equipo y frentes**: **Daniel** toma el contrato de **permisos/roles** (que otros usuarios
  revisen transacciones) — coordinar con él antes de tocar `WalikiRouter` · referencia de UI:
  apps de cobro QR tipo QRápido/Yape Comercio (video de Natalia) — **patrón sí, marca no**;
  los mockups viven en `design/` (canvas de Claude Design).
