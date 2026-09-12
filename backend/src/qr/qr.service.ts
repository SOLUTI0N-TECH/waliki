import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { getAddress } from 'ethers';
import { BlockchainService } from '../blockchain/blockchain.service';
import { YescaService } from '../yesca/yesca.service';
import { CreateQrDto } from './dto/create-qr.dto';
import { QrStoreService } from './qr-store.service';
import type { QrRecord, QrResponse } from './qr.types';

/// Orchestrates the two sides of a sale: the bank QR issued by Yesca and the
/// tUSDT that must reach the destination wallet once that QR is paid.
@Injectable()
export class QrService {
  private readonly logger = new Logger(QrService.name);
  /// Settlements in flight, by QR id. Two concurrent status calls share one
  /// transfer instead of sending two.
  private readonly inFlight = new Map<string, Promise<void>>();

  constructor(
    private readonly yesca: YescaService,
    private readonly blockchain: BlockchainService,
    private readonly store: QrStoreService,
  ) {}

  async create(dto: CreateQrDto): Promise<QrResponse> {
    const intent = await this.yesca.createIntent({
      amount: dto.amount,
      description: dto.description,
      additionalData: dto.additionalData,
      singleUse: dto.singleUse,
      expiresAt: dto.expiresAt,
    });

    const record = this.store.save({
      intent,
      cryptoAmount: dto.cryptoAmount,
      // Store the checksummed form: the DTO accepts any casing
      destinationWallet: getAddress(dto.destinationWallet),
      // Only a complete pair routes through the contract
      ...(dto.merchantId !== undefined &&
        dto.saleId !== undefined && {
          merchantId: dto.merchantId,
          saleId: dto.saleId.toLowerCase(),
        }),
      crypto: { transferred: false },
    });
    this.logger.log(
      `QR ${intent.id} creado · ${dto.cryptoAmount} tUSDT reservados para ${record.destinationWallet}`,
    );
    return this.present(record);
  }

  async status(id: string): Promise<QrResponse> {
    const record = this.store.get(id);
    if (!record) {
      throw new NotFoundException(
        `No conocemos el QR ${id}: se generó en otro proceso o el servidor se reinició.`,
      );
    }

    record.intent = await this.yesca.getIntentStatus(id);
    if (record.intent.status === 'completed' && !record.crypto.transferred) {
      await this.settle(record);
    }
    return this.present(record);
  }

  /// Pays the crypto side exactly once per QR.
  private async settle(record: QrRecord): Promise<void> {
    const id = record.intent.id;
    // get + set with no await in between: atomic on Node's single thread
    let running = this.inFlight.get(id);
    if (!running) {
      running = this.runTransfer(record).finally(() =>
        this.inFlight.delete(id),
      );
      this.inFlight.set(id, running);
    }
    await running;
  }

  /// A failure is recorded, not thrown: the caller still gets the QR state and
  /// the next status call retries the transfer.
  private async runTransfer(record: QrRecord): Promise<void> {
    const id = record.intent.id;

    const { merchantId, saleId } = record;
    const throughRouter = merchantId !== undefined && saleId !== undefined;

    // The contract's own record beats a transaction hash: it survives a
    // restart and answers "was this sale paid", not "did that tx land".
    if (throughRouter && (await this.blockchain.wasSalePaid(merchantId, saleId))) {
      record.crypto = {
        ...record.crypto,
        transferred: true,
        ...(record.crypto.pendingTxHash !== undefined && {
          txHash: record.crypto.pendingTxHash,
        }),
      };
      this.logger.warn(`QR ${id}: la venta ${saleId} ya figura pagada on-chain`);
      return;
    }

    // An earlier attempt may have timed out while its transaction still landed
    const pending = record.crypto.pendingTxHash;
    if (pending !== undefined && (await this.blockchain.wasMined(pending))) {
      record.crypto = { transferred: true, txHash: pending };
      this.logger.warn(
        `QR ${id}: la transferencia ${pending} sí se confirmó; no se repite`,
      );
      return;
    }

    try {
      const onSent = (sentHash: string) => {
        record.crypto = { ...record.crypto, pendingTxHash: sentHash };
      };
      const { txHash } = throughRouter
        ? await this.blockchain.payThroughRouter(
            merchantId,
            saleId,
            record.cryptoAmount,
            onSent,
          )
        : await this.blockchain.transferTUSDT(
            record.destinationWallet,
            record.cryptoAmount,
            onSent,
          );
      record.crypto = { transferred: true, txHash };
      this.logger.log(
        `QR ${id} pagado · ${record.cryptoAmount} tUSDT liquidados (${txHash})`,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      record.crypto = {
        ...record.crypto,
        transferred: false,
        lastError: message,
      };
      this.logger.error(`QR ${id}: falló la liquidación de tUSDT — ${message}`);
    }
  }

  private present(record: QrRecord): QrResponse {
    return {
      ...record.intent,
      cryptoAmount: record.cryptoAmount,
      destinationWallet: record.destinationWallet,
      ...(record.merchantId !== undefined && { merchantId: record.merchantId }),
      ...(record.saleId !== undefined && { saleId: record.saleId }),
      transferred: record.crypto.transferred,
      ...(record.crypto.txHash !== undefined && {
        txHash: record.crypto.txHash,
      }),
      ...(record.crypto.lastError !== undefined && {
        lastError: record.crypto.lastError,
      }),
    };
  }
}
