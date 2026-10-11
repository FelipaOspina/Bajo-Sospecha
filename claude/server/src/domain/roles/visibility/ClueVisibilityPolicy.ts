import { VISIBILITY_ORDER, type PlayerStats, type RoleDefinition, type VisibilityLevel } from '../types.js';

/** Decide qué nivel de detalle percibe un rol sobre una prueba con ciertas etiquetas. */
export interface IVisibilityPolicy {
  resolve(role: RoleDefinition | undefined, stats: PlayerStats, evidenceTags: readonly string[]): VisibilityLevel;
}

/**
 * Política por defecto:
 *  1. Si alguna etiqueta está en stats.visibilityUpgrades → 'full'.
 *  2. Si hay reglas que coinciden, gana la MÁS RESTRICTIVA (un 'hidden' explícito
 *     manda sobre un 'full' de otra regla). Así un diseñador puede ocultar
 *     pistas concretas a un rol aunque otra regla general las muestre.
 *  3. Si ninguna regla coincide → role.visibility.default.
 *  Sin rol (espectador / lobby) → 'hidden'.
 */
export class RestrictiveVisibilityPolicy implements IVisibilityPolicy {
  resolve(role: RoleDefinition | undefined, stats: PlayerStats, tags: readonly string[]): VisibilityLevel {
    if (!role) return 'hidden';
    if (tags.some((t) => stats.visibilityUpgrades.has(t))) return 'full';

    let result: VisibilityLevel | null = null;
    for (const rule of role.visibility.rules) {
      if (!rule.tags.some((t) => tags.includes(t))) continue;
      if (result === null || VISIBILITY_ORDER[rule.level] < VISIBILITY_ORDER[result]) result = rule.level;
    }
    return result ?? role.visibility.default;
  }
}
