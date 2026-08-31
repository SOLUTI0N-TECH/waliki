# Waliki

**Sistema de cobro no-custodial en USDT para comercios bolivianos.**
Punto de venta (web) que cobra en Bs, convierte a USDT, muestra un QR y **verifica el pago leyendo
la blockchain** — sin intermediar los fondos. Proyecto para el **ETH Bolivia Buildathon 2026**
(UNIVALLE Tiquipaya, Cochabamba · 11–13 de septiembre).

> Antes se llamaba *Cobra.bo*. Nombre definitivo: **Waliki** ("está bien" en aymara).
> Plan completo del equipo: Google Doc "Waliki — Plan de Proyecto" (Borrador v3).

## Regla de oro
**Waliki nunca custodia dinero.** Los USDT viajan directo del pagador a la billetera del comerciante.
La plataforma solo lee la cadena, sugiere y registra.

## Alcance de la Fase 1 (lo del Buildathon) — SIN BACKEND
La cadena es la base de datos; el navegador lee los eventos por RPC. Un solo riel: **modo contrato**
(el pagador ejecuta `pay()` desde su billetera). Tasa Bs/USDT **manual** (la fija el dueño), con
cotización que vence (~15 min).

| Rol | Conecta wallet | Qué hace |
|-----|----------------|----------|
| **Dueño** | Sí (una vez) | Registra el comercio on-chain y su dirección de cobro (firma) |
| **Cajero** | No (solo PIN) | Ingresa Bs → QR → espera la pantalla verde. Ve todo, no toca nada |
| **Cliente** | Sí | Escanea el QR → conecta → `approve` + `pay` → recibe comprobante |

Regla: la wallet se conecta **solo para firmar** (pagar o registrar). Para mirar/recibir, nunca.

## Stack
- **Contratos**: Solidity + Hardhat · red **Base Sepolia** (chainId **84532**)
- **Web**: Vite + React + TypeScript · **wagmi + viem + Reown AppKit** (MetaMask extensión + móvil)
- **QR**: es la URL de la página de pago
- **App móvil** (Flutter, con Reown AppKit): después del Buildathon

## Estructura (monorepo)
```
waliki/
  contracts/   # Hardhat: TestUSDT (ERC-20, 6 decimales, faucet) + WalikiRouter (registerMerchant, pay, evento)
  web/         # Vite + React: /caja (cobro→QR→verde) y /pay/:saleId (página de pago del cliente)
  packages/    # (futuro) ABI + tipos compartidos
```

## Plan del spike (tarea inicial: conexión MetaMask)
- **Paso 0 — Cuentas** ← EMPEZAR AQUÍ (ver `docs/PASO-0.md`)
- **Paso 1 — Repo**: scaffolding de `contracts/` (Hardhat) y `web/` (Vite)
- **Paso 2 — Contratos**: `TestUSDT` + `WalikiRouter`; test local → deploy a Base Sepolia
- **Paso 3 — Página de pago**: conectar, forzar red, `approve` + `pay`, mostrar hash → recibo
- **Paso 4 — Caja**: monto Bs → QR → `watchContractEvent` → pantalla verde
- **Paso 5 — Prueba real**: deploy a Vercel, pago desde un teléfono que escanea el QR

**Criterios de "hecho" del spike**: conectar en escritorio Y en teléfono desde el QR · red forzada a
Base Sepolia · `approve` + `pay` reales · verde disparado por el EVENTO (no por "salió la tx") · manejo
del rechazo del usuario y del cambio de cuenta.

## Estado
- [x] Nombre y plan (Google Doc v3)
- [x] Repo inicializado
- [ ] Paso 0 — cuentas
- [ ] Paso 2 — contratos
- [ ] Paso 3 — página de pago (spike MetaMask)
