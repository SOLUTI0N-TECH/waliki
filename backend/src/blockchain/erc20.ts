import type { BaseContract, ContractTransactionResponse } from 'ethers';

/// Minimal ERC20 surface: everything this backend calls, nothing else.
export const ERC20_ABI = [
  'function transfer(address to, uint256 value) returns (bool)',
  'function approve(address spender, uint256 value) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function balanceOf(address owner) view returns (uint256)',
] as const;

/// ethers types every Contract method as `any`. This is the typed slice we use.
export type Erc20 = BaseContract & {
  transfer(to: string, value: bigint): Promise<ContractTransactionResponse>;
  approve(
    spender: string,
    value: bigint,
  ): Promise<ContractTransactionResponse>;
  allowance(owner: string, spender: string): Promise<bigint>;
  decimals(): Promise<bigint>;
  balanceOf(owner: string): Promise<bigint>;
};
