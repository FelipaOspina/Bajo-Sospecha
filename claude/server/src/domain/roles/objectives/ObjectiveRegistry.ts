import type { PlayerId } from '../types.js';

/** Vista mínima del mundo que necesitan los objetivos para evaluarse. */
export interface ObjectiveWorldView {
  players(): PlayerId[];
  teamOf(playerId: PlayerId): string | undefined;
  /** Etiquetas de cada prueba en el inventario del jugador. */
  inventoryTags(playerId: PlayerId): string[][];
  /** Jugadores señalados por el veredicto del juicio (vacío si no hubo). */
  accusedPlayers(): PlayerId[];
  /** Opción ganadora del juicio, o null (empate / sin votos). */
  verdict(): string | null;
  /** Etiquetas de cada prueba expuesta en la mesa pública. */
  revealedTags(): string[][];
}

export interface IObjectiveHandler {
  readonly type: string;
  validate(params: Record<string, unknown>): string | null;
  isComplete(playerId: PlayerId, params: Record<string, unknown>, world: ObjectiveWorldView): boolean;
}

export class ObjectiveRegistry {
  private handlers = new Map<string, IObjectiveHandler>();
  register(h: IObjectiveHandler): this { this.handlers.set(h.type, h); return this; }
  get(type: string) { return this.handlers.get(type); }
  has(type: string) { return this.handlers.has(type); }
}

const countWithTag = (pieces: string[][], tags: string[]) =>
  pieces.filter((p) => p.some((t) => tags.includes(t))).length;

export const CollectEvidence: IObjectiveHandler = {
  type: 'collect_evidence',
  validate: (p) =>
    Array.isArray(p.tags) && Number.isInteger(p.count) ? null : 'requiere tags: string[] y count: entero',
  isComplete: (id, p, w) => countWithTag(w.inventoryTags(id), p.tags as string[]) >= (p.count as number),
};

export const KeepEvidenceHidden: IObjectiveHandler = {
  type: 'keep_evidence_hidden',
  validate: (p) =>
    Array.isArray(p.tags) && Number.isInteger(p.maxCollectedByOthers) ? null : 'requiere tags y maxCollectedByOthers',
  isComplete: (id, p, w) => {
    const myTeam = w.teamOf(id);
    const others = w.players().filter((o) => w.teamOf(o) !== myTeam);
    const total = others.reduce((acc, o) => acc + countWithTag(w.inventoryTags(o), p.tags as string[]), 0);
    return total <= (p.maxCollectedByOthers as number);
  },
};

export const AccuseCulprit: IObjectiveHandler = {
  type: 'accuse_culprit',
  validate: () => null,
  isComplete: (_id, p, w) => {
    const culprits = (p.culpritTeam as string | undefined) ?? 'culpables';
    return w.accusedPlayers().some((a) => w.teamOf(a) === culprits);
  },
};

/** Se cumple si el juicio termina en alguna de las decisiones indicadas. */
export const VerdictObjective: IObjectiveHandler = {
  type: 'verdict',
  validate: (p) => (Array.isArray(p.options) && p.options.length ? null : 'requiere options: string[]'),
  isComplete: (_id, p, w) => {
    const v = w.verdict();
    return v !== null && (p.options as string[]).includes(v);
  },
};

/** Se cumple si en la mesa pública hay al menos `count` pruebas con esas etiquetas. */
export const RevealEvidence: IObjectiveHandler = {
  type: 'reveal_evidence',
  validate: (p) => (Array.isArray(p.tags) ? null : 'requiere tags: string[] (y count opcional)'),
  isComplete: (_id, p, w) => countWithTag(w.revealedTags(), p.tags as string[]) >= ((p.count as number | undefined) ?? 1),
};

/** Objetivo narrativo: se muestra al jugador pero no se evalúa automáticamente. */
export const Narrative: IObjectiveHandler = {
  type: 'narrative',
  validate: () => null,
  isComplete: () => false,
};

export const createDefaultObjectiveRegistry = () =>
  new ObjectiveRegistry()
    .register(CollectEvidence)
    .register(KeepEvidenceHidden)
    .register(AccuseCulprit)
    .register(VerdictObjective)
    .register(RevealEvidence)
    .register(Narrative);
