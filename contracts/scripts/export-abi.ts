import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// Exports contract ABIs (and deployed addresses, when present) to
// web/src/contracts/waliki.json so the frontend imports them without
// duplicating sources. Runs standalone (ts-node) after compile/deploy.
const root = join(__dirname, "..");
const outDir = join(root, "..", "web", "src", "contracts");

function abiOf(name: string): unknown {
  const artifactPath = join(root, "artifacts", "contracts", `${name}.sol`, `${name}.json`);
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

mkdirSync(outDir, { recursive: true });

const out: Record<string, unknown> = {
  testUSDT: { abi: abiOf("TestUSDT") },
  walikiRouter: { abi: abiOf("WalikiRouter") },
};

const deploymentsPath = join(root, "deployments", "baseSepolia.json");
if (existsSync(deploymentsPath)) {
  out.baseSepolia = JSON.parse(readFileSync(deploymentsPath, "utf8"));
} else {
  console.warn("(aviso) deployments/baseSepolia.json aun no existe — se exportan solo los ABIs");
}

writeFileSync(join(outDir, "waliki.json"), JSON.stringify(out, null, 2) + "\n");
console.log(`ABIs exportados a ${join(outDir, "waliki.json")}`);
