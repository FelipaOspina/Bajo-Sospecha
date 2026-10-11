/** Resultado explícito para operaciones de dominio que pueden ser rechazadas. */
export type Result<T, E = string> = { ok: true; value: T } | { ok: false; error: E };

export const ok = <T>(value: T): Result<T, never> => ({ ok: true, value });
export const fail = <E = string>(error: E): Result<never, E> => ({ ok: false, error });
