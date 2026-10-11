import type {
  ChannelView,
  EvidenceView,
  GameEvent,
  InteractableView,
  PlayerId,
  PrivatePlayerState,
  PublicPlayerState,
  Resolution,
  RoomSnapshot,
  TrialState,
} from '../../../shared/protocol/protocol.js';
import type { EvidenceSystem } from '../domain/evidence/EvidenceSystem.js';
import type { ObjectiveRegistry, ObjectiveWorldView } from '../domain/roles/objectives/ObjectiveRegistry.js';
import type { RoleManager } from '../domain/roles/RoleManager.js';
import type { TrialSystem } from '../domain/trial/TrialSystem.js';
import type { ChannelSystem } from '../domain/evidence/ChannelSystem.js';
import type { AbilitySystem } from '../domain/abilities/AbilitySystem.js';

/** Hasta dónde se ve la barra de progreso de otro jugador. */
export const CHANNEL_VISIBLE_RADIUS = 500;
import type { RoomState } from './RoomState.js';

/**
 * Convierte estado autoritativo en lo que UN jugador tiene derecho a saber.
 * Es el único punto donde se aplica el "fog of war" informativo: roles ajenos,
 * detalles de pruebas según visibilidad, inventarios privados.
 */
export class StateProjector {
  constructor(
    private readonly state: RoomState,
    private readonly roles: RoleManager,
    private readonly objectives: ObjectiveRegistry,
    private readonly evidence: EvidenceSystem,
    private readonly world: ObjectiveWorldView,
    private readonly trial: TrialSystem,
    private readonly resolution: () => Resolution | null,
    private readonly channels: ChannelSystem,
    private readonly abilities?: AbilitySystem,
  ) {}

  /** ¿Ve el receptor lo que hace este jugador? (él mismo, o está cerca). Las habilidades
   *  alargan lo que ve el receptor (orejas largas, ojos de gato) o acortan lo que se ve
   *  del actor (camuflaje, antifaz). */
  canWatch(viewer: PlayerId, actor: PlayerId): boolean {
    if (viewer === actor) return true;
    const a = this.state.players.get(viewer)?.position;
    const b = this.state.players.get(actor)?.position;
    const radius = CHANNEL_VISIBLE_RADIUS
      * (this.abilities?.effects(viewer).watchRadius ?? 1)
      * (this.abilities?.effects(actor).stealthRadius ?? 1);
    return !!a && !!b && radius > 0 && Math.hypot(a.x - b.x, a.y - b.y) <= radius;
  }

  /** Engaño (zorro): los demás ven una acción neutra con otra etiqueta. */
  private disguised(viewer: PlayerId, actor: PlayerId, channel: ChannelView): ChannelView {
    const disguise = viewer !== actor ? this.abilities?.effects(actor).disguise : undefined;
    return disguise ? { ...channel, kind: 'backup', label: disguise } : channel;
  }

  snapshotFor(viewer: PlayerId): RoomSnapshot {
    const teammates = new Set(this.roles.knownTeammates(viewer));
    const players: PublicPlayerState[] = [...this.state.players.values()].map((p) => ({
      id: p.id,
      name: p.name,
      position: p.position,
      connected: p.connected,
      ready: p.ready,
      alive: p.alive,
      inventoryCount: this.evidence.inventoryOf(p.id).length,
      ...(p.skinId ? { skinId: p.skinId } : {}),
      ...(p.look && Object.keys(p.look).length ? { look: { ...p.look } } : {}),
      ...this.channelOf(viewer, p.id),
      ...((p.id === viewer || teammates.has(p.id) || this.state.phase === 'results')
        ? { roleId: this.roles.getRoleOf(p.id)?.id }
        : {}),
    }));

    const interactables: InteractableView[] = this.evidence.listInteractables().map((i) => ({
      id: i.id,
      type: i.type,
      position: i.position,
      radius: i.radius,
      contents: i.contents().map((id) => this.evidenceView(viewer, id)).filter((v): v is EvidenceView => v !== null),
    }));

    return {
      version: this.state.version,
      phase: this.state.phase,
      lobby: {
        code: this.state.code,
        visibility: this.state.visibility,
        hostId: [...this.state.players.keys()][0] ?? null,
        minPlayers: this.roles.roleSet.minPlayers,
        maxPlayers: this.roles.roleSet.maxPlayers,
        startsAt: this.state.startsAt,
      },
      phaseEndsAt: this.state.phaseEndsAt,
      players,
      interactables,
      you: this.privateState(viewer),
      trial: this.trialState(viewer),
    };
  }

  private channelOf(viewer: PlayerId, actor: PlayerId): { channel?: PublicPlayerState['channel'] } {
    const c = this.channels.get(actor);
    if (!c || !this.canWatch(viewer, actor)) return {};
    return { channel: this.disguised(viewer, actor, { kind: c.kind, label: c.label, startedAt: c.startedAt, durationMs: c.durationMs }) };
  }

