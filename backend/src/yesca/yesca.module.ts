import { HttpModule } from '@nestjs/axios';
import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { YescaService } from './yesca.service';

@Module({
  imports: [
    // Base URL and bearer token live in the axios instance: no service handles
    // the token, so it cannot leak into a log by accident.
    HttpModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        baseURL: config.getOrThrow<string>('YESCA_API_BASE_URL'),
        timeout: 10_000,
        headers: {
          Authorization: `Bearer ${config.getOrThrow<string>('YESCA_API_TOKEN')}`,
        },
      }),
    }),
  ],
  providers: [YescaService],
  exports: [YescaService],
})
export class YescaModule {}
