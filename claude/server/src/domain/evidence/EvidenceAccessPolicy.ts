import type { AccessRequirement, EvidenceDefinition } from './types.js';

export type AccessAction = 'view' | 'collect';

export interface AccessCheck {
  ok: boolean;
  /** Qué falta: 'role' o 'item' (el primero que falle). */
  missing?: 'role' | 'item';
  /** Ids de los ítems que faltan. */
  missingItems?: string[];
}

export interface AccessSubject {
  roleId: string | undefined;
  /** Ids de definición que lleva en el inventario. */
  carried: ReadonlySet<string>;
}

/**
 * Decide si un jugador cumple el permiso especial de una prueba.
 * Recoger implica poder ver: el requisito de 'collect' se suma al de 'view'.
 */
export interface IEvidenceAccessPolicy {
  check(def: EvidenceDefinition, action: AccessAction, who: AccessSubject): AccessCheck;
}

export class RequirementAccessPolicy implements IEvidenceAccessPolicy {
  check(def: EvidenceDefinition, action: AccessAction, who: AccessSubject): AccessCheck {
    const reqs: (AccessRequirement | undefined)[] =
      action === 'view' ? [def.access?.view] : [def.access?.view, def.access?.collect];
    for (const req of reqs) {
      if (!req) continue;
      if (req.roles?.length && !(who.roleId && req.roles.includes(who.roleId))) return { ok: false, missing: 'role' };
      const missingItems = (req.items ?? []).filter((i) => !who.carried.has(i));
      if (missingItems.length) return { ok: false, missing: 'item', missingItems };
    }
    return { ok: true };
  }
}
