import { Module } from '@nestjs/common';
import { BlockchainModule } from '../blockchain/blockchain.module';
import { YescaModule } from '../yesca/yesca.module';
import { QrController } from './qr.controller';
import { QrStoreService } from './qr-store.service';
import { QrService } from './qr.service';

@Module({
  imports: [YescaModule, BlockchainModule],
  controllers: [QrController],
  providers: [QrService, QrStoreService],
})
export class QrModule {}
