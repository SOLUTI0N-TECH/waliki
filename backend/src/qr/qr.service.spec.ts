// @nestjs/config and @nestjs/axios ship ESM and Jest cannot require them
// here. QrService touches neither: they only arrive through BlockchainService
// and YescaService, both mocked below, so stubs keep the imports loadable.
jest.mock('@nestjs/config', () => ({ ConfigService: class {} }));
jest.mock('@nestjs/axios', () => ({ HttpService: class {} }));

import { Test, type TestingModule } from '@nestjs/testing';
import { BlockchainService } from '../blockchain/blockchain.service';
import { YescaService } from '../yesca/yesca.service';
import { QrService } from './qr.service';
import { QrStoreService } from './qr-store.service';
import type { YescaIntent, YescaStatus } from '../yesca/yesca.types';

const SALE_ID = `0x${'ab'.repeat(32)}`;
/// Sent in any casing; the service stores it checksummed, so the two forms
/// are kept apart on purpose.
const WALLET_SENT = '0x3ca0e1d199ef95c2074248613a34a17b90702440';
const WALLET_STORED = '0x3ca0e1D199Ef95C2074248613A34a17B90702440';

describe('QrService — por dónde se liquida', () => {
  let service: QrService;
  let status: YescaStatus;
  let payThroughRouter: jest.Mock;
  let transferTUSDT: jest.Mock;
  let wasSalePaid: jest.Mock;

  const intent = (): YescaIntent => ({ id: 'int_1', status, base64: 'AAA=' });

  beforeEach(async () => {
    status = 'pending';
    payThroughRouter = jest.fn().mockResolvedValue({ txHash: '0xrouter' });
    transferTUSDT = jest.fn().mockResolvedValue({ txHash: '0xplain' });
    wasSalePaid = jest.fn().mockResolvedValue(false);

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        QrService,
        QrStoreService,
        {
          provide: YescaService,
          useValue: {
            createIntent: jest.fn().mockImplementation(() => intent()),
            getIntentStatus: jest.fn().mockImplementation(() => intent()),
          },
        },
        {
          provide: BlockchainService,
          useValue: {
            payThroughRouter,
            transferTUSDT,
            wasSalePaid,
            wasMined: jest.fn().mockResolvedValue(false),
          },
        },
      ],
    }).compile();
    service = module.get(QrService);
  });

  const create = (extra: Record<string, unknown> = {}) =>
    service.create({
      cryptoAmount: 15.2,
      destinationWallet: WALLET_SENT,
      ...extra,
    } as never);

  it('con merchantId y saleId liquida por el router, para que la venta se vea en el historial', async () => {
    await create({ merchantId: 1, saleId: SALE_ID });
    status = 'completed';

    const res = await service.status('int_1');

    expect(payThroughRouter).toHaveBeenCalledWith(
      1,
      SALE_ID,
      15.2,
      expect.any(Function),
    );
    expect(transferTUSDT).not.toHaveBeenCalled();
    expect(res.transferred).toBe(true);
    expect(res.txHash).toBe('0xrouter');
  });

  it('sin esos datos cae al transfer directo, como antes', async () => {
    await create();
    status = 'completed';

    const res = await service.status('int_1');

    expect(transferTUSDT).toHaveBeenCalledWith(
      WALLET_STORED,
      15.2,
      expect.any(Function),
    );
    expect(payThroughRouter).not.toHaveBeenCalled();
    expect(res.txHash).toBe('0xplain');
  });

  it('un merchantId sin saleId no alcanza: el contrato necesita los dos', async () => {
    await create({ merchantId: 1 });
    status = 'completed';

    await service.status('int_1');

    expect(payThroughRouter).not.toHaveBeenCalled();
    expect(transferTUSDT).toHaveBeenCalled();
  });

  it('no paga mientras el banco no confirme', async () => {
    await create({ merchantId: 1, saleId: SALE_ID });

    const res = await service.status('int_1');

    expect(payThroughRouter).not.toHaveBeenCalled();
    expect(res.transferred).toBe(false);
  });

  it('si el contrato ya registra la venta, no la paga de nuevo', async () => {
    // The guard that makes a retry safe after a timeout or a restart.
    wasSalePaid.mockResolvedValue(true);
    await create({ merchantId: 1, saleId: SALE_ID });
    status = 'completed';

    const res = await service.status('int_1');

    expect(payThroughRouter).not.toHaveBeenCalled();
    expect(res.transferred).toBe(true);
  });

  it('una liquidación fallida se informa y no marca la venta como pagada', async () => {
    payThroughRouter.mockRejectedValue(new Error('sin saldo'));
    await create({ merchantId: 1, saleId: SALE_ID });
    status = 'completed';

    const res = await service.status('int_1');

    expect(res.transferred).toBe(false);
    expect(res.lastError).toContain('sin saldo');

    // …y la siguiente consulta lo reintenta
    payThroughRouter.mockResolvedValue({ txHash: '0xok' });
    const retry = await service.status('int_1');
    expect(retry.transferred).toBe(true);
    expect(retry.txHash).toBe('0xok');
  });

  it('dos consultas simultáneas comparten una sola transferencia', async () => {
    await create({ merchantId: 1, saleId: SALE_ID });
    status = 'completed';

    await Promise.all([service.status('int_1'), service.status('int_1')]);

    expect(payThroughRouter).toHaveBeenCalledTimes(1);
  });
});
