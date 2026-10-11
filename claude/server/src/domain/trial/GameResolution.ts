import type { PlayerId, Resolution } from '../../../../shared/protocol/protocol.js';
import type { ObjectiveRegistry, ObjectiveWorldView } from '../roles/objectives/ObjectiveRegistry.js';
import type { RoleManager } from '../roles/RoleManager.js';
import type { ConditionRegistry } from './ConditionRegistry.js';
import type { Verdict } from './TrialSystem.js';
import type { EndingConfig, ResolutionContext } from './types.js';

export interface ResolutionInput {
  verdict: Verdict;
  context: ResolutionContext;
  objectiveWorld: ObjectiveWorldView;
  players: { id: PlayerId; name: string }[];
}

/**
 * Calcula el desenlace:
 *  - Con `endings` en el escenario: se evalúan TODOS; cada final cumplido suma
 *    sus ganadores (pueden coexistir, p. ej. CTO e Inversor).
 *  - Sin endings: gana quien completó al menos un objetivo evaluable de su rol.
 * Además informa del estado de cada objetivo secreto (se revela al final).
 */
export class GameResolution {
  constructor(
    private readonly roles: RoleManager,
    private readonly objectives: ObjectiveRegistry,
    private readonly conditions: ConditionRegistry,
    private readonly endings: EndingConfig[] = [],
  ) {}

  resolve(input: ResolutionInput): Resolution {
    const { verdict, context, objectiveWorld } = input;

    const objectiveStatus = (p: PlayerId) =>
      (this.roles.getRoleOf(p)?.objectives ?? []).map((o) => ({
        id: o.id,
        description: o.description,
        type: o.type,
        completed: this.objectives.get(o.type)?.isComplete(p, o.params ?? {}, objectiveWorld) ?? false,
      }));

    const winnersOf = (e: EndingConfig) => input.players.filter((p) => {
      const role = this.roles.getRoleOf(p.id);
      return role && (e.winners.roles?.includes(role.id) || e.winners.teams?.includes(role.team));
    }).map((p) => p.id);
    // Un final solo cuenta si se cumple y alguien de la sala lo gana (p. ej. sin Empleados no hay final de Empleados).
    const matched = this.endings.filter((e) => this.conditions.evaluate(e.when, context) && winnersOf(e).length > 0);
    const winners = new Set<PlayerId>();
    if (this.endings.length) {
      matched.forEach((e) => winnersOf(e).forEach((p) => winners.add(p)));
    } else {
      for (const p of input.players) {
        if (objectiveStatus(p.id).some((o) => o.type !== 'narrative' && o.completed)) winners.add(p.id);
      }
    }

    return {
      verdict: { optionId: verdict.optionId, label: verdict.label, tally: verdict.tally, accused: verdict.accused },
      endings: matched.map((e) => ({ id: e.id, title: e.title, description: e.description ?? '' })),
      winners: [...winners],
      players: input.players.map((p) => {
        const role = this.roles.getRoleOf(p.id);
        return {
          id: p.id,
          name: p.name,
          roleId: role?.id ?? '',
          roleName: role?.name ?? '',
          team: role?.team ?? '',
          won: winners.has(p.id),
          objectives: objectiveStatus(p.id).map(({ id, description, completed }) => ({ id, description, completed })),
        };
      }),
      revealedEvidence: [...context.revealed],
    };
  }
}
