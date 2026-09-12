import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { BlockchainService } from '../src/blockchain/blockchain.service';

/// Diagnostics: move tUSDT without going through the Yesca API, to prove RPC,
/// gas, balance, decimals and signing all work.
///
///   npm run test:transfer -- 0xDestino 1.5
async function main() {
  const [to, rawAmount] = process.argv.slice(2);
  if (!to || !rawAmount) {
    console.error('Uso: npm run test:transfer -- <0xDireccionDestino> <monto>');
    process.exitCode = 1;
    return;
  }

  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });
  const blockchain = app.get(BlockchainService);

  console.log(`Wallet pagadora: ${blockchain.address}`);
  console.log(`Saldo antes:     ${await blockchain.balance()} tUSDT`);

  const { txHash } = await blockchain.transferTUSDT(to, Number(rawAmount));
  console.log(`Listo -> https://sepolia.basescan.org/tx/${txHash}`);
  console.log(`Saldo después:   ${await blockchain.balance()} tUSDT`);

  await app.close();
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
