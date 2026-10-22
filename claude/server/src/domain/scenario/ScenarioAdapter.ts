import type { EvidenceAccess, EvidenceActionConfig, EvidenceDefinition, EvidenceMapConfig, InteractableConfig, Vec2 } from '../evidence/types.js';
import type { ObjectiveDefinition, RoleDefinition, RoleSetConfig, VisibilityRule } from '../roles/types.js';
import { KNOWN_POWERS } from '../roles/RoleConfigValidator.js';
import { createDefaultConditionRegistry, type Condition, type EndingConfig, type TrialConfig } from '../trial/index.js';
import { isLegacyCase, normalizeLegacyCase } from './LegacyCaseNormalizer.js';

/**
 * Formato de escenario (shared/config/scenarios/*.json). Es el mismo archivo que
 * lee el ScenarioManager de Godot; aquí se traduce a las configuraciones que ya
 * consumen RoleManager y EvidenceSystem, así ninguno de los dos cambia.
 */
export const EVIDENCE_TYPES = ['text', 'audio', 'photo', 'item'] as const;
export type EvidenceType = (typeof EVIDENCE_TYPES)[number];

export interface ScenarioObjective {
  id?: string;
  description: string;
  type?: string;
  params?: Record<string, unknown>;
}

export interface ScenarioRole {
  id: string;
  name: string;
  description?: string;
  team?: string;
  count?: { min: number; max: number };
  weight?: number;
  knows_teammates?: boolean;
  /** Solo entra en el reparto con al menos estos jugadores. */
  min_players?: number;
  /** Poderes con mecánica: "silence" (silenciar), "escort" (escoltar). */
  powers?: string[];
  /** Roles a los que siempre tiene motivo para silenciar. */
  motive_targets?: string[];
  secret_objectives: (string | ScenarioObjective)[];
  visibility?: RoleDefinition['visibility'];
  modifiers?: RoleDefinition['modifiers'];
}

export interface ScenarioEvidenceSpawn {
  id: string;
  name: string;
  description: string;
  type: EvidenceType;
  /** Aspecto exterior, visible aunque no se conozcan los detalles (p. ej. "digital/critica",
   *  "documental/fisico"). El cliente elige con él el marco del visor. Por defecto, type. */
  medium?: string;
  position: Vec2 | [number, number];
  radius?: number;
  room?: string;
  pocketable?: boolean;
  weight?: number;
  tags?: string[];
  benefits?: string[];
  harms?: string[];
  content?: Record<string, unknown>;
  /** Permisos especiales: { view?: {roles?, items?}, collect?: {roles?, items?} } */
  requires?: EvidenceAccess;
  /** Acciones canalizadas: [{ kind: "delete" | "backup", label, roles, seconds }] */
  actions?: EvidenceActionConfig[];
  /** Roles a los que incrimina (móvil para silenciar a quien la lleve). */
  incriminates?: string[];
}

export interface ScenarioFile {
  format_version?: number;
  scenario_id: string;
  title: string;
  description?: string;
  player_count?: { min: number; max: number };
  /** Duración de fases en segundos. */
  phase_durations?: Partial<Record<'briefing' | 'investigation' | 'emergency' | 'discussion' | 'voting', number>>;
  /** Asambleas de emergencia: máximo por partida y qué expulsión termina la partida con qué opción del juicio. */
  emergency?: EmergencyConfig;
  /** Roles culpables. Sin `endings`, genera el final por defecto "¿se acusó al culpable?". */
  culprit_roles?: string[];
  trial?: TrialConfig;
  endings?: EndingConfig[];
  roles: ScenarioRole[];
  evidence_spawns: ScenarioEvidenceSpawn[];
}

export interface EmergencyConfig {
  /** Por defecto 3. */
  max_per_match?: number;
  /** Rol expulsado → opción del juicio que se da por votada (fin inmediato). */
  expel_ends_game?: Record<string, string>;
}

/** Punto del mapa para las misiones de fantasma. */
export interface GhostTaskPoint {
  position: Vec2;
  label: string;
}

export interface CompiledScenario {
  scenario: ScenarioFile;
  roleSet: RoleSetConfig;
  map: EvidenceMapConfig;
  trial?: TrialConfig;
  endings: EndingConfig[];
  phaseDurationsMs: Record<string, number>;
  emergency: { maxPerMatch: number; expelEndsGame: Record<string, string> };
  /** Sitios de las pistas, para repartir misiones de fantasma. */
  ghostTaskPoints: GhostTaskPoint[];
  /** Avisos no bloqueantes (campos ignorados, valores ajustados al normalizar...). */
  warnings: string[];
}

export class ScenarioError extends Error {
  constructor(public readonly problems: string[]) {
    super(`Escenario inválido:\n - ${problems.join('\n - ')}`);
  }
}

