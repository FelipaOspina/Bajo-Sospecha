/**
 * shared/config/cosmetics/cosmetics.json: ropa, gorras, zapatillas y mochilas del avatar.
 * Es lo único que se compra (con monedas del juego): no cambia nada del juego.
 */

export type CosmeticSlot = 'outfit' | 'hat' | 'shoes' | 'bag';
export const COSMETIC_SLOTS: readonly CosmeticSlot[] = ['outfit', 'hat', 'shoes', 'bag'];

export interface CosmeticItem {
  id: string;
  slot: CosmeticSlot;
  name: string;
  color: string;
  style?: 'suit' | 'hoodie';
  rarity?: string;
}

export interface CosmeticConfig {
  slots: Record<CosmeticSlot, string>;
  items: CosmeticItem[];
}

/** Lo que lleva puesto un jugador: un objeto por hueco (ids del catálogo). */
export type Look = Partial<Record<CosmeticSlot, string>>;

export interface ICosmeticCatalog {
  has(id: string): boolean;
  slotOf(id: string): CosmeticSlot | undefined;
}

export class CosmeticCatalog implements ICosmeticCatalog {
  private readonly byId: Map<string, CosmeticItem>;

  constructor(config: CosmeticConfig) {
    this.byId = new Map(config.items.map((i) => [i.id, i]));
    for (const i of config.items) {
      if (!COSMETIC_SLOTS.includes(i.slot)) throw new Error(`cosmético ${i.id}: hueco desconocido ${i.slot}`);
      if (!/^#[0-9a-fA-F]{6}$/.test(i.color)) throw new Error(`cosmético ${i.id}: color no válido ${i.color}`);
    }
    if (this.byId.size !== config.items.length) throw new Error('cosméticos con ids repetidos');
  }

  has(id: string): boolean { return this.byId.has(id); }
  get(id: string): CosmeticItem | undefined { return this.byId.get(id); }
  slotOf(id: string): CosmeticSlot | undefined { return this.byId.get(id)?.slot; }
}
