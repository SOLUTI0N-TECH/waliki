import { useParams } from 'react-router-dom'

export default function Pay() {
  const { saleId } = useParams()
  return (
    <>
      <h1>Página de pago</h1>
      <p>
        Venta: <code>{saleId}</code>
      </p>
      <p>
        Aquí el cliente conecta su wallet, la red se fuerza a Base Sepolia y se
        ejecuta <code>approve</code> + <code>pay</code>. Se construye en el{' '}
        <strong>Paso 3</strong>.
      </p>
    </>
  )
}
