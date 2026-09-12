import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useAppKit, useAppKitAccount, useAppKitNetwork } from '@reown/appkit/react'
import { useReadContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { walikiRouterAbi } from '../contracts/waliki'
import { walikiNetwork } from '../lib/appkit'
import { network } from '../lib/network'

const CHAIN_ID = network.chainId
const ROUTER = network.router
const EXPLORER = network.explorer

function short(v: string): string {
  return v.length > 12 ? `${v.slice(0, 6)}…${v.slice(-4)}` : v
}

function errText(error: unknown): string {
  const anyErr = error as { shortMessage?: string; message?: string }
  const msg = anyErr?.shortMessage ?? anyErr?.message ?? String(error)
  if (/reject|denied/i.test(msg)) return 'Rechazaste la firma en tu billetera. Puedes intentarlo de nuevo.'
  return msg.slice(0, 160)
}

/// Self-service onboarding: the owner signs ONE transaction and the shop
/// exists on-chain with its payout address locked to the owner's wallet.
export default function Registro() {
  // The Flutter app hands the form over prefilled: /registro?n=<name>&p=<payout>
  const [search] = useSearchParams()
  const [name, setName] = useState(() => (search.get('n') ?? '').slice(0, 48))
  const [payout, setPayout] = useState(() => search.get('p') ?? '')

  const { open } = useAppKit()
  const { address, isConnected } = useAppKitAccount()
  const { chainId, switchNetwork } = useAppKitNetwork()
  const account = (address ?? undefined) as `0x${string}` | undefined
  const wrongNetwork = isConnected && Number(chainId) !== CHAIN_ID

  const regTx = useWriteContract()
  const rcpt = useWaitForTransactionReceipt({ hash: regTx.data, chainId: CHAIN_ID })
  const countRead = useReadContract({
    address: ROUTER,
    abi: walikiRouterAbi,
    functionName: 'merchantCount',
    chainId: CHAIN_ID,
    query: { enabled: rcpt.isSuccess },
  })

  const payoutAddr = payout.trim() || account || ''
  const payoutOk = /^0x[0-9a-fA-F]{40}$/.test(payoutAddr)
  const nameOk = name.trim().length >= 3
  const busy = regTx.isPending || Boolean(regTx.data && rcpt.isLoading)

  if (rcpt.isSuccess) {
    const id = countRead.data !== undefined ? String(countRead.data) : '…'
    return (
      <div className="card">
        <h1>¡Comercio registrado!</h1>
        <p>
          <strong>{name.trim()}</strong> ya existe en la blockchain como el comercio{' '}
          <strong>#{id}</strong>. Su dirección de cobro quedó <strong>candada</strong>: solo la
          billetera que acaba de firmar puede cambiarla — ningún empleado podrá desviar los pagos.
        </p>
        <div className="wallet-row">
          <span className="muted small">Cobra en</span>
          <span className="addr">{short(payoutAddr)}</span>
        </div>
        <div className="wallet-row">
          <span className="muted small">Transacción</span>
          <a href={`${EXPLORER}/tx/${regTx.data}`} target="_blank" rel="noreferrer">
            {short(regTx.data ?? '')} ↗
          </a>
        </div>
        <Link className="btn" style={{ textAlign: 'center', lineHeight: '28px' }} to={`/caja?m=${id}`}>
          Abrir la caja de este comercio
        </Link>
        <p className="muted small">
          La caja funciona al instante: cualquier cajero con el PIN puede cobrar, y cada QR paga
          directo a la dirección registrada.
        </p>
      </div>
    )
  }

  return (
    <div className="pay">
      <div className="card">
        <h1>Registra tu comercio</h1>
        <p className="muted">
          Alta autoservicio: <strong>una sola firma del dueño</strong> y tu negocio queda en la
          blockchain, con la dirección de cobro candada a tu billetera.
        </p>

        <label className="muted small" htmlFor="nombre">Nombre del comercio</label>
        <input
          id="nombre"
          className="field"
          placeholder="Como lo conocen tus clientes"
          value={name}
          maxLength={48}
          onChange={(e) => setName(e.target.value)}
        />

        <label className="muted small" htmlFor="payout">Dirección de cobro (opcional)</label>
        <input
          id="payout"
          className="field addr"
          placeholder={account ? `${short(account)} — tu billetera conectada` : '0x… (por defecto: tu billetera)'}
          value={payout}
          onChange={(e) => setPayout(e.target.value)}
        />
        {payout.trim() !== '' && !payoutOk && (
          <div className="error-box">Esa dirección no parece válida (debe ser 0x… de 42 caracteres).</div>
        )}

        {!isConnected ? (
          <button className="btn" onClick={() => open()}>
            Conectar la billetera del dueño
          </button>
        ) : wrongNetwork ? (
          <button className="btn" onClick={() => switchNetwork(walikiNetwork)}>
            Cambiar de red
          </button>
        ) : (
          <button
            className="btn"
            disabled={!nameOk || !payoutOk || busy}
            onClick={() => {
              regTx.reset()
              regTx.mutate({
                address: ROUTER,
                abi: walikiRouterAbi,
                functionName: 'registerMerchant',
                args: [payoutAddr as `0x${string}`, name.trim()],
                chainId: CHAIN_ID,
              })
            }}
          >
            {busy ? 'Registrando…' : 'Registrar on-chain — 1 firma'}
          </button>
        )}

        {regTx.error != null && <div className="error-box">{errText(regTx.error)}</div>}
      </div>

      <p className="muted small trust">
        La billetera del dueño se conecta solo para firmar el registro. Waliki nunca toca los
        fondos — el dinero de cada venta viaja directo del cliente a la dirección de cobro.
      </p>
    </div>
  )
}
