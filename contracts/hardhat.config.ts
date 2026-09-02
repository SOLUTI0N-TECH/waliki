import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "dotenv/config";

// RPC y clave del deployer salen de contracts/.env (nunca se commitea; ver .env.example)
const { RPC_URL, PRIVATE_KEY, BASESCAN_API_KEY } = process.env;

// MetaMask exports keys without the 0x prefix; accept both forms
const deployerKey = PRIVATE_KEY
  ? PRIVATE_KEY.startsWith("0x")
    ? PRIVATE_KEY
    : `0x${PRIVATE_KEY}`
  : undefined;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  networks: {
    baseSepolia: {
      url: RPC_URL || "https://sepolia.base.org", // empty string in .env must fall back too
      chainId: 84532,
      accounts: deployerKey ? [deployerKey] : [],
    },
    // Mainnets — deploy with TOKEN_ADDRESS set to the real stablecoin
    base: {
      url: process.env.BASE_RPC_URL || "https://mainnet.base.org",
      chainId: 8453,
      accounts: deployerKey ? [deployerKey] : [],
    },
    bsc: {
      url: process.env.BSC_RPC_URL || "https://bsc-dataseed.binance.org",
      chainId: 56,
      accounts: deployerKey ? [deployerKey] : [],
    },
  },
  etherscan: {
    apiKey: BASESCAN_API_KEY ?? "",
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },
};

export default config;
