import { Link, useNavigate } from 'react-router-dom'

// Dev helper until the real cash register (Paso 4) generates sales:
// builds a fresh sale link exactly like the caja will.
function demoSaleUrl(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  const saleId = '0x' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
  const exp = Math.floor(Date.now() / 1000) + 15 * 60
  return `/pay/${saleId}?m=1&a=12500000&bs=175&r=14.00&exp=${exp}`
}

export default function Home() {
  const navigate = useNavigate()
  return (
    <>
      <h1>Cobra en USDT, sin custodios</h1>
      <p className="muted">
        El pago viaja directo de la billetera del cliente a la del comercio. Waliki solo lee la
        blockchain para confirmarlo — nunca toca el dinero.
      </p>

      <nav className="home-nav">
        <Link to="/caja">
          Abrir la caja <span className="chip">cajero · PIN</span>
        </Link>
        <Link to="/registro">
          Registrar mi comercio <span className="chip">dueño · 1 firma</span>
        </Link>
      </nav>

      <button className="btn btn-outline" onClick={() => navigate(demoSaleUrl())}>
        Ver una venta de ejemplo (Bs 175)
      </button>

      <p className="muted small trust">
        Ejemplo sobre el comercio #1 en Base Sepolia, con cotización que vence en 15 minutos —
        el mismo enlace que genera la caja.
      </p>
    </>
  )
}
