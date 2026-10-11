import type { PlayerStats } from '../types.js';

/**
 * Cada modificador es una estrategia independiente. Añadir uno nuevo = registrar
 * un handler, sin tocar RoleManager (Abierto/Cerrado).
 */
export interface IModifierHandler {
  readonly id: string;
  /** Devuelve un mensaje de error si los parámetros no son válidos. */
  validate(params: Record<string, unknown>): string | null;
  apply(stats: PlayerStats, params: Record<string, unknown>): void;
}

export class ModifierRegistry {
  private handlers = new Map<string, IModifierHandler>();

  register(handler: IModifierHandler): this {
    if (this.handlers.has(handler.id)) throw new Error(`Modificador duplicado: ${handler.id}`);
    this.handlers.set(handler.id, handler);
    return this;
  }

  get(id: string): IModifierHandler | undefined {
    return this.handlers.get(id);
  }

  has(id: string): boolean {
    return this.handlers.has(id);
  }
}

// ───────────── Modificadores incluidos ─────────────

const isStringArray = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === 'string');

export const ExtendedReach: IModifierHandler = {
  id: 'extended_reach',
  validate: (p) => (typeof p.multiplier === 'number' && p.multiplier > 0 ? null : 'multiplier debe ser > 0'),
  apply: (s, p) => { s.interactRange *= p.multiplier as number; },
};

export const InventoryCapacity: IModifierHandler = {
  id: 'inventory_capacity',
  validate: (p) => (Number.isInteger(p.delta) ? null : 'delta debe ser entero'),
  apply: (s, p) => { s.inventoryCapacity = Math.max(0, s.inventoryCapacity + (p.delta as number)); },
};

export const ForensicEye: IModifierHandler = {
  id: 'forensic_eye',
  validate: (p) => (isStringArray(p.tags) ? null : 'tags debe ser string[]'),
  apply: (s, p) => { (p.tags as string[]).forEach((t) => s.visibilityUpgrades.add(t)); },
};

export const CanDestroyEvidence: IModifierHandler = {
  id: 'can_destroy_evidence',
  validate: (p) => (isStringArray(p.tags) ? null : 'tags debe ser string[]'),
  apply: (s, p) => { (p.tags as string[]).forEach((t) => s.destroyableTags.add(t)); },
};

export const createDefaultModifierRegistry = (): ModifierRegistry =>
  new ModifierRegistry()
    .register(ExtendedReach)
    .register(InventoryCapacity)
    .register(ForensicEye)
    .register(CanDestroyEvidence);
