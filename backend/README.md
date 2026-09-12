# Waliki — Backend de cobro por QR con liquidación en tUSDT

Intermediario entre la **Yesca API** (pasarela que emite el QR bancario en Bs) y la
**blockchain**: cuando la pasarela marca el QR como pagado, este backend transfiere
automáticamente una cantidad de tUSDT desde su propia wallet a la wallet de destino.

```
cliente → POST /qr ──────────► Yesca crea el QR (base64)
cliente → GET /qr/:id/status ─► Yesca dice "completed"
                              └► WalikiRouter.pay() → tUSDT a la wallet del comercio
                                 (emite PaymentReceived: la venta entra al historial)
```

**Por qué el router y no un `transfer` pelado.** El historial, los reportes y el CSV
de la app se construyen leyendo el evento `PaymentReceived` del contrato. Un
`transfer` de ERC-20 solo emite el `Transfer` del token, así que la venta cobrada
por QR quedaría invisible en el producto. Liquidando por `pay()` una venta en Bs
es indistinguible de una en USDT: mismo evento, mismo historial, misma prueba.

Si el `POST /qr` llega **sin** `merchantId` y `saleId`, el backend cae al `transfer`
directo de antes — compatible hacia atrás, pero esa venta no aparece en el historial.

> **Prototipo de buildathon.** Sin base de datos: los QR viven en un `Map` en memoria y se
> pierden al reiniciar el proceso. A diferencia del resto de Waliki, este backend **sí custodia
> fondos** (su wallet paga los tUSDT) — es una rampa de exploración, no el riel no-custodial.

## Requisitos

- Node 22+
- Una wallet de **testnet** con tUSDT (para pagar) y ETH de Base Sepolia (para el gas)
- Un token de la Yesca API

## Instalación

```bash
npm install
cp .env.example .env   # y completar los valores
npm run start:dev
```

Al arrancar, el log dice **qué wallet paga**, en qué `chainId` y con cuánto saldo. Si falta
una variable del `.env`, el server no arranca y te dice cuál.

### Variables de entorno

| Variable | Obligatoria | Qué es |
|---|---|---|
| `PORT` | no (3000) | Puerto del servidor |
| `YESCA_API_BASE_URL` | no | Base de la pasarela; por defecto `https://dmb.miventa.dev/api` |
| `YESCA_API_TOKEN` | **sí** | Token estático; viaja como `Authorization: Bearer <token>` |
| `RPC_URL` | **sí** | RPC de Base Sepolia. El endpoint de Alchemy va bien acá (ver abajo); público: `https://sepolia.base.org` |
| `WALLET_PRIVATE_KEY` | **sí** | Clave de la wallet que paga los tUSDT. **Solo testnet** |
| `TUSDT_CONTRACT_ADDRESS` | **sí** | Contrato ERC-20 del tUSDT. `.env.example` ya trae el de Base Sepolia |
| `TUSDT_DECIMALS` | no (6) | Fallback si `decimals()` del contrato falla |
| `WALIKI_ROUTER_ADDRESS` | no | WalikiRouter. Por defecto el desplegado en Base Sepolia; solo hay que tocarlo si se redespliega |

El `.env` está en el `.gitignore` de la raíz: nunca se commitea. El token y la clave privada
no se loguean ni aparecen en ninguna respuesta.

#### La red y el token: Base Sepolia

Todo corre en **Base Sepolia** (chainId 84532), donde ya viven los contratos del proyecto:
**no hay que desplegar nada**. El tUSDT es el que está commiteado en
`contracts/deployments/baseSepolia.json`:

```
0xc0934b34b2b1654ac5dc41b8a867e1227e03093d   (6 decimales, con faucet público)
```

Ese valor ya viene puesto en `.env.example`. Cambiará el día que se redesplieguen los contratos
actualizados; para el backend eso es editar una línea del `.env`, nada más.

**Financiar la wallet del backend** — necesita tUSDT para pagar y ETH de Base Sepolia para el gas.
La primera venta liquidada por el router gasta una transacción extra aprobándolo; después reusa
esa aprobación.

```bash
cd ../contracts
npm install
PREFUND_TO=0xWalletDelBackend npx hardhat run scripts/prefund-demo.ts --network baseSepolia
```

`prefund-demo.ts` transfiere **500 tUSDT** por dirección desde el deployer (que arranca con 10.000)
y resuelve la red sola; necesita `contracts/.env` con la `PRIVATE_KEY` del deployer. Alternativa sin
scripts: que la propia wallet llame al `faucet()` del token, que entrega 100 tUSDT con cooldown de
una hora. El ETH del gas sale del faucet de Base Sepolia.

#### Sobre el RPC de Alchemy

