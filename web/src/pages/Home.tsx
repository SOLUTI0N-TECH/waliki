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
      <h1>Waliki</h1>
      <p>
        Cobros en USDT sin custodia: el pago viaja directo del cliente a la wallet del comercio;
        la plataforma solo lee la cadena.
      </p>
      <nav className="home-nav">
        <button className="btn" onClick={() => navigate(demoSaleUrl())}>
          Generar venta de prueba (Bs 175)
        </button>
        <Link to="/caja">Caja (cajero)</Link>
        <Link to="/registro">Registrar mi comercio (dueño)</Link>
      </nav>
      <p className="muted small">
        La venta de prueba apunta al comercio #1 ("Tienda Demo CBBA") en Base Sepolia, con
        cotización que vence en 15 minutos — el mismo enlace que generará la caja.
      </p>
    </>
  )
}
