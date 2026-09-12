import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  Contract,
  JsonRpcProvider,
  Wallet,
  formatUnits,
  getAddress,
  isAddress,
  parseUnits,
} from 'ethers';
import { ERC20_ABI, type Erc20 } from './erc20';
import { ROUTER_ABI, type WalikiRouter } from './router';

const WAIT_CONFIRMATIONS = 1;
const MAX_UINT256 = (1n << 256n) - 1n;
const WAIT_TIMEOUT_MS = 120_000;

function reason(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/// Owns the backend's own wallet and moves tUSDT out of it. The private key
/// lives here and never leaves: no getter, no log, no response ever exposes it.
@Injectable()
export class BlockchainService {
  private readonly logger = new Logger(BlockchainService.name);
  private readonly provider: JsonRpcProvider;
  private readonly wallet: Wallet;
  private readonly token: Erc20;
  private readonly router: WalikiRouter;
  private readonly routerAddress: string;
  private readonly fallbackDecimals: number;
  private decimals?: number;
  /// Transfers are serialized: two concurrent sends from the same wallet would
  /// take the same nonce and one of them would be rejected by the node.
  private queue: Promise<unknown> = Promise.resolve();

  constructor(config: ConfigService) {
    this.fallbackDecimals = config.getOrThrow<number>('TUSDT_DECIMALS');
    // staticNetwork: resolve the chain once instead of on every call — public
    // Base Sepolia RPCs rate-limit hard.
    this.provider = new JsonRpcProvider(
      config.getOrThrow<string>('RPC_URL'),
      undefined,
      {
        staticNetwork: true,
      },
    );
    this.wallet = new Wallet(
      config.getOrThrow<string>('WALLET_PRIVATE_KEY'),
      this.provider,
    );
    this.token = new Contract(
      config.getOrThrow<string>('TUSDT_CONTRACT_ADDRESS'),
      ERC20_ABI,
      this.wallet,
    ) as unknown as Erc20;
    this.routerAddress = getAddress(
      config.getOrThrow<string>('WALIKI_ROUTER_ADDRESS'),
    );
    this.router = new Contract(
      this.routerAddress,
      ROUTER_ABI,
      this.wallet,
    ) as unknown as WalikiRouter;
  }

  /// Public address of the paying wallet — safe to log, unlike its key.
  get address(): string {
    return this.wallet.address;
  }

  /// Sends `amount` tUSDT to `to` and waits for the receipt. `onSent` fires as
  /// soon as the transaction has a hash, before it is confirmed.
  async transferTUSDT(
    to: string,
    amount: number,
    onSent?: (txHash: string) => void,
  ): Promise<{ txHash: string }> {
    if (!isAddress(to)) {
      // isAddress narrows `to` to never here, hence the explicit String()
      throw new Error(`Dirección de destino inválida: ${String(to)}`);
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new Error(`Monto de tUSDT inválido: ${amount}`);
    }

    return this.enqueue(async () => {
      const decimals = await this.getDecimals();
      // toFixed() before parseUnits kills float noise (0.1 + 0.2) and the
      // "too many decimals" NUMERIC_FAULT in one move.
      const units = parseUnits(amount.toFixed(decimals), decimals);

      const tx = await this.token.transfer(getAddress(to), units);
      // Hand the hash over before waiting: if wait() times out, the caller can
      // check whether this transaction landed instead of sending a second one.
      onSent?.(tx.hash);
      this.logger.log(
        `Transferencia de ${amount} tUSDT a ${to} enviada (${tx.hash})`,
      );

      // wait() resolves to null when the tx is dropped, and rejects on timeout
      const receipt = await tx.wait(WAIT_CONFIRMATIONS, WAIT_TIMEOUT_MS);
      if (!receipt || receipt.status !== 1) {
        throw new Error(`La transacción ${tx.hash} no llegó a confirmarse`);
      }
      return { txHash: tx.hash };
    });
  }

  /// Settles through WalikiRouter so the sale emits `PaymentReceived` and the
  /// app's history, reports and CSV can see it. The router moves the tUSDT to
  /// the payout address the merchant registered on-chain, so the funds land
  /// where the shop owner said they should — not wherever the caller asked.
  async payThroughRouter(
    merchantId: number,
    saleId: string,
    amount: number,
    onSent?: (txHash: string) => void,
  ): Promise<{ txHash: string }> {
    if (!Number.isInteger(merchantId) || merchantId <= 0) {
      throw new Error(`merchantId inválido: ${merchantId}`);
    }
    if (!/^0x[0-9a-fA-F]{64}$/.test(saleId)) {
      throw new Error(`saleId inválido: debe ser bytes32 (0x + 64 hex)`);
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new Error(`Monto de tUSDT inválido: ${amount}`);
    }

    return this.enqueue(async () => {
      const decimals = await this.getDecimals();
      const units = parseUnits(amount.toFixed(decimals), decimals);
      const id = BigInt(merchantId);

      // The router pulls with transferFrom, so it needs an allowance. Approving
      // once and reusing it keeps a sale down to a single transaction.
      const allowance = await this.token.allowance(
        this.wallet.address,
        this.routerAddress,
      );
      if (allowance < units) {
        this.logger.log(
          `Aprobando al router ${this.routerAddress} para mover tUSDT`,
        );
        const approval = await this.token.approve(
          this.routerAddress,
          MAX_UINT256,
        );
        await approval.wait(WAIT_CONFIRMATIONS, WAIT_TIMEOUT_MS);
      }

      const tx = await this.router.pay(id, saleId, units);
      onSent?.(tx.hash);
      this.logger.log(
        `Pago de ${amount} tUSDT al comercio ${merchantId} enviado (${tx.hash})`,
      );

      const receipt = await tx.wait(WAIT_CONFIRMATIONS, WAIT_TIMEOUT_MS);
      if (!receipt || receipt.status !== 1) {
        throw new Error(`La transacción ${tx.hash} no llegó a confirmarse`);
      }
      return { txHash: tx.hash };
    });
  }

  /// The contract's own record of a sale. A better idempotency check than a
  /// transaction hash: it answers "was this sale paid" rather than "did that
  /// transaction land", so it holds even across a restart.
  async wasSalePaid(merchantId: number, saleId: string): Promise<boolean> {
    try {
      const paid = await this.router.paidAmount(BigInt(merchantId), saleId);
      return paid > 0n;
    } catch {
      return false;
    }
  }

  /// Did a previously sent transaction land after all? Guards against paying
  /// twice when wait() timed out but the transaction did get mined.
  async wasMined(txHash: string): Promise<boolean> {
    try {
      const receipt = await this.provider.getTransactionReceipt(txHash);
      return receipt?.status === 1;
    } catch {
      return false;
    }
  }

  /// Formatted tUSDT balance of the paying wallet.
  async balance(): Promise<string> {
    const [raw, decimals] = await Promise.all([
      this.token.balanceOf(this.wallet.address),
      this.getDecimals(),
    ]);
    return formatUnits(raw, decimals);
  }

  /// Startup diagnostics: who pays, on which chain, and with how much.
  async logWalletStatus(): Promise<void> {
    try {
      const network = await this.provider.getNetwork();
      this.logger.log(
        `Wallet pagadora: ${this.address} · chainId ${network.chainId}`,
      );
      this.logger.log(`Saldo disponible: ${await this.balance()} tUSDT`);
    } catch (error) {
      this.logger.warn(
        `No se pudo consultar la cadena al arrancar: ${reason(error)}`,
      );
    }
  }

  /// decimals() never changes: read it once, fall back to the .env value.
  private async getDecimals(): Promise<number> {
    if (this.decimals !== undefined) {
      return this.decimals;
    }
    try {
      this.decimals = Number(await this.token.decimals());
    } catch {
      this.logger.warn(
        `No se pudo leer decimals() del token; uso TUSDT_DECIMALS=${this.fallbackDecimals}`,
      );
      this.decimals = this.fallbackDecimals;
    }
    return this.decimals;
  }

  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const next = this.queue.then(task, task);
    // Keep the chain alive: a failed transfer must not poison the queue
    this.queue = next.catch(() => undefined);
    return next;
  }
}
