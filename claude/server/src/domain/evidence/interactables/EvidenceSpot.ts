import type { Vec2 } from '../types.js';
import type { IEvidenceDropTarget, IEvidenceSource, PickContext } from './Interactable.js';

/** Un punto del mapa con como mucho una prueba (un cajón, el suelo, una mesa). */
export class EvidenceSpot implements IEvidenceSource, IEvidenceDropTarget {
  readonly type = 'evidence_spot';
  private held: string | null = null;

  constructor(public readonly id: string, public readonly position: Vec2, public readonly radius: number) {}

  contents() { return this.held ? [this.held] : []; }

  pickCandidate(ctx: PickContext) {
    return this.held && ctx.canPerceive(this.held) ? this.held : null;
  }

  take(instanceId: string) {
    if (this.held !== instanceId) return false;
    this.held = null;
    return true;
  }

  canAccept() { return this.held === null; }
  put(instanceId: string) { this.held = instanceId; }
}
