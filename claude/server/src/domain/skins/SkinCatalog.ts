import type { IRandom } from '../../core/Random.js';

/** shared/config/skins/skins.json (el cliente lee además los colores del chibi). */
export interface SkinConfig {
  /** true = al empezar, cada jugador lleva la skin de su rol. Delata el rol a todos. */
  assign_by_role?: boolean;
  role_skins?: Record<string, string>;
  skins: { id: string; name: string }[];
}

/**
 * Reparte las skins de animales. Son cosméticas y públicas, así que se asignan por
 * jugador (al azar entre las libres, o la que elija en el lobby), no por rol.
 */
export class SkinCatalog {
  constructor(private readonly config: SkinConfig, private readonly rng: IRandom) {}

  get assignByRole(): boolean { return this.config.assign_by_role === true; }

  has(id: string): boolean {
    return this.config.skins.some((s) => s.id === id);
  }

  /** Una skin que nadie lleve (de las permitidas, si se indican); si están todas cogidas, cualquiera. */
  pickFree(taken: Iterable<string | undefined>, allowed?: string[]): string | undefined {
    const used = new Set(taken);
    const all = this.config.skins.map((s) => s.id).filter((id) => !allowed || allowed.includes(id));
    const free = all.filter((id) => !used.has(id));
    const pool = free.length > 0 ? free : all;
    return pool.length > 0 ? pool[Math.floor(this.rng.next() * pool.length)] : undefined;
  }

  /** Skin de un rol si assign_by_role está activo y el rol tiene una válida. */
  forRole(roleId: string | undefined): string | undefined {
    if (!this.assignByRole || !roleId) return undefined;
    const id = this.config.role_skins?.[roleId];
    return id && this.has(id) ? id : undefined;
  }
}
