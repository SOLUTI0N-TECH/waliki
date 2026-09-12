import type { BaseContract, ContractTransactionResponse } from 'ethers';

/// The slice of WalikiRouter this backend calls.
///
/// Settling through the router instead of a plain ERC-20 transfer is what
/// makes a QR sale visible to the rest of Waliki: `pay()` emits
/// `PaymentReceived`, which is the event the app's history, reports and CSV
/// are built on. A bare `transfer()` emits only the token's own `Transfer`,
/// so the sale would never show up anywhere.
export const ROUTER_ABI = [
  'function pay(uint256 merchantId, bytes32 saleId, uint256 amount)',
  'function paidAmount(uint256 merchantId, bytes32 saleId) view returns (uint256)',
  'function merchants(uint256 id) view returns (address owner, address payout, string name)',
  'function isCashier(uint256 merchantId, address cashier) view returns (bool)',
  'function cashierOf(bytes32 saleId) pure returns (address)',
] as const;

/// ethers types every Contract method as `any`. This is the typed slice we use.
export type WalikiRouter = BaseContract & {
  pay: {
    (
      merchantId: bigint,
      saleId: string,
      amount: bigint,
    ): Promise<ContractTransactionResponse>;
    /// Runs the call against the node without sending it. Used to turn a
    /// revert into a readable message BEFORE spending gas -- and, for a sale
    /// the customer already paid in bolivianos, before anyone can think the
    /// settlement is lost.
    staticCall(
      merchantId: bigint,
      saleId: string,
      amount: bigint,
    ): Promise<void>;
  };
  isCashier(merchantId: bigint, cashier: string): Promise<boolean>;
  paidAmount(merchantId: bigint, saleId: string): Promise<bigint>;
  merchants(
    id: bigint,
  ): Promise<
    [string, string, string] & { owner: string; payout: string; name: string }
  >;
};