/** Etiquetas automáticas que permiten a objetivos y visibilidad referirse a pistas y roles. */
export const scenarioTags = {
  evidence: (id: string) => `pista:${id}`,
  type: (t: string) => `tipo:${t}`,
  benefits: (roleId: string) => `beneficia:${roleId}`,
  harms: (roleId: string) => `perjudica:${roleId}`,
};

export function toVec2(p: unknown): Vec2 | null {
  if (Array.isArray(p) && p.length === 2 && typeof p[0] === 'number' && typeof p[1] === 'number') {
    return { x: p[0], y: p[1] };
  }
  const o = p as Vec2 | null;
  return o && typeof o.x === 'number' && typeof o.y === 'number' ? { x: o.x, y: o.y } : null;
}

/**
 * Valida y traduce un escenario. Reglas por defecto:
 *  - Un rol sin `team` va a su propio equipo; sin `count`, es exactamente 1.
 *  - Un objetivo en texto plano es 'narrative' (se muestra, no se evalúa solo).
 *  - Cada pista recibe etiquetas pista:<id>, tipo:<type>, beneficia:<rol>, perjudica:<rol>.
 *  - Un rol sin `visibility` ve en parcial, salvo las pistas que le benefician, que ve completas.
 *  - Cada pista aparece en un punto propio (evidence_spot) en su posición.
 */
