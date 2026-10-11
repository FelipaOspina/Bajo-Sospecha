/**
 * Cola pública. Agrupa a los que esperan de matchSize en matchSize, por orden de
 * llegada. No sabe nada de sockets ni de salas: devuelve el grupo y GameGateway
 * crea la sala y los mete.
 */
export class Matchmaker<T> {
  private readonly queue: T[] = [];

  constructor(readonly matchSize = 4) {}

  /** Entra en la cola. Si se completa un grupo, lo devuelve (y lo saca de la cola). */
  enqueue(ticket: T): T[] | null {
    if (!this.queue.includes(ticket)) this.queue.push(ticket);
    return this.queue.length >= this.matchSize ? this.queue.splice(0, this.matchSize) : null;
  }

  remove(ticket: T): boolean {
    const i = this.queue.indexOf(ticket);
    if (i < 0) return false;
    this.queue.splice(i, 1);
    return true;
  }

  /** 1 = el primero; 0 = no está en la cola. */
  position(ticket: T): number {
    return this.queue.indexOf(ticket) + 1;
  }

  waiting(): readonly T[] {
    return this.queue;
  }
}
