import { Route, Routes } from 'react-router-dom'
import Caja from './pages/Caja'
import Home from './pages/Home'
import Pay from './pages/Pay'

export default function App() {
  return (
    <>
      <div className="testnet-banner">
        MODO PRUEBA · Base Sepolia — los fondos NO son reales
      </div>
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/caja" element={<Caja />} />
          <Route path="/pay/:saleId" element={<Pay />} />
        </Routes>
      </main>
    </>
  )
}