export function compileScenario(input: unknown): CompiledScenario {
  const p: string[] = [];
  const warnings: string[] = [];
  let s = input as ScenarioFile;
  if (isLegacyCase(input)) {
    const n = normalizeLegacyCase(input);
    s = n.scenario;
    warnings.push(...n.warnings);
  }
  if (!s || typeof s !== 'object') throw new ScenarioError(['el escenario no es un objeto']);
  if (typeof s.scenario_id !== 'string' || !/^[a-z0-9_-]+$/i.test(s.scenario_id)) p.push('scenario_id requerido (letras, números, _ o -)');
  if (typeof s.title !== 'string' || !s.title) p.push('title requerido');
  if (!Array.isArray(s.roles) || s.roles.length === 0) p.push('roles debe ser una lista no vacía');
  if (!Array.isArray(s.evidence_spawns)) p.push('evidence_spawns debe ser una lista');
  if (p.length) throw new ScenarioError(p);

  const roleIds = new Set<string>();
  for (const r of s.roles) {
    if (!r.id || roleIds.has(r.id)) p.push(`rol "${r.id}": id vacío o duplicado`);
    if (!r.name) p.push(`rol "${r.id}": name requerido`);
    if (!Array.isArray(r.secret_objectives)) p.push(`rol "${r.id}": secret_objectives debe ser una lista`);
    roleIds.add(r.id);
  }

  const evidenceIds = new Set<string>();
  const definitions: EvidenceDefinition[] = [];
  const interactables: InteractableConfig[] = [];
  for (const e of s.evidence_spawns) {
    const where = `pista "${e.id}"`;
    if (!e.id || evidenceIds.has(e.id)) p.push(`${where}: id vacío o duplicado`);
    evidenceIds.add(e.id);
    if (!e.name) p.push(`${where}: name requerido`);
    if (!EVIDENCE_TYPES.includes(e.type)) p.push(`${where}: type "${e.type}" no es ${EVIDENCE_TYPES.join(' | ')}`);
    const position = toVec2(e.position);
    if (!position) p.push(`${where}: position debe ser {x, y} o [x, y]`);
    for (const ref of [...(e.benefits ?? []), ...(e.harms ?? []), ...(e.incriminates ?? [])]) {
      if (!roleIds.has(ref)) p.push(`${where}: referencia a rol inexistente "${ref}"`);
    }
    for (const req of [e.requires?.view, e.requires?.collect]) {
      for (const r of req?.roles ?? []) if (!roleIds.has(r)) p.push(`${where}: requires con rol inexistente "${r}"`);
    }
    for (const a of e.actions ?? []) {
      if (a.kind !== 'delete' && a.kind !== 'backup') p.push(`${where}: acción "${a.kind}" no es delete | backup`);
      if (!(a.seconds >= 0)) p.push(`${where}: acción ${a.kind} necesita seconds >= 0`);
      if (!Array.isArray(a.roles) || !a.roles.length) p.push(`${where}: acción ${a.kind} necesita roles`);
      for (const r of a.roles ?? []) if (!roleIds.has(r)) p.push(`${where}: acción ${a.kind} con rol inexistente "${r}"`);
    }
    if (!position) continue;

    definitions.push({
      id: e.id,
      name: e.name,
      description: e.description ?? '',
      weight: e.weight ?? 1,
      pocketable: e.pocketable ?? true,
      medium: e.medium ?? e.type,
      ...(e.content ? { content: e.content } : {}),
      ...(e.requires ? { access: e.requires } : {}),
      ...(e.actions?.length ? { actions: e.actions } : {}),
      ...(e.incriminates?.length ? { incriminates: [...e.incriminates] } : {}),
      tags: [
        ...(e.tags ?? []),
        scenarioTags.evidence(e.id),
        scenarioTags.type(e.type),
        ...(e.benefits ?? []).map(scenarioTags.benefits),
        ...(e.harms ?? []).map(scenarioTags.harms),
      ],
    });
    interactables.push({ id: `spawn_${e.id}`, type: 'evidence_spot', position, radius: e.radius ?? 48, evidenceId: e.id });
  }
  // ───── Juicio y finales ─────
  const optionIds = new Set(['abstain']);
  for (const o of s.trial?.options ?? []) {
    if (!o.id || optionIds.has(o.id)) p.push(`opción de juicio "${o.id}": id vacío o duplicado`);
    if (o.accuses_role && !roleIds.has(o.accuses_role)) p.push(`opción "${o.id}": accuses_role inexistente "${o.accuses_role}"`);
    optionIds.add(o.id);
  }
  for (const r of s.culprit_roles ?? []) if (!roleIds.has(r)) p.push(`culprit_roles: rol inexistente "${r}"`);
  for (const r of s.roles) {
    if (r.min_players !== undefined && !Number.isInteger(r.min_players)) p.push(`rol "${r.id}": min_players debe ser entero`);
    for (const pw of r.powers ?? []) if (!KNOWN_POWERS.includes(pw)) p.push(`rol "${r.id}": poder desconocido "${pw}"`);
    for (const t of r.motive_targets ?? []) if (!roleIds.has(t)) p.push(`rol "${r.id}": motive_targets con rol inexistente "${t}"`);
  }
  for (const [role, option] of Object.entries(s.emergency?.expel_ends_game ?? {})) {
    if (!roleIds.has(role)) p.push(`emergency.expel_ends_game: rol inexistente "${role}"`);
    if (!optionIds.has(option)) p.push(`emergency.expel_ends_game: opción inexistente "${option}"`);
  }
  const teams = new Set(s.roles.map((r) => r.team ?? r.id));
  const conditions = createDefaultConditionRegistry();
  for (const end of s.endings ?? []) {
    const where = `final "${end.id}"`;
    p.push(...conditions.validate(end.when).map((m) => `${where}: ${m}`));
    p.push(...conditionRefs(end.when, { roles: roleIds, evidence: evidenceIds, options: optionIds }).map((m) => `${where}: ${m}`));
    for (const r of end.winners?.roles ?? []) if (!roleIds.has(r)) p.push(`${where}: ganador con rol inexistente "${r}"`);
    for (const t of end.winners?.teams ?? []) if (!teams.has(t)) p.push(`${where}: ganador con equipo inexistente "${t}"`);
  }

  for (const e of s.evidence_spawns) {
    for (const req of [e.requires?.view, e.requires?.collect]) {
      for (const i of req?.items ?? []) if (!evidenceIds.has(i)) p.push(`pista "${e.id}": requires con ítem inexistente "${i}"`);
    }
  }
  if (p.length) throw new ScenarioError(p);

  const roles: RoleDefinition[] = s.roles.map((r) => ({
    id: r.id,
    name: r.name,
    team: r.team ?? r.id,
    description: r.description ?? '',
    count: r.count ?? { min: 1, max: 1 },
    weight: r.weight ?? 0,
    knowsTeammates: r.knows_teammates ?? false,
    ...(r.min_players !== undefined ? { minPlayers: r.min_players } : {}),
    ...(r.powers?.length ? { powers: [...r.powers] } : {}),
    ...(r.motive_targets?.length ? { motiveTargets: [...r.motive_targets] } : {}),
    visibility: r.visibility ?? {
      default: 'partial',
      rules: [{ tags: [scenarioTags.benefits(r.id)], level: 'full' } satisfies VisibilityRule],
    },
    modifiers: r.modifiers ?? [],
    objectives: r.secret_objectives.map((o, i): ObjectiveDefinition =>
      typeof o === 'string'
        ? { id: `obj_${i + 1}`, type: 'narrative', description: o }
        : { id: o.id ?? `obj_${i + 1}`, type: o.type ?? 'narrative', description: o.description, params: o.params }),
  }));

  const count = s.player_count ?? {
    min: roles.reduce((a, r) => a + r.count.min, 0),
    max: roles.reduce((a, r) => a + r.count.max, 0),
  };

  return {
    scenario: s,
    roleSet: { id: s.scenario_id, name: s.title, version: s.format_version ?? 1, minPlayers: count.min, maxPlayers: count.max, roles },
    map: { mapId: s.scenario_id, evidence: definitions, interactables },
    trial: s.trial,
    endings: withSilenceEnding(s.endings?.length ? s.endings : defaultEndings(s, roles), s, roles),
    phaseDurationsMs: Object.fromEntries(Object.entries(s.phase_durations ?? {}).map(([k, v]) => [k, (v as number) * 1000])),
    emergency: { maxPerMatch: s.emergency?.max_per_match ?? 3, expelEndsGame: { ...(s.emergency?.expel_ends_game ?? {}) } },
    ghostTaskPoints: s.evidence_spawns.flatMap((e, i) => {
      const position = toVec2(e.position);
      return position ? [{ position, label: `${GHOST_TASK_VERBS[i % GHOST_TASK_VERBS.length]} (${e.room ?? 'oficina'})` }] : [];
    }),
    warnings,
  };
}

