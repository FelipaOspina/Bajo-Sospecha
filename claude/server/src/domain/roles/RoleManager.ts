import type { IRoleAssignmentStrategy } from './assignment/RoleAssignmentStrategy.js';
import type { ModifierRegistry } from './modifiers/ModifierRegistry.js';
import type { IRoleConfigSource } from './RoleConfigSource.js';
import type { RoleConfigValidator } from './RoleConfigValidator.js';
import type { IVisibilityPolicy } from './visibility/ClueVisibilityPolicy.js';
import {
  DEFAULT_STATS,
  type IRoleQuery,
  type PlayerId,
  type PlayerStats,
  type RoleDefinition,
  type RoleSetConfig,
  type VisibilityLevel,
} from './types.js';

export interface RoleManagerDeps {
  source: IRoleConfigSource;
  validator: RoleConfigValidator;
  modifiers: ModifierRegistry;
  assignment: IRoleAssignmentStrategy;
  visibility: IVisibilityPolicy;
  baseStats?: () => PlayerStats;
}

/**
 * Orquesta el ciclo de vida de los roles en una sala:
 *   cargar set JSON → validar → asignar a jugadores → responder consultas.
 *
 * Cada decisión concreta (de dónde se lee, cómo se valida, cómo se reparte,
 * cómo se calcula la visibilidad, qué hace cada modificador) está delegada en
 * una dependencia inyectada, por lo que RoleManager no cambia al añadir reglas.
 */
export class RoleManager implements IRoleQuery {
  private config: RoleSetConfig | null = null;
  private rolesById = new Map<string, RoleDefinition>();
  private assignments = new Map<PlayerId, string>();
  private statsCache = new Map<PlayerId, PlayerStats>();

  constructor(private readonly deps: RoleManagerDeps) {}

  // ───── Carga ─────

  async loadRoleSet(roleSetId: string): Promise<RoleSetConfig> {
    return this.useRoleSet(await this.deps.source.load(roleSetId));
  }

  /** Versión síncrona para configs ya en memoria (p. ej. un escenario compilado). */
  useRoleSet(raw: unknown): RoleSetConfig {
    const config = this.deps.validator.validate(raw);
    this.config = config;
    this.rolesById = new Map(config.roles.map((r) => [r.id, r]));
    this.assignments.clear();
    this.statsCache.clear();
    return config;
  }

  get roleSet(): RoleSetConfig {
    if (!this.config) throw new Error('No hay set de roles cargado');
    return this.config;
  }

  getRole(roleId: string): RoleDefinition | undefined {
    return this.rolesById.get(roleId);
  }

  // ───── Asignación ─────

  assignRoles(players: readonly PlayerId[]): ReadonlyMap<PlayerId, string> {
    this.assignments = this.deps.assignment.assign(players, this.roleSet);
    this.statsCache.clear();
    return this.assignments;
  }

  /** Para reconexiones, partidas guardadas o roles forzados por el anfitrión. */
  setRole(playerId: PlayerId, roleId: string): void {
    if (!this.rolesById.has(roleId)) throw new Error(`Rol desconocido: ${roleId}`);
    this.assignments.set(playerId, roleId);
    this.statsCache.delete(playerId);
  }

  removePlayer(playerId: PlayerId): void {
    this.assignments.delete(playerId);
    this.statsCache.delete(playerId);
  }

  playersInTeam(team: string): PlayerId[] {
    return [...this.assignments].filter(([, r]) => this.rolesById.get(r)?.team === team).map(([p]) => p);
  }

  // ───── IRoleQuery ─────

  getRoleOf(playerId: PlayerId): RoleDefinition | undefined {
    const roleId = this.assignments.get(playerId);
    return roleId ? this.rolesById.get(roleId) : undefined;
  }

  getStats(playerId: PlayerId): PlayerStats {
    const cached = this.statsCache.get(playerId);
    if (cached) return cached;

    const stats = (this.deps.baseStats ?? DEFAULT_STATS)();
    for (const mod of this.getRoleOf(playerId)?.modifiers ?? []) {
      this.deps.modifiers.get(mod.id)?.apply(stats, mod.params ?? {});
    }
    this.statsCache.set(playerId, stats);
    return stats;
  }

  visibilityFor(playerId: PlayerId, evidenceTags: readonly string[]): VisibilityLevel {
    return this.deps.visibility.resolve(this.getRoleOf(playerId), this.getStats(playerId), evidenceTags);
  }

  knownTeammates(playerId: PlayerId): PlayerId[] {
    const role = this.getRoleOf(playerId);
    if (!role?.knowsTeammates) return [];
    return this.playersInTeam(role.team).filter((p) => p !== playerId);
  }
}
