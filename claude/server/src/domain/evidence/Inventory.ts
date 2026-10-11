import type { PlayerId } from './types.js';

/** Inventario de UN jugador. Solo guarda ids; el peso lo calcula quien conoce el catálogo. */
export interface IInventory {
  readonly owner: PlayerId;
  items(): readonly string[];
  has(instanceId: string): boolean;
  add(instanceId: string): void;
  remove(instanceId: string): boolean;
}

export class Inventory implements IInventory {
  private readonly ids: string[] = [];
  constructor(public readonly owner: PlayerId) {}

  items() { return this.ids; }
  has(id: string) { return this.ids.includes(id); }
  add(id: string) { if (!this.has(id)) this.ids.push(id); }
  remove(id: string) {
    const i = this.ids.indexOf(id);
    if (i < 0) return false;
    this.ids.splice(i, 1);
    return true;
  }
}

/** Crea inventarios bajo demanda. Sustituible por uno persistente (Redis, BD). */
export interface IInventoryStore {
  of(playerId: PlayerId): IInventory;
  delete(playerId: PlayerId): void;
}

export class InMemoryInventoryStore implements IInventoryStore {
  private readonly map = new Map<PlayerId, IInventory>();
  of(playerId: PlayerId) {
    let inv = this.map.get(playerId);
    if (!inv) this.map.set(playerId, (inv = new Inventory(playerId)));
    return inv;
  }
  delete(playerId: PlayerId) { this.map.delete(playerId); }
}
