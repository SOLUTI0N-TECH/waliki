import type { YescaIntent } from '../yesca/yesca.types';

export interface CryptoState {
  transferred: boolean;
  txHash?: string;
  /// Hash of a transfer that was sent but could not be confirmed. Checked
  /// before retrying, so a timed-out transaction is never paid twice.
  pendingTxHash?: string;
  lastError?: string;
}

export interface QrRecord {
  intent: YescaIntent;
  cryptoAmount: number;
  destinationWallet: string;
  /// Present when the sale settles through WalikiRouter instead of a plain
  /// transfer. Both travel together or not at all.
  merchantId?: number;
  saleId?: string;
  crypto: CryptoState;
}

/// What both endpoints answer: the gateway's QR plus our crypto side.
export interface QrResponse extends YescaIntent {
  cryptoAmount: number;
  destinationWallet: string;
  merchantId?: number;
  saleId?: string;
  transferred: boolean;
  txHash?: string;
  lastError?: string;
}
