# Contratos v2 — Cajeros on-chain (Opción B)

> **Qué es esto**: la especificación de lo que se va a construir, decidida el **12/09/2026** tras el
> análisis de los contratos `TestUSDTNew.sol` / `WalikiRouterNew.sol`.
> Sustituye al documento comparativo anterior: aquí ya no hay tres caminos, hay uno.
> Todas las firmas y hashes están calculados con `ethers` y verificados contra el código real.

---

## 1. La decisión

**Opción B: los cajeros existen en la cadena —se agregan y se revocan— y cada venta queda atribuida
a uno, pero el cajero nunca firma ni paga gas.**

Se descarta el modelo de `createCharge` de `WalikiRouterNew.sol` porque obligaba a que cada caja
tuviera una llave con saldo de gas y a pagar una transacción antes de poder mostrar el QR. Una caja
sin gas es una caja que no cobra.

### Decisiones tomadas

| Decisión | Detalle |
|---|---|
| **Solo se redespliega el router** | El tUSDT sigue en `0xc0934b…093d`. Se conservan todos los saldos y el faucet |
| **`TestUSDTNew.sol` se elimina** | No aporta nada que el faucet no cubra ya |
| **La identidad del cajero la genera el dueño** | Y se la entrega con un código corto, como hoy |
| **La caja web atribuye al dueño** | No tiene identidad de cajero; los cobros web son del dueño |
| **La baja de un cajero es inmediata** | Sus QR sin pagar dejan de ser pagables |

### Lo que resuelve

