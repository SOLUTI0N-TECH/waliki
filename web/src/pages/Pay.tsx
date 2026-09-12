import { useEffect, useMemo, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { useAppKit, useAppKitAccount, useAppKitNetwork } from '@reown/appkit/react'
import { useReadContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { formatUnits } from 'viem'
import { testUSDTAbi, walikiRouterAbi } from '../contracts/waliki'
import { walikiNetwork } from '../lib/appkit'
import { network } from '../lib/network'

const CHAIN_ID = network.chainId
const ROUTER = network.router
const USDT = network.token
const EXPLORER = network.explorer
const SYMBOL = network.tokenSymbol
const DECIMALS = network.tokenDecimals
const ZERO_ADDR = '0x0000000000000000000000000000000000000000' as `0x${string}`
const ZERO_SALE = ('0x' + '0'.repeat(64)) as `0x${string}`

const nf = new Intl.NumberFormat('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

function fmtUsdt(units: bigint): string {
  return nf.format(Number(formatUnits(units, DECIMALS)))
}

function short(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

function isRejected(error: unknown): boolean {
  const msg = error instanceof Error ? `${error.name} ${error.message}` : String(error)
  return /reject|denied|denegad|rechaz/i.test(msg)
}

function shortError(error: unknown): string {
  if (!error) return ''
  if (isRejected(error)) return 'Rechazaste la firma en tu billetera. Puedes intentarlo de nuevo.'
  const anyErr = error as { shortMessage?: string; message?: string }
  const msg = anyErr.shortMessage ?? anyErr.message ?? String(error)
  if (/cooldown/i.test(msg)) return 'El faucet está en cooldown: se puede reclamar 1 vez por hora.'
  return msg.slice(0, 160)
}

export default function Pay() {
  const { saleId } = useParams()
  const [search] = useSearchParams()

  // The QR carries the whole sale: /pay/:saleId?m=1&a=12500000&bs=175&r=14.00&exp=173...
  const sale = useMemo(() => {
    const id = saleId && /^0x[0-9a-fA-F]{64}$/.test(saleId) ? (saleId as `0x${string}`) : null
    const m = search.get('m')
    const a = search.get('a')
    const merchantId = m && /^\d+$/.test(m) ? BigInt(m) : null
    const amount = a && /^\d+$/.test(a) ? BigInt(a) : null
    const exp = Number(search.get('exp') ?? '0') || null
    return {
      id,
      merchantId,
      amount,
      bs: search.get('bs'),
      rate: search.get('r'),
      exp,
      valid: Boolean(id && merchantId && merchantId > 0n && amount && amount > 0n),
    }
  }, [saleId, search])

  // 1-second clock for the quote countdown
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000))
  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000)
    return () => clearInterval(t)
  }, [])
  const expired = sale.exp ? now >= sale.exp : false
  const remaining = sale.exp ? Math.max(0, sale.exp - now) : null

  const { open } = useAppKit()
  const { address, isConnected } = useAppKitAccount()
  const { chainId, switchNetwork } = useAppKitNetwork()
  const account = (address ?? undefined) as `0x${string}` | undefined
  const wrongNetwork = isConnected && Number(chainId) !== CHAIN_ID

  const merchantRead = useReadContract({
    address: ROUTER,
    abi: walikiRouterAbi,
    functionName: 'merchants',
    args: [sale.merchantId ?? 0n],
    chainId: CHAIN_ID,
    query: { enabled: sale.valid },
  })
  const merchantName = merchantRead.data ? merchantRead.data[2] : null
  const merchantExists = merchantRead.data ? merchantRead.data[0] !== ZERO_ADDR : true

  // Polled so the page also flips to "paid" if someone else pays this sale
  const paidRead = useReadContract({
    address: ROUTER,
    abi: walikiRouterAbi,
    functionName: 'paidAmount',
    args: [sale.merchantId ?? 0n, sale.id ?? ZERO_SALE],
    chainId: CHAIN_ID,
    query: { enabled: sale.valid, refetchInterval: 4000 },
  })

  const balanceRead = useReadContract({
    address: USDT,
    abi: testUSDTAbi,
    functionName: 'balanceOf',
    args: [account ?? ZERO_ADDR],
    chainId: CHAIN_ID,
    query: { enabled: Boolean(account) },
  })
  const allowanceRead = useReadContract({
    address: USDT,
    abi: testUSDTAbi,
    functionName: 'allowance',
    args: [account ?? ZERO_ADDR, ROUTER],
    chainId: CHAIN_ID,
    query: { enabled: Boolean(account) },
  })

  const faucetTx = useWriteContract()
  const approveTx = useWriteContract()
  const payTx = useWriteContract()

  const faucetRcpt = useWaitForTransactionReceipt({ hash: faucetTx.data, chainId: CHAIN_ID })
  const approveRcpt = useWaitForTransactionReceipt({ hash: approveTx.data, chainId: CHAIN_ID })
  const payRcpt = useWaitForTransactionReceipt({ hash: payTx.data, chainId: CHAIN_ID })

  const refetchBalance = balanceRead.refetch
  const refetchAllowance = allowanceRead.refetch
  const refetchPaid = paidRead.refetch
  useEffect(() => {
    if (faucetRcpt.isSuccess) void refetchBalance()
  }, [faucetRcpt.isSuccess, refetchBalance])
  useEffect(() => {
    if (approveRcpt.isSuccess) void refetchAllowance()
  }, [approveRcpt.isSuccess, refetchAllowance])
  useEffect(() => {
    if (payRcpt.isSuccess) {
      void refetchPaid()
      void refetchBalance()
    }
  }, [payRcpt.isSuccess, refetchPaid, refetchBalance])

  if (!sale.valid) {
    return (
      <div className="card">
        <h1>Enlace de pago incompleto</h1>
        <p className="muted">
          Este enlace no trae los datos de la venta. Escanea de nuevo el QR de la caja — el QR
          incluye el monto, el comercio y la cotización.
        </p>
        <Link to="/">Volver al inicio</Link>
      </div>
    )
  }

  const amount = sale.amount ?? 0n
  const balance = balanceRead.data
  const allowance = allowanceRead.data
  const paidOnChain = (paidRead.data ?? 0n) > 0n
  const payReverted = payRcpt.isError || payRcpt.data?.status === 'reverted'
  // Green by two roads: the receipt, or the 4s chain poll confirming the sale
  // is paid after this browser sent the payment — never an eternal "Pagando…".
  const justPaid =
    (payRcpt.isSuccess && payRcpt.data?.status === 'success') ||
    (paidOnChain && Boolean(payTx.data) && !payReverted)

  const needsFaucet = isConnected && !wrongNetwork && balance !== undefined && balance < amount
  const needsApprove = allowance !== undefined && allowance < amount
  const busyFaucet = faucetTx.isPending || Boolean(faucetTx.data && faucetRcpt.isLoading)
  const busyApprove = approveTx.isPending || Boolean(approveTx.data && approveRcpt.isLoading)
  const busyPay = payTx.isPending || Boolean(payTx.data && payRcpt.isLoading)
  const lastError = payTx.error ?? approveTx.error ?? faucetTx.error

  // Success screen: this browser just paid the sale
  if (justPaid) {
    return (
      <div className="success-panel">
        <div className="success-check">✓</div>
        <h1>¡Pago enviado!</h1>
        <div className="success-amount">
          {sale.bs ? `Bs ${nf.format(Number(sale.bs))}` : `${fmtUsdt(amount)} ${SYMBOL}`}
        </div>
        <div className="success-sub">
          {fmtUsdt(amount)} {SYMBOL} · {merchantName ?? `comercio #${sale.merchantId}`}
        </div>
        <div className="receipt">
          <div className="row">
            <span>Transacción</span>
            <a href={`${EXPLORER}/tx/${payTx.data}`} target="_blank" rel="noreferrer">
              {short(payTx.data ?? '')} ↗
            </a>
          </div>
          <div className="row">
            <span>Bloque</span>
            <span>{payRcpt.data ? String(payRcpt.data.blockNumber) : '…'}</span>
          </div>
          <div className="row">
            <span>Venta</span>
            <span className="addr">{short(sale.id ?? '')}</span>
          </div>
        </div>
        <p className="muted">
          La caja del comercio se pondrá verde sola: la verificación la hace la blockchain, no
          esta pantalla.
        </p>
      </div>
    )
  }

  // Already paid (by someone else) before this browser tried
  if (paidOnChain) {
    return (
      <div className="card">
        <h1>Esta venta ya está pagada</h1>
        <p>
          La venta <span className="addr">{short(sale.id ?? '')}</span> ya registra un pago de{' '}
          <strong>{fmtUsdt(paidRead.data ?? 0n)} {SYMBOL}</strong> en la blockchain.
        </p>
        <p className="muted">Si necesitas hacer otro cobro, pide al cajero un QR nuevo.</p>
      </div>
    )
  }

  return (
    <div className="pay">
      <div className="card">
        <div className="merchant-row">
          <div>
            <div className="muted small">Pagas a</div>
            <div className="merchant-name">
              {merchantName ?? `Comercio #${String(sale.merchantId)}`}
            </div>
          </div>
          <span className="chip chip-green">verificado on-chain</span>
        </div>
        {!merchantExists && (
          <div className="error-box">Este comercio no existe en el contrato. Revisa el enlace.</div>
        )}

        <div className="amount-block">
          {sale.bs && <div className="amount-bs">Bs {nf.format(Number(sale.bs))}</div>}
          <div className="amount-usdt">{fmtUsdt(amount)} {SYMBOL}</div>
          <div className="chips">
            {sale.rate && <span className="chip">Tasa Bs {sale.rate} = 1 USDT</span>}
            {remaining !== null && !expired && (
              <span className="chip chip-amber">
                vence en {Math.floor(remaining / 60)}:{String(remaining % 60).padStart(2, '0')}
              </span>
            )}
            {expired && <span className="chip chip-red">cotización vencida</span>}
          </div>
        </div>

        {isConnected && account && (
          <div className="wallet-row">
            <span className="addr">{short(account)}</span>
            <span className="muted">
              saldo: {balance !== undefined ? `${fmtUsdt(balance)} ${SYMBOL}` : '…'}
            </span>
          </div>
        )}

        {expired ? (
          <button className="btn" disabled>
            Cotización vencida — pide un QR nuevo en la caja
          </button>
        ) : !isConnected ? (
          <button className="btn" onClick={() => open()}>
            Conectar billetera
          </button>
        ) : wrongNetwork ? (
          <button className="btn" onClick={() => switchNetwork(walikiNetwork)}>
            Cambiar a {walikiNetwork.name}
          </button>
        ) : needsApprove ? (
          <button className="btn" disabled={busyApprove || needsFaucet} onClick={() => {
            approveTx.reset()
            approveTx.mutate({
              address: USDT,
              abi: testUSDTAbi,
              functionName: 'approve',
              args: [ROUTER, amount],
              chainId: CHAIN_ID,
            })
          }}>
            {busyApprove ? 'Aprobando…' : `Aprobar ${fmtUsdt(amount)} ${SYMBOL} · firma 1 de 2`}
          </button>
        ) : (
          <button className="btn" disabled={busyPay || needsFaucet} onClick={() => {
            payTx.reset()
            payTx.mutate({
              address: ROUTER,
              abi: walikiRouterAbi,
              functionName: 'pay',
              args: [sale.merchantId ?? 0n, sale.id ?? ZERO_SALE, amount],
              chainId: CHAIN_ID,
            })
          }}>
            {busyPay ? 'Pagando…' : `Pagar ${fmtUsdt(amount)} ${SYMBOL} · firma 2 de 2`}
          </button>
        )}

        {network.isTestnet && needsFaucet && !expired && (
          <button className="btn btn-outline" disabled={busyFaucet} onClick={() => {
            faucetTx.reset()
            faucetTx.mutate({
              address: USDT,
              abi: testUSDTAbi,
              functionName: 'faucet',
              chainId: CHAIN_ID,
            })
          }}>
            {busyFaucet ? 'Reclamando…' : `Te faltan ${SYMBOL} — obtener 100`}
          </button>
        )}

        {isConnected && !wrongNetwork && !expired && (
          <div className="steps muted small">
            El pago se hace en 2 firmas: primero <strong>aprobar</strong>, luego{' '}
            <strong>pagar</strong>. El gas lo cubre {walikiNetwork.nativeCurrency.symbol} de tu billetera.
          </div>
        )}

        {lastError != null && <div className="error-box">{shortError(lastError)}</div>}

        {(faucetTx.isPending || approveTx.isPending || payTx.isPending) && (
          <div className="muted small center">
            ¿No aparece la firma? Abre la app de MetaMask en este teléfono y vuelve aquí.
          </div>
        )}
        {(Boolean(faucetTx.data) && faucetRcpt.isLoading) ||
        (Boolean(approveTx.data) && approveRcpt.isLoading) ||
        (Boolean(payTx.data) && payRcpt.isLoading) ? (
          <div className="muted small center">Confirmando en la blockchain…</div>
        ) : null}
      </div>

      <p className="muted small trust">
        Los {SYMBOL} viajan directo de tu billetera a la del comercio. Waliki nunca toca los fondos —
        solo lee la blockchain.
      </p>
    </div>
  )
}
