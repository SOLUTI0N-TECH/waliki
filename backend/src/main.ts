import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { BlockchainService } from './blockchain/blockchain.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // As strict as Yesca itself: an unknown field is a clear 400 from here
  // instead of a confusing one from the gateway.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );
  // Prototype: any front-end (the Vite dev server, a phone) may call this
  app.enableCors({ origin: true });

  const port = app.get(ConfigService).get<number>('PORT') ?? 3000;
  await app.listen(port);

  new Logger('Bootstrap').log(
    `Waliki backend escuchando en http://localhost:${port}`,
  );
  await app.get(BlockchainService).logWalletStatus();
}

void bootstrap();
