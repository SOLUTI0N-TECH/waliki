import {
  BadGatewayException,
  BadRequestException,
  HttpException,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { AxiosError } from 'axios';

const logger = new Logger('YescaApi');

interface YescaErrorBody {
  message?: string;
  error?: string;
}

/// Translates an AxiosError into something the caller can act on.
///
/// Never logs `error`, `error.config` or `error.toJSON()`: the Authorization
/// header travels inside them and would end up in the logs.
export function toHttpException(
  error: AxiosError,
  action: string,
): HttpException {
  const status = error.response?.status;
  const body = error.response?.data as YescaErrorBody | undefined;
  const detail = body?.message ?? body?.error ?? error.message;

  logger.error(
    `Fallo al ${action}: la pasarela respondió ${status ?? 'nada'} — ${detail}`,
  );

  switch (status) {
    case 400:
      return new BadRequestException(
        `La pasarela rechazó los datos del cobro: ${detail}`,
      );
    case 401:
    case 403:
      // Deliberately not a 401 for our caller: the rejected credentials are the
      // service's, not theirs (check YESCA_API_TOKEN).
      return new BadGatewayException(
        'La pasarela rechazó las credenciales del servicio.',
      );
    case 404:
      return new NotFoundException('La pasarela no encuentra ese cobro.');
    default:
      return status !== undefined && status >= 500
        ? new BadGatewayException(`La pasarela falló al ${action}.`)
        : new ServiceUnavailableException(
            `No se pudo contactar la pasarela para ${action}.`,
          );
  }
}
