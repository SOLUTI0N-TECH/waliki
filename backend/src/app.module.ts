import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { BlockchainModule } from './blockchain/blockchain.module';
import { validate } from './config/env.validation';
import { HealthController } from './health.controller';
import { QrModule } from './qr/qr.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate }),
    BlockchainModule,
    QrModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
