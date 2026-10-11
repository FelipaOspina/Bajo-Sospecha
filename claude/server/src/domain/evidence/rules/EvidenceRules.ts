import type { PlayerStats } from '../../roles/types.js';
import type { AccessSubject, IEvidenceAccessPolicy } from '../EvidenceAccessPolicy.js';
import { RequirementAccessPolicy } from '../EvidenceAccessPolicy.js';
import type { IInteractable } from '../interactables/Interactable.js';
import type { EvidenceDefinition, EvidenceInstance, PlayerId, RoomPhase, Vec2 } from '../types.js';

export type EvidenceAction = 'collect' | 'drop' | 'destroy' | 'present';

export interface EvidenceRuleContext {
  action: EvidenceAction;
  playerId: PlayerId;
  playerPosition: Vec2;
  alive: boolean;
  phase: RoomPhase;
  stats: PlayerStats;
  /** Peso total que ya carga el jugador. */
  carriedWeight: number;
  instance: EvidenceInstance;
  definition: EvidenceDefinition;
  interactable?: IInteractable;
  /** Rol e inventario del jugador, para permisos especiales. */
  subject: AccessSubject;
}

/**
 * Una regla = una razón para rechazar una acción.
 * EvidenceSystem ejecuta la cadena completa; añadir reglas no lo modifica.
 */
export interface IEvidenceRule {
  readonly appliesTo: readonly EvidenceAction[];
  /** null si permite la acción; si no, el motivo del rechazo. */
  check(ctx: EvidenceRuleContext): string | null;
}

export class AliveRule implements IEvidenceRule {
  readonly appliesTo = ['collect', 'drop', 'destroy', 'present'] as const;
  check(ctx: EvidenceRuleContext) { return ctx.alive ? null : 'not_alive'; }
}

export class PhaseRule implements IEvidenceRule {
  constructor(
    public readonly appliesTo: readonly EvidenceAction[],
    private readonly allowed: readonly RoomPhase[],
  ) {}
  check(ctx: EvidenceRuleContext) { return this.allowed.includes(ctx.phase) ? null : 'wrong_phase'; }
}

/** Hay que estar cerca para recoger o soltar. */
export class InRangeRule implements IEvidenceRule {
  readonly appliesTo = ['collect', 'drop'] as const;
  check(ctx: EvidenceRuleContext) {
    const i = ctx.interactable;
    if (!i) return 'no_target';
    const d = Math.hypot(i.position.x - ctx.playerPosition.x, i.position.y - ctx.playerPosition.y);
    return d <= ctx.stats.interactRange + i.radius ? null : 'out_of_range';
  }
}

export class PocketableRule implements IEvidenceRule {
  readonly appliesTo = ['collect'] as const;
  check(ctx: EvidenceRuleContext) {
    return ctx.definition.pocketable === false && !ctx.instance.copyOf ? 'not_pocketable' : null;
  }
}

/** Permiso especial de la prueba: rol concreto y/o llave en el inventario. */
export class AccessRule implements IEvidenceRule {
  readonly appliesTo = ['collect'] as const;
  constructor(private readonly policy: IEvidenceAccessPolicy) {}
  check(ctx: EvidenceRuleContext) {
    const r = this.policy.check(ctx.definition, 'collect', ctx.subject);
    if (r.ok) return null;
    return r.missing === 'role' ? 'requires_role' : 'requires_item';
  }
}

export class CapacityRule implements IEvidenceRule {
  readonly appliesTo = ['collect'] as const;
  check(ctx: EvidenceRuleContext) {
    return ctx.carriedWeight + ctx.definition.weight <= ctx.stats.inventoryCapacity ? null : 'inventory_full';
  }
}

export class DestroyPermissionRule implements IEvidenceRule {
  readonly appliesTo = ['destroy'] as const;
  check(ctx: EvidenceRuleContext) {
    return ctx.definition.tags.some((t) => ctx.stats.destroyableTags.has(t)) ? null : 'cannot_destroy';
  }
}

export const createDefaultEvidenceRules = (
  access: IEvidenceAccessPolicy = new RequirementAccessPolicy(),
): IEvidenceRule[] => [
  new AliveRule(),
  new PhaseRule(['collect', 'drop', 'destroy'], ['investigation']),
  new PhaseRule(['present'], ['discussion', 'voting']),
  new InRangeRule(),
  new AccessRule(access),
  new PocketableRule(),
  new CapacityRule(),
  new DestroyPermissionRule(),
];