/** Acciones que un fantasma hace "desde el más allá" en el sitio de una pista. */
const GHOST_TASK_VERBS = [
  'Hacer parpadear las luces',
  'Revolver los papeles',
  'Encender una pantalla',
  'Abrir un cajón',
  'Empujar una silla',
  'Tirar una carpeta al suelo',
];

/** Id del final "los culpables vivos igualan o superan al resto". */
export const SILENCE_ENDING_ID = 'silencio_total';

/**
 * Si el escenario no trae el final silencio_total y tiene roles con poder "silence",
 * se añade uno: ganan esos roles (o los culprit_roles).
 */
function withSilenceEnding(endings: EndingConfig[], s: ScenarioFile, roles: RoleDefinition[]): EndingConfig[] {
  if (endings.some((e) => e.id === SILENCE_ENDING_ID)) return endings;
  const killers = s.culprit_roles?.length ? s.culprit_roles : roles.filter((r) => r.powers?.includes('silence')).map((r) => r.id);
  if (!roles.some((r) => r.powers?.includes('silence')) || !killers.length) return endings;
  return [...endings, {
    id: SILENCE_ENDING_ID,
    title: 'Silencio total',
    description: 'Los culpables que quedan en pie ya igualan al resto: nadie más se atreve a hablar.',
    when: { forced: SILENCE_ENDING_ID },
    winners: { roles: killers },
  }];
}

/** Final por defecto si hay culprit_roles y no hay endings: ¿el veredicto señaló al culpable? */
function defaultEndings(s: ScenarioFile, roles: RoleDefinition[]): EndingConfig[] {
  const culprits = s.culprit_roles ?? [];
  if (!culprits.length) return [];
  const innocentTeams = [...new Set(roles.filter((r) => !culprits.includes(r.id)).map((r) => r.team))];
  return [
    { id: 'culpable_descubierto', title: 'El culpable ha sido descubierto', when: { accused_role: culprits }, winners: { teams: innocentTeams } },
    { id: 'culpable_impune', title: 'El culpable queda impune', when: { not: { accused_role: culprits } }, winners: { roles: culprits } },
  ];
}

/** Comprueba que las condiciones solo nombran pistas, roles y opciones que existen. */
function conditionRefs(c: Condition, known: { roles: Set<string>; evidence: Set<string>; options: Set<string> }): string[] {
  const out: string[] = [];
  const list = (v: unknown) => (typeof v === 'string' ? [v] : Array.isArray(v) ? v.map(String) : []);
  for (const [k, v] of Object.entries(c ?? {})) {
    if (k === 'all' || k === 'any') (v as Condition[]).forEach((n) => out.push(...conditionRefs(n, known)));
    else if (k === 'not') out.push(...conditionRefs(v as Condition, known));
    else if (k === 'verdict') list(v).filter((id) => !known.options.has(id)).forEach((id) => out.push(`verdict: opción inexistente "${id}"`));
    else if (k === 'accused_role') list(v).filter((id) => !known.roles.has(id)).forEach((id) => out.push(`accused_role: rol inexistente "${id}"`));
    else if (k.startsWith('revealed_') || k.startsWith('destroyed_')) {
      if (k !== 'revealed_count') list(v).filter((id) => !known.evidence.has(id)).forEach((id) => out.push(`${k}: pista inexistente "${id}"`));
    } else if (k === 'held_count') {
      const o = v as { role: string };
      if (!known.roles.has(o.role)) out.push(`held_count: rol inexistente "${o.role}"`);
    } else if (k === 'held_by_role') {
      const o = v as { role: string; evidence: string };
      if (!known.roles.has(o.role)) out.push(`held_by_role: rol inexistente "${o.role}"`);
      if (!known.evidence.has(o.evidence)) out.push(`held_by_role: pista inexistente "${o.evidence}"`);
    }
  }
  return out;
}
