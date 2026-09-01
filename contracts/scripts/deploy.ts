import hre from "hardhat";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// Deploys TestUSDT + WalikiRouter and stores the addresses in
// deployments/<network>.json (this file IS committed: the team and the web
// app need the addresses).
async function main() {
  const [deployer] = await hre.viem.getWalletClients();
  console.log(`Red: ${hre.network.name} · deployer: ${deployer.account.address}`);

  const usdt = await hre.viem.deployContract("TestUSDT");
  console.log(`TestUSDT:     ${usdt.address}`);

  const router = await hre.viem.deployContract("WalikiRouter", [usdt.address]);
  console.log(`WalikiRouter: ${router.address}`);

  const salida = {
    network: hre.network.name,
    chainId: hre.network.config.chainId ?? null,
    deployer: deployer.account.address,
    testUSDT: usdt.address,
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
