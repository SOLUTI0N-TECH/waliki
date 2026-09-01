import { Link } from 'react-router-dom'

export default function Home() {
  return (
    <>
      <h1>Waliki</h1>
      <p>
        Cobros en USDT sin custodia: el pago viaja directo del cliente a la
        wallet del comercio; la plataforma solo lee la cadena.
      </p>
      <nav className="home-nav">
        <Link to="/caja">Caja (cajero)</Link>
        <Link to="/pay/demo-001">Página de pago (demo)</Link>
      </nav>
    </>
  )
}
