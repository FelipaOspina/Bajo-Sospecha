export interface MatchmakerOptions {
  /** Jugadores para empezar la cuenta atrás (MATCH_MIN). */
  minSize: number;
  /** Con estos en cola arranca ya (MATCH_MAX). */
  maxSize: number;
  /** Cuenta atrás desde que se alcanza el mínimo (MATCH_WAIT_MS). */
  waitMs: number;
  now: () => number;
}

const DEFAULTS: MatchmakerOptions = { minSize: 4, maxSize: 12, waitMs: 30_000, now: () => Date.now() };

/**
 * Cola pública, por orden de llegada:
 *  - con maxSize en cola sale ya un grupo de maxSize;
 *  - con minSize empieza una cuenta atrás de waitMs; al vencer (tick) sale un grupo
 *    con todos los que haya (como mucho maxSize);
 *  - si baja de minSize, la cuenta atrás se cancela.
 * No sabe nada de sockets ni de salas: devuelve el grupo y GameGateway crea la sala.
 */
export class Matchmaker<T> {
  private readonly queue: T[] = [];
  private readonly opts: MatchmakerOptions;
  /** Hora a la que arranca el grupo actual; null sin cuenta atrás. */
  private deadline: number | null = null;

  /** Un número = tamaño fijo (compatibilidad: min = max = n). */
  constructor(opts: Partial<MatchmakerOptions> | number = {}) {
    const o = typeof opts === 'number' ? { minSize: opts, maxSize: opts } : opts;
    this.opts = { ...DEFAULTS, ...o };
    if (this.opts.minSize > this.opts.maxSize) this.opts.minSize = this.opts.maxSize;
  }

  get matchSize() { return this.opts.maxSize; }
  get minSize() { return this.opts.minSize; }
  get startsAt(): number | null { return this.deadline; }

  /** Entra en la cola. Si se completa un grupo de maxSize, lo devuelve (y lo saca de la cola). */
  enqueue(ticket: T): T[] | null {
    if (!this.queue.includes(ticket)) this.queue.push(ticket);
    if (this.queue.length >= this.opts.maxSize) {
      const group = this.queue.splice(0, this.opts.maxSize);
      this.deadline = null;
      this.refreshCountdown();
      return group;
    }
    this.refreshCountdown();
    return null;
  }

  remove(ticket: T): boolean {
    const i = this.queue.indexOf(ticket);
    if (i < 0) return false;
    this.queue.splice(i, 1);
    this.refreshCountdown();
    return true;
  }

  /** Llamar periódicamente: al vencer la cuenta atrás devuelve el grupo que arranca. */
  tick(): T[] | null {
    if (this.deadline === null || this.opts.now() < this.deadline) return null;
    const group = this.queue.splice(0, this.opts.maxSize);
    this.deadline = null;
    this.refreshCountdown();
    return group.length >= this.opts.minSize ? group : null;
  }

  /** 1 = el primero; 0 = no está en la cola. */
  position(ticket: T): number {
    return this.queue.indexOf(ticket) + 1;
  }

  waiting(): readonly T[] {
    return this.queue;
  }

  private refreshCountdown(): void {
    if (this.queue.length < this.opts.minSize) this.deadline = null;
    else if (this.deadline === null) this.deadline = this.opts.now() + this.opts.waitMs;
  }
}