1. **Cualquiera puede hacerse cajero de un comercio ajeno.** Hoy
   [cajero_setup.dart:43](app/lib/screens/cajero_setup.dart#L43) solo comprueba on-chain *que el
   comercio exista*; el PIN no se verifica contra nada y el que teclea el cajero pasa a ser el suyo.
   Los `merchantId` son correlativos y públicos.
2. **No se sabe cuánto recaudó cada empleado.** El evento no dice quién cobró.
3. **No se puede echar a un cajero.**

---

## 2. ⚠️ Antes que nada: un agujero que ya estaba abierto

> **Estado: arreglado el 12/09/2026**, antes que cualquier otra cosa de este documento. Las dos cajas
> comparan contra el monto pedido y la pantalla verde muestra el monto **recibido**.

Esto **no** necesitaba contratos nuevos ni esperar a nada. Era un bug explotable en producción, en
las dos cajas.

El monto del cobro viaja en la URL del QR (`…/pay/0x<saleId>?m=1&a=12500000`) y la página de pago lo
pasa tal cual a `pay()`. Las dos cajas dan la venta por buena así:

```dart
// app/lib/screens/cobrar.dart:261
if (paid > BigInt.zero && mounted && _phase == _Phase.qr) {   // no compara con el monto esperado
```
```ts
// web/src/pages/Caja.tsx:233
if (!activeSale || !paidRead.data || paidRead.data === 0n) return
```

**Cualquier cliente que edite `a=` en la barra del navegador paga 0,01 USDT y la caja se pone verde,
con sonido y vibración.** No es teórico: es cambiar un dígito.

El arreglo es una línea en cada caja —comparar contra el monto esperado— y **entra primero**, antes
que cualquier otra cosa de este documento. La pantalla verde debería además mostrar el monto
realmente recibido, no el que se pidió.

---

## 3. El contrato

Se reescribe [WalikiRouter.sol](contracts/contracts/WalikiRouter.sol) **en su sitio**, con el mismo
nombre de contrato y de archivo, para que Hardhat siga resolviendo por nombre y `export-abi` siga
funcionando. Se borran `TestUSDTNew.sol` y `WalikiRouterNew.sol`: dos contratos con el mismo nombre
en la carpeta son una trampa de despliegue.

### Se conserva idéntico

`registerMerchant` · `setPayoutAddress` · `merchants` · `merchantCount` · el evento
`MerchantRegistered` · y sobre todo el mapping **`paidAmount`**. Ese último importa mucho: mantiene
el selector `0x9378fd0b`, así que **el polling que pone verde la caja sigue funcionando sin tocar
una línea**.

### Se agrega

```solidity
mapping(uint256 => mapping(address => bool)) public isCashier;
mapping(uint256 => address) public pendingOwner;

event CashierAdded(uint256 indexed merchantId, address indexed cashier, string label);
event CashierRemoved(uint256 indexed merchantId, address indexed cashier);
event OwnershipTransferStarted(uint256 indexed merchantId, address indexed from, address indexed to);
event MerchantOwnershipTransferred(uint256 indexed merchantId, address indexed from, address indexed to);

function cashierOf(bytes32 saleId) external pure returns (address);                        // vease abajo
function addCashier(uint256 merchantId, address cashier, string calldata label) external;  // solo el dueno
function removeCashier(uint256 merchantId, address cashier) external;                      // solo el dueno
function transferMerchantOwnership(uint256 merchantId, address newOwner) external;         // paso 1
function acceptMerchantOwnership(uint256 merchantId) external;                             // paso 2
function cancelMerchantOwnershipTransfer(uint256 merchantId) external;                     // arrepentirse
```

Cuatro detalles que no son cosméticos:

- **El `label` va solo en el evento**, no en storage: cuesta cero gas permanente y evita que la
  pantalla del dueño solo pueda mostrar `0x1a2b…f0`. Nadie gestiona empleados por su dirección.
- **`registerMerchant` da de alta al dueño como cajero** (`isCashier[id][msg.sender] = true` +
  su `CashierAdded`). Así hay **un solo invariante** en `pay`, el traspaso de propiedad no invalida
  los QR del dueño anterior, y "mis cobros" del dueño es la misma consulta que la de cualquier otro.
- **El traspaso de propiedad es en dos pasos.** Es la única operación irreversible del contrato: un
  dedazo en una dirección válida-pero-ajena deja el comercio inutilizable para siempre. Con
  `pendingOwner` + `accept`, el destinatario tiene que firmar; y mientras no acepte, el dueño puede
  cancelar (si no, una oferta olvidada queda viva para siempre). Al aceptar, el dueño anterior
  **sigue de alta como cajero**: las ventas que tuviera en pantalla se pueden pagar, y el dueño nuevo
  lo da de baja después.
- **Al dueño no se le puede dar de baja como cajero.** Podría volver a darse de alta, así que no es
  irreversible — pero es un pie de banco sin ninguna ventaja.

### El cajero va dentro del `saleId`, y eso ahorra la mitad del trabajo

El `saleId` pasa a ser **`dirección del cajero (20 bytes) || 12 bytes aleatorios`** en vez de 32
bytes aleatorios. Como el contrato lo puede leer de ahí, **no hace falta pasarlo como parámetro ni
emitirlo en el evento**:

```solidity
function cashierOf(bytes32 saleId) public pure returns (address) {
    return address(bytes20(saleId));
}

function pay(uint256 merchantId, bytes32 saleId, uint256 amount) external {
    Merchant storage m = merchants[merchantId];
    require(m.owner != address(0), "Waliki: comercio inexistente");
    require(amount > 0, "Waliki: monto cero");
    require(paidAmount[merchantId][saleId] == 0, "Waliki: venta ya pagada");
    require(isCashier[merchantId][cashierOf(saleId)], "Waliki: cajero no autorizado");

    paidAmount[merchantId][saleId] = amount;
    token.safeTransferFrom(msg.sender, m.payout, amount);
    emit PaymentReceived(merchantId, saleId, msg.sender, amount, m.payout);
}
```

**`pay` y `PaymentReceived` no cambian de firma.** Eso importa más de lo que parece: la app lleva los
selectores y el `topic0` **escritos a mano** ([chain.dart:52-66](app/lib/chain.dart#L52-L66)), y
cambiarlos rompe el historial **en silencio** — sin excepción, sin error, solo una lista vacía y
montos que no significan nada. Deducir el cajero evita esa clase entera de fallo y deja
`web/src/pages/Pay.tsx` y `backend/src/blockchain/router.ts` intactos.

Es gratis además en tamaño: el `saleId` ya viajaba en la ruta del QR (`/pay/<saleId>`), así que **no
hace falta ningún parámetro `&c=` en la URL** y el QR no crece ni un carácter.

Y la atribución sigue siendo infalsificable: para culpar a otro cajero hay que cambiar el `saleId`, y
al cambiarlo estás pagando *otra* venta — la real sigue sin pagar, la caja nunca se pone verde y no
sale la mercancía. El `saleId` es un campo **indexado** del evento, así que la firma del cajero viaja
en el log sin ocupar un slot extra.

Lo único que se pierde frente a un `cashier` indexado es poder filtrar "mis cobros" en el RPC. No
cuesta nada: `eth_getLogs` se paga por rango de bloques, no por resultados, y la app ya lee todas las
ventas del comercio para armar el historial. El filtro por cajero se hace sobre esa misma lista.

### Firmas y hashes (verificados con `ethers`)

La app los necesita escritos a mano, así que aquí quedan. `contracts/test/waliki.test.ts` los afirma
contra el ABI compilado y `app/test/abi_test.dart` los recalcula con `web3dart`:

```
addCashier(uint256,address,string)              0x7961ffdc
removeCashier(uint256,address)                  0xed164620
isCashier(uint256,address)                      0x909cf575
cashierOf(bytes32)                              0xab515d2c
transferMerchantOwnership(uint256,address)      0x27146d6c
acceptMerchantOwnership(uint256)                0x54f83d86
cancelMerchantOwnershipTransfer(uint256)        0x2c77a635
pendingOwner(uint256)                           0x2b800e3b

pay(uint256,bytes32,uint256)                    0x3fcf3bfe   ← SIN CAMBIOS
paidAmount(uint256,bytes32)                     0x9378fd0b   ← SIN CAMBIOS
merchants(uint256)                              0x92c8823b   ← SIN CAMBIOS
merchantCount()                                 0x89105185   ← SIN CAMBIOS
registerMerchant(address,string)                0xa6c8a384   ← SIN CAMBIOS
setPayoutAddress(uint256,address)               0xdfefa227   ← SIN CAMBIOS

topic0 CashierAdded      0xe3343999af5709fd77744d1e75d1f52604472c522e29a62cde2e4e284cba55ec
topic0 CashierRemoved    0x54a78a91dea4745892ac90c82e3b81b4bbff52f2d6bececff18bff4fc2608fc7
topic0 PaymentReceived   0x0b385fcca75fcb7ea5db933cc6da0cc478e6a99e11d3596eedb8fde3897caff7  ← SIN CAMBIOS
topic0 MerchantRegistered 0x037fddc1b3113ac1da8bedf43384dd2830a0409fdb349f3cd03c79f9c0a09dbc  ← SIN CAMBIOS
```

⚠️ **El orden de los parámetros cambia el topic0.** Si se reordena el evento, estos valores dejan de
servir y hay que recalcularlos.

---

## 4. Vinculación de cajeros — el flujo nuevo

**Lo genera el dueño**, conservando exactamente la UX del código que el equipo ya diseñó:

1. El dueño pulsa **"Nueva caja"**, le pone nombre, y su app genera 10 bytes aleatorios, deriva de
   ahí la clave y la dirección del cajero, y firma `addCashier(merchantId, direccion, "Caja 1")` por
   WalletConnect — igual que ya firma `registerMerchant` ([wallet.dart](app/lib/wallet.dart)).
2. Cuando `isCashier` confirma —**no antes**, o el cajero teclearía el código y se le diría que no
   está autorizado— la app muestra el **código corto**: `7-K3NQ-7X2F-PM8T-QWRJ` (merchantId en
   decimal + la semilla en base32 Crockford, 16 caracteres).
3. El cajero teclea o pega ese código. Su app **deriva la misma identidad** y ya sabe a qué comercio
   pertenece, porque el id viaja en el código.
4. Confirma con un `eth_call` a `isCashier(merchantId, yo)` y entra.
5. El cajero elige su PIN, que a partir de ahora es **solo un bloqueo local de pantalla**: quien
   autentica es la cadena.

El alfabeto no lleva `I`, `L`, `O` ni `U`: las tres primeras se leen como `1`, `1` y `0` —y el
lector las acepta indistintamente—, y la `U` para que ningún código salga con una palabrota.
Diez bytes es el único largo que cuadra exacto en base32 (80 bits ÷ 5), así que no hay bits de
relleno que un decodificador laxo pueda aceptar de dos formas.

Esto elimina el código `<merchantId><pin>` actual y, con él, el agujero de que cualquiera se
autovincule. También elimina el subsistema de descubrimiento por logs que haría falta en el flujo
inverso: bastantes menos piezas móviles.

**El riesgo asumido**: la semilla queda en el historial de WhatsApp y quien la lea puede hacerse
pasar por esa caja. El daño máximo es emitir QR que pagan **a la cuenta del comercio** — exactamente
el mismo nivel de riesgo que el PIN compartido de hoy, pero ahora con autorización on-chain y
revocable en un toque.

### La identidad, en detalle

`web3dart 3.0.3` y `flutter_secure_storage 10.3.1` **ya estaban resueltos** como dependencias
transitivas de `reown_appkit`. Hay que **declararlos** en `pubspec.yaml` —el lint
`depend_on_referenced_packages` rompe `flutter analyze` al importarlos— pero con las mismas
restricciones que reown, así que `pubspec.lock` solo cambia dos líneas: cero descargas, cero
configuración nativa nueva. `pointycastle` no hace falta: `web3dart` reexporta `keccak256`,
`privateKeyBytesToPublic` y `publicKeyToAddress`.

Derivación: `keccak256("waliki-cashier-v1" ‖ semilla ‖ contador)`, avanzando el contador mientras el
resultado caiga fuera del orden de la curva (1 entre 2¹²⁸). El dominio con versión evita que la misma
semilla sirva para otra cosa por accidente y deja migrar el esquema sin ambigüedad.

- Se guarda **la semilla**, no la clave: es lo que permite volver a mostrar el código, y son 10 bytes
  contra 32. La dirección derivada va a `SharedPreferences` porque es pública y derivarla cuesta una
  multiplicación de curva elíptica en Dart puro (decenas de ms en un teléfono de gama baja).
- El **dueño** guarda además las semillas de las cajas que creó. Sin eso no puede volver a mostrarle
  el código a una caja existente, y re-vincular un teléfono perdido costaría dos firmas.
- La semilla se escribe **antes** de firmar `addCashier`. Si la app muere con la billetera abierta y
  la transacción entra igual, queda una dirección autorizada cuya semilla no existe en ningún lado:
  una caja fantasma que nadie puede usar y que solo se limpia con un `removeCashier`.
- `android:allowBackup="false"`, o el backup automático restaura las preferencias en un teléfono
  donde la clave del Keystore no existe y queda una caja que se cree vinculada y no tiene identidad.
  Y, aparte del manifiesto, el arranque comprueba que la semilla siga ahí antes de abrir el PIN.
- La UI dice **"identificador de caja"**, no "billetera": se parece a una y alguien le va a mandar
  USDT. Por eso se deriva una clave real y no 20 bytes al azar — lo que llegue ahí es recuperable.

**¿Por qué un keypair real si el cajero no firma?** Porque deja abierta la evolución natural: que el
cajero **firme el QR off-chain** (EIP-712 sobre monto y venta, gratis, sin gas) y el contrato haga
`ecrecover`. Eso mataría de raíz el bug del §2 —el monto quedaría firmado— sin romper la regla de que
el cajero no paga gas. Con 20 bytes aleatorios esa puerta queda cerrada y habría que re-vincular a
todos.

---

## 5. Qué se rompe y qué sobrevive

### `app/` — la pieza frágil: no usa ABIs, falla en silencio

| Qué | Estado |
|---|---|
| `paidAmount` y la pantalla verde | 🟢 Intacto — mismo selector |
| `merchants`, `merchantCount`, `registerMerchant`, `MerchantRegistered` | 🟢 Intactos |
| **Decodificación de `PaymentReceived`** | 🟢 Intacta — el evento no cambió |
| `saleId` y la caché del historial | 🔁 Cambian |
| Vinculación de cajero | 🔁 Reescrita |

Aquí está la ganancia de deducir el cajero del `saleId`. Con un evento nuevo,
[chain.dart:407](app/lib/chain.dart#L407) —que lee `payer` de `topics[3]` y `amount` de los primeros
32 bytes del `data`— habría seguido compilando y habría **pintado como monto un número de ~10⁴⁷**,
sin excepción y sin ABI que validara. Con el evento intacto, `Payment` gana `cashier` como un getter
derivado del `saleId`: no puede desalinearse, no ocupa nada en la caché, y las ventas guardadas antes
del cambio siguen respondiendo bien.

**Lo que sí hay que invalidar es la caché.** `_PaymentCache` usa claves `waliki.payments.$merchantId`
([chain.dart:188](app/lib/chain.dart#L188)) sin router ni versión. Al redesplegar, los `merchantId`
se reinician: un dispositivo con caché del comercio #1 viejo mezclaría ventas de dos contratos, con
un total inflado que nunca se autocorrige. La clave pasa a incluir la dirección del router, así que
el próximo redespliegue también queda cubierto sin acordarse.

**Y la sesión.** `Session` gana un número de esquema y, al arrancar con uno anterior, **borra rol,
`merchantId` y PIN**. Sin eso, un teléfono ya vinculado abre el PIN con un `merchantId` que ahora
apunta al comercio de otra persona. La tasa sobrevive: es la última cotización vista y sigue siendo
correcta.

### `web/`

**La llamada a `pay` no cambia.** Solo hay que generar el `saleId` con el prefijo del dueño —que ya
está en `merchantRead`— y regenerar el ABI. TypeScript avisa de todo lo demás en compilación: aquí no
hay fallos silenciosos.

Se añade **simulación antes de firmar** (`simulateContract`) para traducir el revert a *"este QR ya
no es válido, pide uno nuevo"*. Sin eso el cliente ve un error crudo de la billetera y desconfía.

### `backend/`

[router.ts](backend/src/blockchain/router.ts) **no cambia**: el `saleId` que manda la app ya trae el
prefijo del cajero, así que el DTO tampoco necesita campo nuevo y
[qr_service.dart](app/lib/qr_service.dart#L99) sigue enviando lo mismo.

⚠️ Hay un caso con dinero real: si el cajero se da de baja entre que se emite el QR bancario y se
liquida, `pay()` revierte **después de que el cliente ya pagó los bolivianos**. Decisión tomada: la
baja es inmediata, así que el backend **simula antes de enviar**, detecta ese revert concreto y
devuelve un error claro —*"la caja está dada de baja; vuelve a habilitarla para liberar esta venta"*—
mientras sigue reintentando. El dinero no se pierde: queda pendiente con un arreglo de un toque.

⚠️ `WALIKI_ROUTER_ADDRESS` pasa a ser **obligatoria**. Hoy es opcional con el router viejo
hardcodeado en [env.validation.ts:19](backend/src/config/env.validation.ts#L19) y el `.env` de
producción no la define: tras el redespliegue seguiría hablando con el contrato viejo sin quejarse.

### Migración

Router nuevo = dirección nueva = **los `merchantId` vuelven a 1**. Los dos comercios existentes
(#1 y "Diego Coffe") se re-registran y reciben ids nuevos; el historial viejo se queda donde está.
Hay que actualizar de forma atómica: `deployments/baseSepolia.json`, `web/src/contracts/waliki.ts`,
`config.dart` (`router` y `deployBlock`) y el `.env` del backend. Es fácil dejarse uno y depurarlo a
ciegas, porque la app no falla: devuelve vacío.

`deploy.ts` **ya sabe reutilizar el token existente** vía `TOKEN_ADDRESS`, así que no hay que tocarlo.

---

## 6. Tests

El proyecto no tenía **ningún** test que cubriera la frontera app↔contrato, que es justo la que se
rompe en silencio. Además de adaptar los 7 de Hardhat y cubrir cajeros (alta y baja solo por el
dueño, aislamiento entre comercios, cajero revocado que ya no cobra, ciclo alta→baja→alta, el
`saleId` que no corresponde a ningún cajero, el traspaso en dos pasos), entran dos pruebas de
regresión que son la red de seguridad de todo lo demás:

- **En Hardhat**: afirmar los **selectores y topic0 literales contra el ABI compilado**. Si alguien
  reordena un parámetro, la firma desaparece del ABI y revienta el CI en vez de reventar la app en el
  demo.
- **En Dart**: `web3dart` exporta `keccakAscii`, así que `app/test/abi_test.dart` recalcula los mismos
  hashes y los compara con las constantes de `chain.dart` y `wallet.dart` — y compara la calldata
  contra *golden* generada con `ethers`. Mata toda la clase de bugs "hex escrito a mano".

Y en la app, dos que protegen cosas que fallarían en silencio: los **vectores de derivación** de la
identidad (si el esquema cambia sin querer, todos los cajeros ya vinculados derivan otra dirección y
ninguno queda autorizado) y el **offset `0x60`** de `addCashier`, que si se copia mal **no revierte**:
la transacción entra y emite la etiqueta corrupta.

---

## 7. Orden de trabajo

| # | Trabajo | Nota |
|---|---|---|
| 0 | **Arreglar el sub-pago** en las dos cajas | Una línea cada una. No espera a nada |
| 1 | Reescribir el contrato + borrar los dos `*New.sol` + tests | |
| 2 | Desplegar reutilizando el token, verificar en Basescan, regenerar ABIs | |
| 3 | `web/` y `backend/` | Cambios mínimos: el ABI no se movió |
| 4 | `app/`: identidad, caché, sesión, pantallas de cajeros | La más grande |
| 5 | Re-registrar los comercios y probar el circuito completo | |
| 6 | `CLAUDE.md`, `README.md`, `docs/HANDOFF.md` | La tabla de roles ya no es cierta |

---

## 8. Lo que la Opción B no resuelve

Queda anotado a propósito, para que nadie lo descubra por sorpresa:

- **El monto lo sigue poniendo el pagador.** El arreglo del §2 lo detecta en la caja, pero no lo
  impide en la cadena. La solución de fondo es que el cajero firme el QR (EIP-712) — evolución
  natural, no ahora.
- **Dar de baja a un cajero invalida sus QR en vuelo.** Es la decisión tomada, y es lo que se quiere
  en el 99% de los casos: acabo de despedir a alguien y no quiero que siga emitiendo cobros.
- **El gas del dueño**: registrar el comercio y agregar cajeros sigue exigiendo ETH en su billetera.
  Para un comerciante que acaba de instalar la app, eso es un muro.
- **`merchantsOf()` enumera 1..merchantCount** — no escala a miles de comercios.
- **`backend/` sigue sin autenticación** en `POST /qr`.
- **El handoff del código por WhatsApp** no detecta una sustitución completa. Con cámara
  (`mobile_scanner` es plugin + permiso, sin código nativo) el flujo quedaría cerrado.

---

## 9. Preguntas abiertas

1. **¿En qué red se publica?** Una app en las tiendas operando con dinero de mentira es difícil de
   sostener. Si es Base mainnet con USDT real, se reabre [docs/MAINNET.md](docs/MAINNET.md) y hace
   falta decidir sobre auditoría.
2. **¿Quién paga el gas del alta** cuando un comerciante crea su negocio desde la app?
3. **¿Cómo se custodia la llave del dueño?** Hoy es su MetaMask por WalletConnect. ¿Seguimos
   exigiendo que ya tenga wallet, o Waliki genera una (Fase 2, "Modo Fácil")?
4. **¿`backend/` se arregla o se queda como prototipo?** Si va a producción con la app, su falta de
   autenticación es bloqueante.
5. **¿Quién valida las políticas de Apple y Google** para apps con cripto, antes de invertir el
   desarrollo?
6. **¿Estos contratos los mantiene Daniel?** `CLAUDE.md` dice que el frente de permisos/roles es
   suyo y que hay que coordinar antes de tocar `WalikiRouter`.
7. **¿Se verifican en Basescan?** Los actuales no lo están.
8. **¿Cómo se coordina el corte?** Con la app publicada, los usuarios con la versión vieja quedan
   rotos hasta que actualicen.
