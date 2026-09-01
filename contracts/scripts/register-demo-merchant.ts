import hre from "hardhat";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Registers the demo merchant (#1) on the deployed WalikiRouter, with the
// deployer wallet as owner and payout address. Idempotent: if a merchant
// already exists it only prints it.
async function main() {
  const deploymentsPath = join(__dirname, "..", "deployments", `${hre.network.name}.json`);
  const deployments = JSON.parse(readFileSync(deploymentsPath, "utf8"));
  const router = await hre.viem.getContractAt("WalikiRouter", deployments.walikiRouter);

  const count = await router.read.merchantCount();
  if (count > 0n) {
    const [owner, payout, name] = await router.read.merchants([1n]);
    console.log(`Ya hay ${count} comercio(s). #1: "${name}" · payout ${payout} · owner ${owner}`);
    return;
  }

  const [deployer] = await hre.viem.getWalletClients();
  const hash = await router.write.registerMerchant([
    deployer.account.address,
    "Tienda Demo CBBA",
  ]);
  const publicClient = await hre.viem.getPublicClient();
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`Comercio #1 "Tienda Demo CBBA" registrado`);
  console.log(`tx ${hash} · bloque ${receipt.blockNumber}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
