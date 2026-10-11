import type { ModifierRegistry } from './modifiers/ModifierRegistry.js';
import type { ObjectiveRegistry } from './objectives/ObjectiveRegistry.js';
import { VISIBILITY_ORDER, type RoleSetConfig } from './types.js';

export class RoleConfigError extends Error {
  constructor(public readonly problems: string[]) {
    super(`Configuración de roles inválida:\n - ${problems.join('\n - ')}`);
  }
}

/**
 * Valida la forma Y la coherencia del JSON antes de que entre al juego.
 * Responsabilidad única: no carga, no asigna; solo dice si el config es usable.
 */
export class RoleConfigValidator {
  constructor(
    private readonly modifiers: ModifierRegistry,
    private readonly objectives: ObjectiveRegistry,
  ) {}

  validate(input: unknown): RoleSetConfig {
    const p: string[] = [];
    const c = input as Partial<RoleSetConfig>;
    if (!c || typeof c !== 'object') throw new RoleConfigError(['el config no es un objeto']);
    if (typeof c.id !== 'string') p.push('id requerido');
    if (!Number.isInteger(c.minPlayers) || !Number.isInteger(c.maxPlayers)) p.push('minPlayers/maxPlayers deben ser enteros');
    if (!Array.isArray(c.roles) || c.roles.length === 0) p.push('roles debe ser un array no vacío');
    if (p.length) throw new RoleConfigError(p);

    const ids = new Set<string>();
    let sumMin = 0;
    let sumMax = 0;
    for (const r of c.roles!) {
      const where = `rol "${r.id}"`;
      if (!r.id || ids.has(r.id)) p.push(`${where}: id vacío o duplicado`);
      ids.add(r.id);
      if (!r.team) p.push(`${where}: team requerido`);
      if (!r.count || r.count.min < 0 || r.count.max < r.count.min) p.push(`${where}: count inválido`);
      sumMin += r.count?.min ?? 0;
      sumMax += r.count?.max ?? 0;

      if (!r.visibility || !(r.visibility.default in VISIBILITY_ORDER)) p.push(`${where}: visibility.default inválido`);
      for (const rule of r.visibility?.rules ?? []) {
        if (!(rule.level in VISIBILITY_ORDER)) p.push(`${where}: nivel de visibilidad "${rule.level}" desconocido`);
        if (!Array.isArray(rule.tags) || rule.tags.length === 0) p.push(`${where}: regla de visibilidad sin tags`);
      }

      for (const m of r.modifiers ?? []) {
        const handler = this.modifiers.get(m.id);
        if (!handler) { p.push(`${where}: modificador desconocido "${m.id}"`); continue; }
        const err = handler.validate(m.params ?? {});
        if (err) p.push(`${where}: modificador "${m.id}": ${err}`);
      }

      for (const o of r.objectives ?? []) {
        const handler = this.objectives.get(o.type);
        if (!handler) { p.push(`${where}: tipo de objetivo desconocido "${o.type}"`); continue; }
        const err = handler.validate(o.params ?? {});
        if (err) p.push(`${where}: objetivo "${o.id}": ${err}`);
      }
    }

    if (sumMin > c.minPlayers!) p.push(`la suma de mínimos (${sumMin}) supera minPlayers (${c.minPlayers})`);
    if (sumMax < c.maxPlayers!) p.push(`la suma de máximos (${sumMax}) no cubre maxPlayers (${c.maxPlayers})`);

    if (p.length) throw new RoleConfigError(p);
    return c as RoleSetConfig;
  }
}
