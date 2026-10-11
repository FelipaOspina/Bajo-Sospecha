import type { EvidenceActionConfig } from '../evidence/types.js';
import type { ScenarioEvidenceSpawn, ScenarioFile, ScenarioRole } from './ScenarioAdapter.js';

const legacyAction = (kind: EvidenceActionConfig['kind'], a: any): EvidenceActionConfig => ({
  kind,
  label: String(a.action_name ?? (kind === 'delete' ? 'Borrando...' : 'Copiando...')),
  roles: [...(a.authorized_roles ?? [])],
  seconds: Number(a.channeling_time_seconds ?? 0),
});

/**
 * Convierte un "caso" escrito con el formato libre de guion (case_id, roles con
 * individual_objectives, clues_and_evidence con room y type en texto) al formato
 * de escenario. El archivo original no se modifica: se normaliza al cargarlo.
 *
 * Lo que se puede deducir de los datos, se deduce; lo que es texto narrativo
 * (victory_resolution, habilidades, sabotajes) se ignora con un aviso.
 * Mantener en sincronía con client/scripts/scenario/LegacyCaseNormalizer.gd.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

export const isLegacyCase = (raw: unknown): boolean =>
  !!raw && typeof raw === 'object' && ('case_id' in raw || 'clues_and_evidence' in raw);

export const slug = (s: string) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');

/** Palabras del campo "type" libre → tipo de pista. El orden importa. */
const TYPE_RULES: [RegExp, ScenarioEvidenceSpawn['type']][] = [
  [/audio|grabaci|voz/, 'audio'],
  [/visual|foto|imagen|captura/, 'photo'],
  [/fisic|documental|objeto|item/, 'item'],
];

export function legacyEvidenceType(raw: string): ScenarioEvidenceSpawn['type'] {
  const t = slug(raw);
  return TYPE_RULES.find(([re]) => re.test(t))?.[1] ?? 'text';
}

/** Rejilla de 3 columnas: una celda por sala; varias pistas en una sala se separan en horizontal. */
export function roomPosition(roomIndex: number, slot: number) {
  return { x: 200 + (roomIndex % 3) * 440 + slot * 70, y: 150 + Math.floor(roomIndex / 3) * 400 };
}

export function normalizeLegacyCase(raw: any): { scenario: ScenarioFile; warnings: string[] } {
  const warnings: string[] = [];
  const rooms: string[] = Array.isArray(raw.setting?.rooms) ? [...raw.setting.rooms] : [];
  const slotsUsed = new Map<number, number>();

  const findRoom = (name: string): number => {
    let i = rooms.indexOf(name);
    if (i < 0) i = rooms.findIndex((r) => slug(r).includes(slug(name)) || slug(name).includes(slug(r)));
    if (i < 0) {
      warnings.push(`la sala "${name}" no está en setting.rooms; se añade al final`);
      rooms.push(name);
      i = rooms.length - 1;
    }
    return i;
  };

  const roles: ScenarioRole[] = (raw.roles ?? []).map((r: any) => {
    if (r.hidden_ability) warnings.push(`rol ${r.role_id}: hidden_ability "${r.hidden_ability.name}" aún no tiene mecánica; se ignora`);
    return {
      id: r.role_id,
      name: r.display_name ?? r.role_id,
      description: r.starting_knowledge ?? '',
      team: slug(String(r.alignment ?? r.role_id).split('/')[0] ?? r.role_id),
      count: { min: 1, max: 1 },
      secret_objectives: [...(r.individual_objectives ?? [])],
      modifiers: [],
    } satisfies ScenarioRole;
  });
  const roleById = new Map(roles.map((r) => [r.id, r]));

  const spawns: ScenarioEvidenceSpawn[] = (raw.clues_and_evidence ?? []).map((c: any) => {
    const req = c.interaction_requirements ?? {};
    const roomIndex = findRoom(String(c.room ?? 'Sin sala'));
    const slot = slotsUsed.get(roomIndex) ?? 0;
    slotsUsed.set(roomIndex, slot + 1);
    const deleters: string[] = req.can_be_deleted ? req.deletion_action?.authorized_roles ?? [] : [];
    const backers: string[] = req.backup_action?.authorized_roles ?? [];

    // deletion_action / backup_action → acciones canalizadas (barra de progreso).
    const actions: EvidenceActionConfig[] = [];
    if (req.can_be_deleted && req.deletion_action) actions.push(legacyAction('delete', req.deletion_action));
    if (req.backup_action) actions.push(legacyAction('backup', req.backup_action));
    if (req.skill_check) warnings.push(`pista ${c.id}: skill_check (minijuego) aún no tiene mecánica; se ignora`);

    return {
      id: c.id,
      name: c.name,
      description: c.description ?? '',
      type: legacyEvidenceType(String(c.type ?? '')),
      tags: String(c.type ?? '').split('/').map((t) => slug(t)).filter(Boolean),
      medium: String(c.type ?? '').split('/').map((t) => slug(t)).filter(Boolean).join('/'),
      room: c.room,
      position: roomPosition(roomIndex, slot),
      pocketable: req.can_be_pocketed ?? true,
      weight: c.evidence_weight ?? 1,
      benefits: backers,
      harms: deleters,
      ...(actions.length ? { actions } : {}),
    } satisfies ScenarioEvidenceSpawn;
  });

  let playerCount = raw.player_count;
  if (playerCount && playerCount.max > roles.length) {
    warnings.push(`player_count.max (${playerCount.max}) se reduce a ${roles.length}: solo hay ${roles.length} roles`);
    playerCount = { min: Math.min(playerCount.min, roles.length), max: roles.length };
  }

  const flow = raw.turn_and_phase_flow ?? {};
  const confrontationRules: string = (flow.phase_2_confrontation?.rules ?? []).join(' ');
  const maxPresented = Number(/hasta\s+(\d+)\s+evidencias/i.exec(confrontationRules)?.[1] ?? 2);
  if (raw.victory_resolution) warnings.push('victory_resolution es texto libre: se usa el final por defecto (¿se acusó al culpable?)');
  if (raw.sabotage_events?.length) warnings.push(`${raw.sabotage_events.length} sabotajes ignorados (aún no hay mecánica)`);

  return {
    warnings,
    scenario: {
      format_version: 1,
      scenario_id: slug(String(raw.case_id ?? 'caso')),
      title: raw.title ?? raw.case_id,
      description: raw.setting?.crisis_summary ?? '',
      player_count: playerCount,
      culprit_roles: (raw.roles ?? []).filter((r: any) => /culpable/i.test(r.alignment ?? '')).map((r: any) => r.role_id),
      phase_durations: {
        ...(flow.phase_1_exploration?.duration_seconds ? { investigation: flow.phase_1_exploration.duration_seconds } : {}),
        ...(flow.phase_2_confrontation?.duration_seconds ? { discussion: flow.phase_2_confrontation.duration_seconds } : {}),
      },
      // "Se vota quién es despedido": una opción por personaje, con su recuento de votos.
      trial: {
        max_presented_per_player: maxPresented,
        allow_player_accusation: false,
        public_tally: true,
        options: roles.map((r) => ({ id: `acusar_${slug(r.id)}`, label: `Acusar a ${r.name}`, accuses_role: r.id })),
      },
      roles,
      evidence_spawns: spawns,
    },
  };
}
