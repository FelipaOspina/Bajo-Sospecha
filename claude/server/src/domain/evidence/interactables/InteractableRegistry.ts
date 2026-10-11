import type { InteractableConfig, Vec2 } from '../types.js';
import { EvidenceContainer } from './EvidenceContainer.js';
import { EvidenceSpot } from './EvidenceSpot.js';
import type { IInteractable } from './Interactable.js';

export type InteractableFactory = (cfg: InteractableConfig) => IInteractable;

/**
 * Fábrica extensible: nuevos tipos de objeto (puertas, cajas fuertes, terminales)
 * se registran sin modificar EvidenceSystem.
 */
export class InteractableFactoryRegistry {
  private readonly factories = new Map<string, InteractableFactory>();
  register(type: string, f: InteractableFactory): this { this.factories.set(type, f); return this; }
  create(cfg: InteractableConfig): IInteractable {
    const f = this.factories.get(cfg.type);
    if (!f) throw new Error(`Tipo de interactuable desconocido: ${cfg.type}`);
    return f(cfg);
  }
}

export const createDefaultInteractableFactories = () =>
  new InteractableFactoryRegistry()
    .register('evidence_spot', (c) => new EvidenceSpot(c.id, c.position, c.radius))
    .register('container', (c) => new EvidenceContainer(c.id, c.position, c.radius, (c.capacity as number) ?? Infinity));

/** Índice de los objetos del mapa. */
export class InteractableRegistry {
  private readonly byId = new Map<string, IInteractable>();

  add(i: IInteractable) {
    if (this.byId.has(i.id)) throw new Error(`Interactuable duplicado: ${i.id}`);
    this.byId.set(i.id, i);
  }
  get(id: string) { return this.byId.get(id); }
  all() { return [...this.byId.values()]; }

  nearest(pos: Vec2, filter: (i: IInteractable) => boolean = () => true): IInteractable | undefined {
    let best: IInteractable | undefined;
    let bestD = Infinity;
    for (const i of this.byId.values()) {
      if (!filter(i)) continue;
      const d = Math.hypot(i.position.x - pos.x, i.position.y - pos.y);
      if (d < bestD) { bestD = d; best = i; }
    }
    return best;
  }
}
