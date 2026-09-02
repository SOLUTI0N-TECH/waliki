import hre from "hardhat";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// Deploys TestUSDT + WalikiRouter and stores the addresses in
// deployments/<network>.json (this file IS committed: the team and the web
// app need the addresses).
async function main() {
  const [deployer] = await hre.viem.getWalletClients();
  console.log(`Red: ${hre.network.name} · deployer: ${deployer.account.address}`);

  // Mainnet: point the router at a real stablecoin (TOKEN_ADDRESS) instead of
  // deploying the demo token. Testnet: deploy TestUSDT with its faucet.
  const existingToken = process.env.TOKEN_ADDRESS?.trim();
  let tokenAddress: `0x${string}`;

  if (existingToken) {
    if (!/^0x[0-9a-fA-F]{40}$/.test(existingToken)) {
      throw new Error(`TOKEN_ADDRESS invalida: ${existingToken}`);
    }
    tokenAddress = existingToken as `0x${string}`;
    const token = await hre.viem.getContractAt("TestUSDT", tokenAddress);
    const [symbol, decimals] = await Promise.all([
      token.read.symbol(),
      token.read.decimals(),
    ]);
    console.log(`Token existente: ${symbol} (${decimals} decimales) en ${tokenAddress}`);
    console.log(`  -> configura VITE_TOKEN_SYMBOL=${symbol} y VITE_TOKEN_DECIMALS=${decimals}`);
  } else {
    const usdt = await hre.viem.deployContract("TestUSDT");
    tokenAddress = usdt.address;
    console.log(`TestUSDT:     ${usdt.address}`);
  }

  const router = await hre.viem.deployContract("WalikiRouter", [tokenAddress]);
  console.log(`WalikiRouter: ${router.address}`);

  const salida = {
    network: hre.network.name,
    chainId: hre.network.config.chainId ?? null,
    deployer: deployer.account.address,
    testUSDT: tokenAddress,
    walikiRouter: router.address,
    deployedAt: new Date().toISOString(),
  };
  const dir = join(__dirname, "..", "deployments");
  mkdirSync(dir, { recursive: true });
  const archivo = join(dir, `${hre.network.name}.json`);
  writeFileSync(archivo, JSON.stringify(salida, null, 2) + "\n");
  console.log(`Direcciones guardadas en ${archivo}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
