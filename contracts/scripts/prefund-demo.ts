import hre from "hardhat";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { formatUnits, parseUnits } from "viem";

// Prefunds the demo-kit wallets with tUSDT from the deployer supply, so the
// live demo never depends on the faucet cooldown. Recipients come from the
// PREFUND_TO env var (comma-separated) or the default list below.
const DEFAULT_RECIPIENTS = [
  "0xbe5d6249ef221495db1469348e694f824bd7e22d", // teléfono #1
];
const AMOUNT = parseUnits("500", 6); // 500 tUSDT each

async function main() {
  const recipients = (process.env.PREFUND_TO?.split(",") ?? DEFAULT_RECIPIENTS)
    .map((a) => a.trim())
    .filter((a) => /^0x[0-9a-fA-F]{40}$/.test(a)) as `0x${string}`[];
  if (recipients.length === 0) {
    console.log("Sin direcciones validas (PREFUND_TO=0x..,0x..)");
    return;
  }

  const deploymentsPath = join(__dirname, "..", "deployments", `${hre.network.name}.json`);
  const deployments = JSON.parse(readFileSync(deploymentsPath, "utf8"));
  const usdt = await hre.viem.getContractAt("TestUSDT", deployments.testUSDT);
  const publicClient = await hre.viem.getPublicClient();

  for (const to of recipients) {
    const hash = await usdt.write.transfer([to, AMOUNT]);
    await publicClient.waitForTransactionReceipt({ hash });
    const balance = await usdt.read.balanceOf([to]);
    console.log(`${to} · +${formatUnits(AMOUNT, 6)} → saldo ${formatUnits(balance, 6)} tUSDT`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
