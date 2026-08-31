# Waliki — Guía del proyecto (para Claude Code)

> **Qué es**: sistema de cobro **no-custodial en USDT** para comercios bolivianos. Un punto de venta
> web cobra en Bs, convierte a USDT, muestra un QR y **verifica el pago leyendo la blockchain**.
> Proyecto para el **ETH Bolivia Buildathon 2026** (UNIVALLE Tiquipaya, Cochabamba · 11–13 sep).
> Antes se llamaba *Cobra.bo*; nombre definitivo **Waliki** ("está bien" en aymara).
> Fuente de verdad del plan: Google Doc "Waliki — Plan de Proyecto" (Borrador v3).
> Este proyecto NO tiene relación de código con `futures-ai-bot` (otro proyecto del mismo usuario).

## ⚠️ Regla de oro (innegociable)
**Waliki nunca custodia dinero.** Los USDT viajan directo del pagador a la billetera del comerciante;
la plataforma solo lee la cadena, sugiere y registra. Ningún módulo debe retener, mover ni intermediar
fondos. Si algo va a tocar custodia de fondos → **detente y pregunta**.

## Convenciones de trabajo
- **Responder en español** (es el idioma del usuario y del equipo).
- **Todo el código de Waliki vive en este repo** (`C:\Yo\SolutionTech\waliki`). No mezclar con otros proyectos.
- Secretos (`.env`, project ids, claves) **nunca** se commitean (ya están en `.gitignore`).
- El usuario pide análisis/decisión **antes** de implementar; no adelantarse a crear código sin pedido claro.
  Las preguntas se responden sin editar archivos; ofrecer la edición y esperar el sí.

## Alcance de la Fase 1 (lo del Buildathon) — SIN BACKEND
Decisión del equipo (Anexo C del Google Doc):
- **Sin backend**: la cadena es la base de datos; el navegador lee los eventos por RPC (viem).
  Los servicios de experiencia del plan original (WhatsApp, servicio de tasa P2P, PDF) se difieren a la Etapa 2.
- **Un solo riel: modo contrato** (F3a). El pagador ejecuta `pay()` desde su billetera. El "modo
  transferencia simple" desde exchange (F3b) se difiere: sin servidor no hay reservas compartidas de
  "monto único", y además habría que tolerar la comisión que el exchange descuenta del monto enviado.
- **Tasa Bs/USDT manual** (la fija el dueño), con cotización que **vence** (~15 min). Congelada en el QR.

### Roles (clave para entender el diseño)
| Rol | ¿Conecta wallet? | Qué hace |
|-----|------------------|----------|
| **Dueño** | Sí, una vez | Registra el comercio on-chain y su dirección de cobro (firma con su wallet) |
| **Cajero** | No — solo PIN | Ingresa Bs → muestra QR → espera la pantalla verde. Ve todo, no toca nada |
| **Cliente** | Sí | Escanea el QR → conecta → `approve` + `pay` → recibe su comprobante |

Principio: **la wallet se conecta SOLO para firmar** (pagar o registrarse). Para mirar/recibir, nunca
(leer la cadena no requiere permisos; recibir tampoco requiere estar conectado).

### Funcionalidades que se agregan a la Fase 1
Registro on-chain del comerciante (candado de la dirección de cobro: un empleado no puede desviar los
pagos) · cotización con vencimiento · red forzada a Base Sepolia en la página de pago · faucet de tUSDT
integrado en la página de pago (demo) · trazabilidad de cada verde (hash/bloque/confirmaciones/enlace al
explorador) · semáforo de salud de conexión en la caja + estado "pendiente de verificación" · kit demo
(banner TESTNET, 3 billeteras prefinanciadas, video de respaldo).

## Stack
- **Contratos**: Solidity + **Hardhat** · red **Base Sepolia** (chainId **84532**, RPC `https://sepolia.base.org`)
- **Web**: **Vite + React + TypeScript** · **wagmi + viem + Reown AppKit** (MetaMask extensión + móvil vía deep link)
- **QR** = la URL de la página de pago (`/pay/:saleId`)
- **App móvil** (Flutter + Reown AppKit): después del Buildathon, no en la Fase 1

