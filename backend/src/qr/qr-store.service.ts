import { Injectable } from '@nestjs/common';
import type { QrRecord } from './qr.types';

/// In-memory store. This is a prototype: the map dies with the process, and a
/// restarted server simply does not know the QRs it issued before.
@Injectable()
export class QrStoreService {
  private readonly records = new Map<string, QrRecord>();

  save(record: QrRecord): QrRecord {
    this.records.set(record.intent.id, record);
    return record;
  }

  get(id: string): QrRecord | undefined {
    return this.records.get(id);
  }
}