El plan gratis de Alchemy **limita `eth_getLogs` a 10 bloques**, y por eso la web y la app usan el
RPC público primero y Alchemy solo como respaldo (ver `CLAUDE.md`). **A este backend no le afecta**:
solo hace `eth_call`, `sendRawTransaction` y `getTransactionReceipt` — nunca escanea logs. Acá
Alchemy es la opción correcta, y conviene usarla por fiabilidad al firmar.

⚠️ Pero ese endpoint **no** debe copiarse como RPC primario de la app ni de la web: ahí rompe el
historial.

## Endpoints

### `POST /qr` — crear el cobro

| Campo | Requerido | Notas |
|---|---|---|
| `cryptoAmount` | **sí** | tUSDT a transferir cuando se pague el QR |
| `destinationWallet` | **sí** | Dirección `0x…` que recibe los tUSDT. Con `merchantId`, manda la dirección de cobro que el comercio registró on-chain |
| `merchantId` | no | Comercio en el contrato. Con `saleId`, liquida por `WalikiRouter.pay()` |
| `saleId` | no | `bytes32` (`0x` + 64 hex) elegido por quien llama. El contrato lo guarda y rechaza un segundo pago del mismo, que es lo que hace segura la reintentona |
| `amount` | no | Monto fiat (Bs), hasta 2 decimales. Si se omite → QR de monto abierto |
| `description` | no | Concepto del cobro |
| `additionalData` | no | Dato libre |
| `singleUse` | no | Por defecto `true` |
| `expiresAt` | no | ISO 8601. Por defecto, 15 minutos |

```bash
curl -X POST http://localhost:3000/qr \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 175.00,
    "description": "Venta mostrador",
    "cryptoAmount": 12.5,
    "destinationWallet": "0x3ca0e1d199ef95c2074248613a34a17b90702440"
  }'
```

Respuesta: lo que devuelve Yesca (`id`, `amount`, `status`, `expires_at`, `token` y `base64`
con la imagen del QR) más `cryptoAmount`, `destinationWallet` y `transferred: false`.

### `GET /qr/:id/status` — consultar y liquidar

```bash
curl http://localhost:3000/qr/<id>/status
```

Consulta el estado real en Yesca. Si es `completed` y todavía no se pagó la cripto, dispara la
liquidación y responde con `transferred: true` y el `txHash`.

⚠️ **`completed` no es lo mismo que cobrado.** `completed` dice que el banco recibió los
bolivianos; `transferred` dice que los tUSDT llegaron al comercio. La app pone la pantalla
verde con `transferred`, no con `completed`: entre uno y otro Waliki todavía debe la plata.

Antes de pagar se consulta `paidAmount(merchantId, saleId)` en el contrato. Es mejor
idempotencia que un hash de transacción: sobrevive a un reinicio y responde "¿esta venta
está pagada?" en vez de "¿esa transacción entró?". Si la transferencia falla,
responde igual con el estado del QR más `lastError`, y **reintenta en la próxima consulta**.

```json
{
  "id": "...", "status": "completed", "base64": "...",
  "cryptoAmount": 12.5,
  "destinationWallet": "0x3cA0e1...2440",
  "transferred": true,
  "txHash": "0xabc…"
}
```

Cada QR se paga **una sola vez**: el flag vive en el store y dos consultas simultáneas comparten
la misma transferencia.

### `GET /health`

```json
{ "status": "ok" }
```

## Probar la transferencia sin pagar un QR

Para aislar RPC, gas, saldo y decimales antes de tocar la pasarela:

```bash
npm run test:transfer -- 0xWalletDestino 1.5
```

Imprime la wallet pagadora, el saldo antes y después, y el enlace a Etherscan.

## Notas para Windows / PowerShell

En PowerShell, `curl` es un alias de `Invoke-WebRequest`, no el curl real. Usa `curl.exe`, o
mejor `Invoke-RestMethod`, que evita el infierno de comillas:

```powershell
$body = @{ cryptoAmount = 1.5; destinationWallet = '0x…'; amount = 175.00 } | ConvertTo-Json
$qr = Invoke-RestMethod -Method Post -Uri http://localhost:3000/qr -ContentType 'application/json' -Body $body
Invoke-RestMethod "http://localhost:3000/qr/$($qr.id)/status"
```

Para ver el QR generado:

```powershell
$b64 = $qr.base64 -replace '^data:image/\w+;base64,', ''
[IO.File]::WriteAllBytes("$env:TEMP\qr.png", [Convert]::FromBase64String($b64)); ii "$env:TEMP\qr.png"
```

## Comandos

| Comando | Qué hace |
|---|---|
| `npm run start:dev` | Servidor con recarga (⚠️ cada recarga vacía el store en memoria) |
| `npm run build` / `npm run start:prod` | Compilar y correr — lo recomendado para una demo |
| `npm test` | Tests unitarios |
| `npm run lint` | ESLint **con `--fix`**: escribe archivos, no usar en CI |