## Estructura del monorepo
```
waliki/
  contracts/   # Hardhat: TestUSDT (ERC-20, 6 decimales, faucet con cooldown)
               #          WalikiRouter (registerMerchant, pay(merchantId, saleId, amount), evento PaymentReceived)
  web/         # Vite + React: /caja (cobro Bs→QR→verde) y /pay/:saleId (página de pago del cliente)
  packages/    # (futuro) ABI + tipos compartidos
  docs/        # PASO-0.md (checklist de cuentas) y siguientes
```

## Plan del spike inicial (tarea: conexión con MetaMask)
El spike es **web, no Flutter** (la página de pago la abre el cliente al escanear un QR → tiene que ser
una URL en su navegador).
- **Paso 0 — Cuentas**: Reown projectId, MetaMask (PC + 2 teléfonos), ETH de Base Sepolia de faucet
  para ~3 direcciones, (opcional) RPC propio. Detalle en `docs/PASO-0.md`.
- **Paso 1 — Repo**: scaffolding de `contracts/` (Hardhat) y `web/` (Vite).
- **Paso 2 — Contratos**: `TestUSDT` + `WalikiRouter`; test en red local → deploy a Base Sepolia.
- **Paso 3 — Página de pago**: conectar wallet, forzar red, `approve` + `pay`, mostrar hash → recibo.
- **Paso 4 — Caja**: monto Bs → QR → `watchContractEvent(saleId)` → pantalla verde.
- **Paso 5 — Prueba real**: deploy a Vercel, pago desde un teléfono que escanea el QR.

**Criterios de "hecho" del spike**: conectar en escritorio Y en teléfono desde el QR · red forzada a
Base Sepolia (`switchChain`/`addChain`) · `approve` + `pay` reales · verde disparado por el EVENTO (no
por "salió la tx") · manejo del rechazo del usuario y del cambio de cuenta.
Trampas conocidas: USDT real necesita 2 tx (`approve` + `pay`); el pagador necesita ETH de gas en el
teléfono; el sonido en móvil requiere un gesto previo del usuario.

## Contexto de negocio (para el pitch — NO es alcance de la Fase 1)
- **Por qué existe**: en Bolivia (devaluación + inflación desde el fin del cambio fijo en jun-2026) el
  comercio ya cobra en USDT pero no tiene "caja registradora" para ese riel. Dolores: comprobantes de
  pago falsificados (capturas), caja indelegable, sin contabilidad. Waliki es la caja de ese riel.
- **Idea que da el moat** (visión, láminas del pitch): "adelanto de ventas con repago automático" — las
  ventas verificadas on-chain construyen un historial → puntaje → adelanto en USDT desde un pool → el
  contrato deriva un % de cada venta futura al pool hasta amortizar. El cobro es la infraestructura de
  datos y cobranza; el crédito es el negocio (patrón Square Capital / Mercado Pago).
- **Precedentes validados**: Venezuela = Crixto + Binance Pay en puntos de venta (2025); global =
  Shopify + Stripe + Coinbase con USDC on-chain en Base (2025). Ningún jugador global opera Bolivia.
- **Regulación**: pagos con activos virtuales permitidos (BCB 2024); marco 2025 = DS 5384 + ASFI
  540/2025 (Circular 885/2025, fintech/PSAV) + UIF 19/2025. Posición: software no-custodial, sin fiat
  ni custodia; el registro PSAV y KYC entran recién en la Etapa 2. Consultar antes de comercializar.

## Ideas descartadas (para no reproponerlas)
- **Ahorro automático en USDT recibiendo pagos en Bs**: descartada por el usuario — cambia de cliente
  (el que paga en Bs) en vez de reforzar el núcleo; es un on-ramp disfrazado, un nice-to-have.
- **Apilar capas de "libro" en el PoS del Buildathon** (2º riel completo, PDF server-side, etc.):
  fuera de la Fase 1 para no inflar las 48 h.

## Estado
- [x] Nombre y plan (Google Doc v3) · [x] repo inicializado · README + `docs/PASO-0.md` + `.gitignore`
- [ ] Paso 0 — cuentas · [ ] Paso 2 — contratos · [ ] Paso 3 — página de pago (spike MetaMask)
