export type YescaStatus = 'pending' | 'completed' | 'expired' | 'cancelled';

/// Yesca wraps every answer: `{ ok, statusCode, message, data: { ...intent } }`.
export interface YescaEnvelope<T> {
  ok?: boolean;
  statusCode?: number;
  message?: string;
  data?: T;
}

/// The intent itself. Only `id` and `status` are load-bearing for us; the rest
/// travels straight through to our callers, so the type stays open on purpose
/// (Yesca also sends currency, paid_at, account_*, payee_name, handle…).
export interface YescaIntent {
  id: string;
  status: YescaStatus;
  /// Comes back as a string ("12.00"), not the number we sent
  amount?: string | number | null;
  expires_at?: string;
  token?: string;
  base64?: string;
  [key: string]: unknown;
}

/// Exactly the fields Yesca accepts. Anything else earns a 400 from them, so
/// this closed type is the guard: TS rejects an extra key at compile time.
export interface YescaCreateIntentPayload {
  amount?: number;
  description?: string;
  additional_data?: string;
  single_use?: boolean;
  expires_at?: string;
}

/// Our camelCase input; YescaService maps it to the payload above.
export interface CreateIntentInput {
  amount?: number;
  description?: string;
  additionalData?: string;
  singleUse?: boolean;
  expiresAt?: string;
}
