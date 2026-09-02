import hre from "hardhat";

// Diagnostic: dump recent on-chain activity for the demo contracts.
const ROUTER = "0xd98869ebf0231ce1a56b145cb83db0ab2b1d382a";
const USDT = "0xc0934b34b2b1654ac5dc41b8a867e1227e03093d";
const OWNER = "0x3ca0e1d199ef95c2074248613a34a17b90702440";

async function main() {
  const router = await hre.viem.getContractAt("WalikiRouter", ROUTER);
  const usdt = await hre.viem.getContractAt("TestUSDT", USDT);
  const publicClient = await hre.viem.getPublicClient();

  const latest = await publicClient.getBlockNumber();
  console.log(`Bloque actual: ${latest}`);
  // Public RPCs cap eth_getLogs at 10,000 blocks: scan the recent window only
  const FROM_BLOCK = latest > 9000n ? latest - 9000n : 0n;

  const pagos = await router.getEvents.PaymentReceived({}, { fromBlock: FROM_BLOCK, toBlock: "latest" });
  console.log(`\nPaymentReceived: ${pagos.length}`);
  for (const p of pagos) {
    console.log(`  bloque ${p.blockNumber} · payer ${p.args.payer} · monto ${p.args.amount} · sale ${String(p.args.saleId).slice(0, 10)}…`);
  }

  const transfers = await usdt.getEvents.Transfer({}, { fromBlock: FROM_BLOCK, toBlock: "latest" });
  console.log(`\nTransfer (tUSDT): ${transfers.length}`);
  for (const t of transfers) {
    console.log(`  bloque ${t.blockNumber} · ${t.args.from} -> ${t.args.to} · ${t.args.value}`);
  }

  const approvals = await usdt.getEvents.Approval({}, { fromBlock: FROM_BLOCK, toBlock: "latest" });
  console.log(`\nApproval (tUSDT): ${approvals.length}`);
  for (const a of approvals) {
    console.log(`  bloque ${a.blockNumber} · owner ${a.args.owner} · spender ${a.args.spender} · ${a.args.value}`);
  }

  console.log(`\ntotalSupply: ${await usdt.read.totalSupply()}`);
  console.log(`balance dueño: ${await usdt.read.balanceOf([OWNER])}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
