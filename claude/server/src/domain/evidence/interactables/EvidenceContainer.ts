import type { Vec2 } from '../types.js';
import type { IEvidenceDropTarget, IEvidenceSource, PickContext } from './Interactable.js';

/** Contenedor con varias pruebas (baúl, armario). Entrega la primera que el jugador percibe. */
export class EvidenceContainer implements IEvidenceSource, IEvidenceDropTarget {
  readonly type = 'container';
  private readonly items: string[] = [];

  constructor(
    public readonly id: string,
    public readonly position: Vec2,
    public readonly radius: number,
    private readonly capacity = Infinity,
  ) {}

  contents() { return this.items; }

  pickCandidate(ctx: PickContext) {
    return this.items.find((i) => ctx.canPerceive(i)) ?? null;
  }

  take(instanceId: string) {
    const i = this.items.indexOf(instanceId);
    if (i < 0) return false;
    this.items.splice(i, 1);
    return true;
  }

  canAccept() { return this.items.length < this.capacity; }
  put(instanceId: string) { this.items.push(instanceId); }
}