  /** La mesa y las opciones son públicas; el voto de cada uno solo lo ve él. */
  private trialState(viewer: PlayerId): TrialState {
    return {
      deck: [...this.trial.deck],   // copia: lastSent no debe compartir el array vivo o el delta no verá cambios
      options: this.trial.options(),
      voted: this.trial.voters(),
      myVote: this.trial.voteOf(viewer),
      maxPresentedPerPlayer: this.trial.maxPresentedPerPlayer,
      ...(this.trial.publicTally ? { tally: this.trial.verdict().tally } : {}),
      resolution: this.resolution(),
    };
  }

  /** Vista completa e igual para todos (pruebas expuestas en la mesa). */
  publicEvidenceView(instanceId: string): EvidenceView {
    const def = this.evidence.definitionOf(instanceId)!;
    return {
      instanceId,
      visibility: 'full',
      definitionId: def.id,
      name: def.name,
      description: def.description,
      tags: def.tags,
      pocketable: def.pocketable ?? true,
      ...(def.medium ? { medium: def.medium } : {}),
      ...(def.content ? { content: def.content } : {}),
      ...(this.evidence.getInstance(instanceId)?.copyOf ? { isCopy: true } : {}),
    };
  }

  evidenceView(viewer: PlayerId, instanceId: string, minimum?: 'partial'): EvidenceView | null {
    let level = this.evidence.visibilityOf(viewer, instanceId);
    if (minimum && level === 'hidden') level = minimum;
    if (level === 'hidden') return null;
    const def = this.evidence.definitionOf(instanceId)!;
    const lock = this.lockFor(viewer, instanceId);
    const medium = def.medium ? { medium: def.medium } : {};
    if (level === 'partial') return { instanceId, visibility: 'partial', ...medium, ...lock, ...this.actionsFor(viewer, instanceId) };
    return {
      instanceId,
      visibility: 'full',
      definitionId: def.id,
      name: def.name,
      description: def.description,
      tags: def.tags,
      pocketable: def.pocketable ?? true,
      ...medium,
      ...(def.content ? { content: def.content } : {}),
      ...lock,
      ...this.actionsFor(viewer, instanceId),
    };
  }

  private actionsFor(viewer: PlayerId, instanceId: string): Pick<EvidenceView, 'actions' | 'isCopy'> {
    const actions = this.channels.availableActions(viewer, instanceId).map(({ kind, label, seconds }) => ({ kind, label, seconds }));
    return {
      ...(actions.length ? { actions } : {}),
      ...(this.evidence.getInstance(instanceId)?.copyOf ? { isCopy: true } : {}),
    };
  }

  /** Qué permiso le falta al receptor. Solo se nombran ítems (llaves), nunca roles. */
  private lockFor(viewer: PlayerId, instanceId: string): Pick<EvidenceView, 'locked' | 'requiredItems'> {
    if (this.evidence.getInstance(instanceId)?.location.kind === 'inventory') return {};
    for (const action of ['view', 'collect'] as const) {
      const r = this.evidence.accessOf(viewer, instanceId, action);
      if (r.ok) continue;
      const names = (r.missingItems ?? []).map((id) => this.evidence.catalogName(id));
      return { locked: action, ...(names.length ? { requiredItems: names } : {}) };
    }
    return {};
  }

  /** Adapta un evento global al receptor (p. ej. oculta qué prueba se recogió). */
  projectEvent(viewer: PlayerId, event: GameEvent): GameEvent | null {
    if (event.e === 'evidence_collected' && event.evidence) {
      return event.by === viewer
        ? { ...event, evidence: this.evidenceView(viewer, event.evidence.instanceId) ?? undefined }
        : { e: 'evidence_collected', by: event.by, interactableId: event.interactableId };
    }
    if ((event.e === 'channel_started' || event.e === 'channel_finished') && !this.canWatch(viewer, event.by)) return null;
    if (event.e === 'channel_started') return { ...event, channel: this.disguised(viewer, event.by, event.channel) };
    if (event.e === 'evidence_presented') {
      return { ...event, evidence: this.publicEvidenceView(event.evidence.instanceId) };
    }
    return event;
  }

  private privateState(viewer: PlayerId): PrivatePlayerState | null {
    const role = this.roles.getRoleOf(viewer);
    if (!role) return null;
    return {
      roleId: role.id,
      team: role.team,
      knownTeammates: this.roles.knownTeammates(viewer),
      inventory: this.evidence.inventoryOf(viewer).map((i) => this.evidenceView(viewer, i.instanceId)!),
      objectives: role.objectives.map((o) => ({
        id: o.id,
        description: o.description,
        completed: this.objectives.get(o.type)?.isComplete(viewer, o.params ?? {}, this.world) ?? false,
      })),
      ...this.abilityState(viewer),
    };
  }

  private abilityState(viewer: PlayerId): Pick<PrivatePlayerState, 'ability' | 'speedMultiplier'> {
    const ability = this.abilities?.stateFor(viewer);
    if (!ability) return {};
    return { ability, speedMultiplier: Math.round(this.abilities!.effects(viewer).speed * 1000) / 1000 };
  }
}
