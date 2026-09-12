import { HttpService } from '@nestjs/axios';
import { BadGatewayException, Injectable } from '@nestjs/common';
import type { AxiosError } from 'axios';
import { catchError, firstValueFrom } from 'rxjs';
import { toHttpException } from './yesca.errors';
import type {
  CreateIntentInput,
  YescaCreateIntentPayload,
  YescaEnvelope,
  YescaIntent,
} from './yesca.types';

/// Default quote window when the caller does not set one.
const QUOTE_MINUTES = 15;

/// Pulls the intent out of the `{ ok, statusCode, message, data }` envelope.
/// An answer without an id is an error, never a record keyed by undefined.
function unwrap(
  body: YescaEnvelope<YescaIntent> | YescaIntent,
  action: string,
): YescaIntent {
  const intent =
    (body as YescaEnvelope<YescaIntent>).data ?? (body as YescaIntent);
  if (typeof intent?.id !== 'string' || intent.id === '') {
    throw new BadGatewayException(
      `La pasarela respondió sin el id del cobro al ${action}.`,
    );
  }
  return intent;
}

/// Thin client for the external bank-QR gateway. The base URL and the bearer
/// token are baked into the axios instance (see YescaModule), so they never
/// travel through this class.
@Injectable()
export class YescaService {
  constructor(private readonly http: HttpService) {}

  async createIntent(input: CreateIntentInput): Promise<YescaIntent> {
    // Yesca answers 400 to any unknown field, and null counts as present:
    // the payload is built key by key, never spread from our DTO.
    const payload: YescaCreateIntentPayload = {
      single_use: input.singleUse ?? true,
      expires_at:
        input.expiresAt ??
        new Date(Date.now() + QUOTE_MINUTES * 60_000).toISOString(),
    };
    // A missing or zero amount means "open amount": the key must be absent
    if (input.amount !== undefined && input.amount > 0) {
      payload.amount = input.amount;
    }
    if (input.description) {
      payload.description = input.description;
    }
    if (input.additionalData) {
      payload.additional_data = input.additionalData;
    }

    const { data } = await firstValueFrom(
      this.http
        .post<YescaEnvelope<YescaIntent>>(
          '/transactions/intent/create',
          payload,
        )
        .pipe(
          catchError((error: AxiosError) => {
            throw toHttpException(error, 'crear el cobro');
          }),
        ),
    );
    return unwrap(data, 'crear el cobro');
  }

  async getIntentStatus(id: string): Promise<YescaIntent> {
    const path = `/transactions/intent/${encodeURIComponent(id)}/status`;
    const { data } = await firstValueFrom(
      this.http.get<YescaEnvelope<YescaIntent>>(path).pipe(
        catchError((error: AxiosError) => {
          throw toHttpException(error, 'consultar el estado del cobro');
        }),
      ),
    );
    return unwrap(data, 'consultar el estado del cobro');
  }
}
