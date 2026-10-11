import type { IRandom } from '../../../core/Random.js';
import type { PlayerId, RoleSetConfig } from '../types.js';

export interface IRoleAssignmentStrategy {
  assign(players: readonly PlayerId[], config: RoleSetConfig): Map<PlayerId, string>;
}

/**
 * 1. Cubre los mínimos de cada rol.
 * 2. Rellena el resto por sorteo ponderado (weight) entre roles con hueco (count.max).
 * 3. Baraja jugadores para que el orden de entrada no determine el rol.
 */
export class WeightedRoleAssignment implements IRoleAssignmentStrategy {
  constructor(private readonly rng: IRandom) {}

  assign(players: readonly PlayerId[], config: RoleSetConfig): Map<PlayerId, string> {
    const n = players.length;
    if (n < config.minPlayers || n > config.maxPlayers) {
      throw new Error(`El set "${config.id}" admite ${config.minPlayers}-${config.maxPlayers} jugadores (hay ${n})`);
    }

    const pool: string[] = [];
    const used = new Map<string, number>();
    for (const role of config.roles) {
      for (let i = 0; i < role.count.min; i++) pool.push(role.id);
      used.set(role.id, role.count.min);
    }

    while (pool.length < n) {
      const candidates = config.roles.filter((r) => (r.weight ?? 0) > 0 && used.get(r.id)! < r.count.max);
      const total = candidates.reduce((acc, r) => acc + (r.weight ?? 0), 0);
      if (total === 0) throw new Error(`No hay roles disponibles para completar ${n} jugadores`);
      let roll = this.rng.next() * total;
      const pick = candidates.find((r) => (roll -= r.weight ?? 0) < 0) ?? candidates[candidates.length - 1]!;
      pool.push(pick.id);
      used.set(pick.id, used.get(pick.id)! + 1);
    }

    const shuffled = [...players];
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(this.rng.next() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j]!, shuffled[i]!];
    }
    return new Map(shuffled.map((p, i) => [p, pool[i]!]));
  }
}
