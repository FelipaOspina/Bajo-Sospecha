import {
  PROTOCOL_VERSION,
  type ClientIntent,
  type GameEvent,
  type PlayerId,
  type Resolution,
  type RoomPhase,
  type RoomSnapshot,
  type ServerMessage,
} from '../../../shared/protocol/protocol.js';
import { EventBus } from '../core/EventBus.js';
import type { Result } from '../core/Result.js';
import {
  ChannelSystem,
  createEvidenceSystem,
  type ChannelEvents,
  type EvidenceEvents,
  type EvidenceMapConfig,
  type EvidenceSystem,
} from '../domain/evidence/index.js';
import type { ObjectiveRegistry, ObjectiveWorldView } from '../domain/roles/objectives/ObjectiveRegistry.js';
import type { RoleManager } from '../domain/roles/RoleManager.js';
import {
  createDefaultConditionRegistry,
  GameResolution,
  TrialSystem,
  type ConditionRegistry,
  type EndingConfig,
  type ResolutionContext,
  type TrialConfig,
} from '../domain/trial/index.js';
import type { SkinCatalog } from '../domain/skins/SkinCatalog.js';
import { AbilitySystem, type AbilityCatalog, type AbilityUse } from '../domain/abilities/index.js';
import type { IRoleQuery, PlayerStats } from '../domain/roles/types.js';
import { mathRandom, type IRandom } from '../core/Random.js';
import { fail, ok } from '../core/Result.js';
import { BodyContainer } from '../domain/evidence/interactables/EvidenceContainer.js';
import type { LineOfSight } from '../domain/world/LineOfSight.js';
import { SILENCE_ENDING_ID, type GhostTaskPoint } from '../domain/scenario/ScenarioAdapter.js';
import type { Verdict } from '../domain/trial/TrialSystem.js';
import type { PlayerId as Pid, Vec2 } from '../../../shared/protocol/protocol.js';
import { JsonDeltaEncoder, type IDeltaEncoder } from './DeltaEncoder.js';
import { freshSocialFields, RoomState, type PlayerRecord, type RoomVisibility } from './RoomState.js';
import { StateProjector, type MotiveTarget } from './StateProjector.js';
import type { MatchActivity } from '../domain/profile/types.js';
import { emptyActivity } from '../domain/profile/DetectivePath.js';

/** Cómo sale un mensaje hacia un jugador. WebSocket hoy; WebRTC/ENet mañana. */
export interface IClientTransport {
  send(playerId: PlayerId, msg: ServerMessage): void;
}

/** Todo lo que una sala necesita del escenario cargado. */
export interface RoomSetup {
  roles: RoleManager;
  objectives: ObjectiveRegistry;
  map: EvidenceMapConfig;
  trial?: TrialConfig;
  endings?: EndingConfig[];
  conditions?: ConditionRegistry;
  /** Catálogo de skins de animales; sin él los jugadores no llevan skinId. */
  skins?: SkinCatalog;
  /** Habilidades por animal (shared/config/abilities); sin él no hay habilidades. */
  abilities?: AbilityCatalog;
  /** Muros para los testigos (shared/config/maps/office_walls.json); sin ellos, solo distancia. */
  lineOfSight?: LineOfSight;
  /** Emergencias: máximo por partida y qué expulsión termina la partida (rol → opción del juicio). */
  emergency?: { maxPerMatch: number; expelEndsGame: Record<string, string> };
  /** Puntos para las misiones de fantasma (sitios de pistas). Sin ellos, los objetos del mapa. */
  ghostTaskPoints?: GhostTaskPoint[];
  /** Azar para repartir misiones de fantasma. */
  rng?: IRandom;
}

/** Reglas de silenciar / escoltar / emergencias / fantasmas (ms y px). */
export const SOCIAL = {
  silenceRange: 90,
  silenceCooldownMs: 60_000,
  /** "too_early": los primeros 60 s de la investigación. */
  silenceGraceMs: 60_000,
  knockMs: 30_000,
  reportRange: 160,
  escortRange: 160,
  escortMs: 45_000,
  escortCooldownMs: 90_000,
  witnessRange: 900,
  ghostPingCooldownMs: 20_000,
  ghostPingMs: 6_000,
  ghostTaskRange: 80,
  ghostTaskMs: 6_000,
  ghostTasksAtOnce: 3,
  ghostTasksMax: 6,
  ghostRevealMs: 20_000,
  /** Cuánto se ve el resultado de la emergencia antes de volver a la investigación. */
  emergencyResultMs: 4_000,
  bodyRadius: 48,
  ghostTaskTolerance: 6,
} as const;

/** Intenciones vetadas a fantasmas (not_alive) y a noqueados (knocked). */
const GHOST_FORBIDDEN = new Set<ClientIntent['t']>([
  'interact', 'channel_start', 'drop_evidence', 'destroy_evidence', 'present_evidence', 'vote', 'use_ability',
  'silence', 'report_body', 'escort', 'emergency_vote', 'call_meeting', 'skip_to_voting',
]);
const KNOCKED_FORBIDDEN = new Set<ClientIntent['t']>([
  'move', 'interact', 'channel_start', 'drop_evidence', 'destroy_evidence', 'present_evidence', 'use_ability',
  'silence', 'report_body', 'escort', 'call_meeting',
]);

export interface RoomOptions {
  phaseDurationsMs: Partial<Record<RoomPhase, number>>;
  maxSpeedPxPerSec: number;
  now: () => number;
  /** private (por código) o public (matchmaking: arranca sola con autoStartDelayMs). */
  visibility: RoomVisibility;
  autoStartDelayMs: number;
  /** Al terminar la partida (recompensas de perfil y retos de la Ruta del Detective). */
  onResolved?: (resolution: Resolution, activity: ReadonlyMap<PlayerId, MatchActivity>) => void;
}

/** Al entrar: skins que puede llevar, la que prefiere y sus cosméticos puestos (de su perfil). */
export interface JoinOptions {
  ownedSkins?: string[];
  preferredSkin?: string;
  look?: Record<string, string>;
}

const MAX_CHAT_LENGTH = 200;

const DEFAULTS: RoomOptions = {
  phaseDurationsMs: { briefing: 10_000, investigation: 180_000, emergency: 75_000, discussion: 90_000, voting: 45_000 },
  maxSpeedPxPerSec: 260,
  now: () => Date.now(),
  visibility: 'private',
  autoStartDelayMs: 10_000,
};

const NEXT_PHASE: Partial<Record<RoomPhase, RoomPhase>> = {
  briefing: 'investigation',
  investigation: 'discussion',
  discussion: 'voting',
  voting: 'results',
};

/**
 * Una partida. Recibe intenciones, las valida contra los sistemas de dominio y
 * difunde el resultado:
 *   - Eventos discretos (fiables, inmediatos) → 'event'
 *   - Estado continuo (posiciones, contadores) → 'delta' en cada tick
 */
export class Room {
  readonly state = new RoomState();
  readonly evidence: EvidenceSystem;
  private readonly projector: StateProjector;
  private readonly lastSent = new Map<PlayerId, RoomSnapshot>();
  private readonly opts: RoomOptions;
  private readonly bus = new EventBus<EvidenceEvents & ChannelEvents>();
  readonly channels: ChannelSystem;
  private readonly objectiveWorld: ObjectiveWorldView;
  private readonly roles: RoleManager;
  readonly trial: TrialSystem;
  private readonly resolver: GameResolution;
  private resolution: Resolution | null = null;
  /** Veredicto impuesto (CEO expulsado en una emergencia). */
  private verdictOverride: Verdict | null = null;
  private readonly endings: EndingConfig[];
  private readonly lineOfSight?: LineOfSight;
  private readonly emergencyRules: { maxPerMatch: number; expelEndsGame: Record<string, string> };
  private readonly ghostTaskPoints?: GhostTaskPoint[];
  private readonly rng: IRandom;
  private ghostTaskSeq = 0;
  private bodySeq = new Map<PlayerId, number>();
  private readonly skins?: SkinCatalog;
  readonly abilities?: AbilitySystem;
  /** Lo que hace cada jugador en la partida (retos de la Ruta del Detective). Privado: solo va a su perfil. */
  readonly activity = new Map<PlayerId, MatchActivity>();

  constructor(
    readonly id: string,
    setup: RoomSetup,
    private readonly transport: IClientTransport,
    opts: Partial<RoomOptions> = {},
    private readonly encoder: IDeltaEncoder = new JsonDeltaEncoder(),
  ) {
    this.opts = { ...DEFAULTS, ...opts, phaseDurationsMs: { ...DEFAULTS.phaseDurationsMs, ...opts.phaseDurationsMs } };
    const { roles, objectives, map } = setup;
    this.roles = roles;
    this.skins = setup.skins;
    this.state.code = id;
    this.state.visibility = this.opts.visibility;
    this.endings = setup.endings ?? [];
    this.lineOfSight = setup.lineOfSight;
    this.emergencyRules = setup.emergency ?? { maxPerMatch: 3, expelEndsGame: {} };
    this.ghostTaskPoints = setup.ghostTaskPoints;
    this.rng = setup.rng ?? mathRandom;

    const world = {
      positionOf: (p: PlayerId) => this.state.players.get(p)?.position,
      isAlive: (p: PlayerId) => this.state.players.get(p)?.alive ?? false,
      currentPhase: () => this.state.phase,
      now: this.opts.now,
    };
    // Las pasivas del animal (alcance, inventario) se suman a las estadísticas del rol.
    const rolesWithAbilities: IRoleQuery = {
      getRoleOf: (p) => roles.getRoleOf(p),
      getStats: (p) => this.withAbilityStats(p, roles.getStats(p)),
      visibilityFor: (p, tags) => roles.visibilityFor(p, tags),
      knownTeammates: (p) => roles.knownTeammates(p),
    };
    this.evidence = createEvidenceSystem(map, rolesWithAbilities, world, this.bus);
    this.channels = new ChannelSystem(this.evidence, roles, world, this.bus, {
      durationMultiplier: (p) => this.abilities?.channelMultiplier(p) ?? 1,
      moveTolerance: (p) => this.abilities?.effects(p).moveTolerance ?? 0,
    });
    if (setup.abilities) {
      this.abilities = new AbilitySystem(setup.abilities, {
        players: () => [...this.state.players.keys()],
        skinOf: (p) => this.state.players.get(p)?.skinId,
        ...world,
      }, {
        interrupt: (p) => {
          const busy = this.channels.get(p) !== undefined;
          this.channels.cancel(p, 'interrupted');
          return busy;
        },
        scent: (p, radius) => this.scent(p, radius),
      });
    }

    this.objectiveWorld = {
      players: () => [...this.state.players.keys()],
      teamOf: (p) => roles.getRoleOf(p)?.team,
      inventoryTags: (p) => this.evidence.inventoryTags(p),
      accusedPlayers: () => this.currentVerdict().accused,
      verdict: () => this.currentVerdict().optionId,
      revealedTags: () => this.evidence.revealedTags(),
    };

    this.trial = new TrialSystem(
      setup.trial,
      {
        ids: () => [...this.state.players.keys()],
        nameOf: (p) => this.state.players.get(p)?.name ?? p,
        isAlive: (p) => this.state.players.get(p)?.alive ?? false,
        playersWithRole: (r) => [...this.state.players.keys()].filter((p) => roles.getRoleOf(p)?.id === r),
      },
      this.evidence,
      (instanceId) => this.projector.publicEvidenceView(instanceId),
      this.opts.now,
    );
    this.resolver = new GameResolution(roles, objectives, setup.conditions ?? createDefaultConditionRegistry(), setup.endings);
    this.projector = new StateProjector(this.state, roles, objectives, this.evidence, this.objectiveWorld, this.trial, () => this.resolution, this.channels, this.abilities, {
      motiveTargets: (viewer) => this.motiveTargets(viewer),
      silenceReadyAt: (viewer) => this.silenceReadyAt(viewer),
      now: this.opts.now,
    });
    this.wireDomainEvents();
  }

  // ───── Conexión ─────

  /** Por qué no se puede entrar ahora (null = se puede). */
  joinError(): 'game_started' | 'room_full' | null {
    if (this.state.phase !== 'lobby') return 'game_started';
    if (this.state.players.size >= this.roles.roleSet.maxPlayers) return 'room_full';
    return null;
  }

  connect(playerId: PlayerId, name: string, join: JoinOptions = {}): void {
    const existing = this.state.players.get(playerId);
    if (existing) {
      existing.connected = true; // reconexión: conserva rol e inventario
    } else {
      const error = this.joinError();
      if (error) throw new Error(error);
      const taken = [...this.state.players.values()].map((o) => o.skinId);
      const preferred = join.preferredSkin && !taken.includes(join.preferredSkin) && (join.ownedSkins?.includes(join.preferredSkin) ?? true)
        ? join.preferredSkin : undefined;
      this.state.players.set(playerId, {
        id: playerId, name, position: { x: 0, y: 0 }, connected: true, ready: false,
        alive: true, lastSeq: 0, lastMoveAt: this.opts.now(),
        ...freshSocialFields({ x: 0, y: 0 }),
        ownedSkins: join.ownedSkins,
        skinId: preferred ?? this.skins?.pickFree(taken, join.ownedSkins),
        ...(join.look ? { look: { ...join.look } } : {}),
      });
      this.broadcast({ e: 'player_joined', playerId, name });
      this.updateCountdown();
    }
    this.state.bump();
    const snapshot = this.projector.snapshotFor(playerId);
    this.lastSent.set(playerId, snapshot);
    this.transport.send(playerId, { t: 'welcome', playerId, protocol: PROTOCOL_VERSION, roomCode: this.id, serverTime: this.opts.now(), snapshot });
  }

  /** Sin nadie conectado: la sala se puede cerrar. */
  isEmpty(): boolean {
    return ![...this.state.players.values()].some((p) => p.connected);
  }

  get phase(): RoomPhase { return this.state.phase; }

  disconnect(playerId: PlayerId): void {
    const p = this.state.players.get(playerId);
    if (!p) return;
    if (this.state.phase === 'lobby') {
      this.state.players.delete(playerId);
      this.roles.removePlayer(playerId);
      this.updateCountdown();
    } else {
      p.connected = false;
      this.channels.cancel(playerId, 'disconnected');
      this.evidence.spillInventory(playerId);
    }
    this.lastSent.delete(playerId);
    this.state.bump();
    this.broadcast({ e: 'player_left', playerId });
  }

  // ───── Intenciones ─────

  handleIntent(playerId: PlayerId, intent: ClientIntent): void {
    const player = this.state.players.get(playerId);
    if (!player) return;
    if (intent.seq <= player.lastSeq) return; // duplicado / desordenado
    player.lastSeq = intent.seq;

    const gate = this.gate(player, intent.t);
    const result = gate ? fail(gate) : this.apply(player, intent);
    if (result.ok) {
      this.state.bump();
      this.transport.send(playerId, { t: 'ack', seq: intent.seq });
    } else {
      this.transport.send(playerId, { t: 'rejected', seq: intent.seq, reason: result.error });
    }
  }

  private apply(player: PlayerRecord, intent: ClientIntent): Result<unknown> {
    switch (intent.t) {
      case 'join': return { ok: true, value: null };
      case 'ready': return this.setReady(player, intent.ready);
      case 'choose_skin': return this.chooseSkin(player, intent.skinId);
      case 'chat': return this.chat(player, intent.text);
      case 'move': return this.move(player, intent.position);
      case 'interact': return this.evidence.interact(player.id, intent.interactableId, intent.evidenceInstanceId);
      case 'channel_start': return this.channels.start(player.id, intent.evidenceInstanceId, intent.action);
      case 'channel_cancel': this.channels.cancel(player.id); return { ok: true, value: null };
      case 'drop_evidence': return this.evidence.drop(player.id, intent.evidenceInstanceId);
      case 'destroy_evidence': return this.evidence.destroy(player.id, intent.evidenceInstanceId);
      case 'present_evidence':
        if (player.wasKnocked) return fail('knocked_before');
        return this.trial.present(player.id, intent.evidenceInstanceId);
      case 'call_meeting': return this.callMeeting(player);
      case 'skip_to_voting': return this.skipToVoting(player);
      case 'use_ability': return this.useAbility(player);
      case 'vote': return this.vote(player, intent.optionId);
      case 'silence': return this.silence(player, intent.targetId);
      case 'report_body': return this.reportBody(player, intent.bodyId);
      case 'escort': return this.escort(player, intent.targetId);
      case 'emergency_vote': return this.emergencyVote(player, intent.targetId);
      case 'ghost_ping': return this.ghostPing(player, intent.position);
      case 'ghost_task': return this.startGhostTask(player, intent.taskId);
      default: return { ok: false, error: 'unknown_intent' };   // menú/perfil: los atiende GameGateway
    }
  }

  /** Fantasmas y noqueados no pueden hacer casi nada. */
  private gate(player: PlayerRecord, t: ClientIntent['t']): string | null {
    if (player.ghost && GHOST_FORBIDDEN.has(t)) return 'not_alive';
    if (this.isKnocked(player) && KNOCKED_FORBIDDEN.has(t)) return 'knocked';
    return null;
  }

  private isKnocked(p: PlayerRecord): boolean {
    return p.knockedUntil !== null && p.knockedUntil > this.opts.now();
  }

  /** En pie: vivo, no fantasma (los noqueados cuentan como en pie). */
  private standing(p: PlayerRecord | undefined): p is PlayerRecord {
    return !!p && p.alive && !p.ghost;
  }

  /** Suma uno a una estadística de la partida (solo durante la partida). */
  private track(playerId: PlayerId, stat: Exclude<keyof MatchActivity, 'survived'>, n = 1): void {
    if (this.state.phase === 'lobby') return;
    let a = this.activity.get(playerId);
    if (!a) { a = emptyActivity(); this.activity.set(playerId, a); }
    a[stat] += n;
  }

  private setReady(player: PlayerRecord, ready: boolean): Result<null> {
    if (this.state.phase !== 'lobby') return { ok: false, error: 'wrong_phase' };
    player.ready = ready;
    const all = [...this.state.players.values()];
    if (all.length >= this.roles.roleSet.minPlayers && all.every((p) => p.ready)) this.startGame();
    return { ok: true, value: null };
  }

  /** Reparte roles y empieza (todos listos, o fin de la cuenta atrás pública). */
  private startGame(): void {
    const all = [...this.state.players.values()];
    this.activity.clear();
    for (const p of all) this.activity.set(p.id, emptyActivity());
    this.roles.assignRoles(all.map((p) => p.id));
    // Opción desactivada por defecto: la skin del rol delataría el rol a todos.
    for (const p of all) p.skinId = this.skins?.forRole(this.roles.getRoleOf(p.id)?.id) ?? p.skinId;
    this.state.startsAt = null;
    this.enterPhase('briefing');
  }

  /** Salas públicas: con el mínimo de jugadores empieza la cuenta atrás; si alguien sale, se para. */
  private updateCountdown(): void {
    if (this.state.visibility !== 'public' || this.state.phase !== 'lobby') return;
    const enough = this.state.players.size >= this.roles.roleSet.minPlayers;
    if (enough && this.state.startsAt === null) this.state.startsAt = this.opts.now() + this.opts.autoStartDelayMs;
    if (!enough) this.state.startsAt = null;
  }

  /** Fases con chat: lobby, el debate del juicio final y la asamblea de emergencia. */
  private static readonly CHAT_PHASES: ReadonlySet<RoomPhase> = new Set<RoomPhase>(['lobby', 'discussion', 'voting', 'emergency']);

  private chat(player: PlayerRecord, text: unknown): Result<null> {
    if (!Room.CHAT_PHASES.has(this.state.phase)) return { ok: false, error: 'wrong_phase' };
    // Los fantasmas no hablan con los vivos (en el lobby nadie es fantasma).
    if (this.state.phase !== 'lobby' && !this.standing(player)) return fail('not_alive');
    const clean = String(text ?? '').replace(/\s+/g, ' ').trim().slice(0, MAX_CHAT_LENGTH);
    if (!clean) return { ok: false, error: 'empty_message' };
    this.broadcast({ e: 'chat', by: player.id, name: player.name, text: clean, at: this.opts.now() });
    if (this.state.phase !== 'lobby') this.track(player.id, 'chats');
    return { ok: true, value: null };
  }

  /** Cosméticos cambiados en el menú mientras espera en el lobby (los valida el perfil). */
  setLook(playerId: PlayerId, look: Record<string, string>): void {
    const p = this.state.players.get(playerId);
    if (!p || this.state.phase !== 'lobby') return;
    p.look = { ...look };
    this.state.bump();
  }

  private chooseSkin(player: PlayerRecord, skinId: string): Result<null> {
    if (this.state.phase !== 'lobby') return { ok: false, error: 'wrong_phase' };
    if (!this.skins?.has(skinId)) return { ok: false, error: 'unknown_skin' };
    if (player.ownedSkins && !player.ownedSkins.includes(skinId)) return { ok: false, error: 'skin_locked' };
    const takenByOther = [...this.state.players.values()].some((o) => o.id !== player.id && o.skinId === skinId);
    if (takenByOther) return { ok: false, error: 'skin_taken' };
    player.skinId = skinId;
    return { ok: true, value: null };
  }

  private move(player: PlayerRecord, to: { x: number; y: number }): Result<null> {
    if (!Number.isFinite(to.x) || !Number.isFinite(to.y)) return { ok: false, error: 'bad_position' };
    const now = this.opts.now();
    const dt = Math.max((now - player.lastMoveAt) / 1000, 1 / 60);
    const dist = Math.hypot(to.x - player.position.x, to.y - player.position.y);
    // Margen de 1.5x para jitter de red. Si se excede, el siguiente delta corrige al cliente.
    const speed = this.opts.maxSpeedPxPerSec * (this.abilities?.speedMultiplier(player.id) ?? 1);
    if (dist > speed * dt * 1.5) return { ok: false, error: 'too_fast' };
    player.position = { x: to.x, y: to.y };
    player.lastMoveAt = now;
    if (!player.ghost) player.lastSeenPosition = { ...player.position };
    this.channels.onMove(player.id, player.position);
    const gc = player.ghostChannel;
    if (gc && Math.hypot(to.x - gc.origin.x, to.y - gc.origin.y) > SOCIAL.ghostTaskTolerance) this.cancelGhostTask(player, 'moved');
    return { ok: true, value: null };
  }

  // ───── Habilidades ─────

  private useAbility(player: PlayerRecord): Result<AbilityUse> {
    if (!this.abilities) return { ok: false, error: 'no_ability' };
    const r = this.abilities.use(player.id);
    if (r.ok) { this.sendAbilityEvent(r.value); this.track(player.id, 'abilities'); }
    return r;
  }

  /** Quien la usa recibe todo; los demás, solo las que no son secretas y sin las marcas. */
  private sendAbilityEvent(use: AbilityUse): void {
    const full: GameEvent = {
      e: 'ability_used', by: use.by, abilityId: use.abilityId, endsAt: use.endsAt,
      ...(use.marks ? { marks: use.marks } : {}),
      ...(use.affected ? { affected: use.affected } : {}),
    };
    for (const [id, p] of this.state.players) {
      if (!p.connected) continue;
      if (id !== use.by && use.secret) continue;
      const event: GameEvent = id === use.by ? full : { e: 'ability_used', by: use.by, abilityId: use.abilityId, endsAt: use.endsAt, ...(use.affected ? { affected: use.affected } : {}) };
      this.transport.send(id, { t: 'event', version: this.state.version, event });
    }
  }

  /** Olfato: escondites cerca con alguna prueba que este jugador puede percibir. */
  private scent(playerId: PlayerId, radius: number): string[] {
    const here = this.state.players.get(playerId)?.position;
    if (!here) return [];
    return this.evidence.listInteractables()
      .filter((i) => Math.hypot(i.position.x - here.x, i.position.y - here.y) <= radius)
      .filter((i) => i.contents().some((id) => this.evidence.visibilityOf(playerId, id) !== 'hidden'))
      .map((i) => i.id);
  }

  private withAbilityStats(playerId: PlayerId, stats: PlayerStats): PlayerStats {
    if (!this.abilities) return stats;
    const e = this.abilities.effects(playerId);
    if (e.interactRange === 1 && e.inventory === 0) return stats;
    return { ...stats, interactRange: stats.interactRange * e.interactRange, inventoryCapacity: stats.inventoryCapacity + e.inventory };
  }

  private vote(player: PlayerRecord, optionId: string | null): Result<null> {
    if (this.state.phase !== 'voting') return { ok: false, error: 'wrong_phase' };
    const r = this.trial.vote(player.id, optionId);
    if (!r.ok) return r;
    if (optionId !== null) this.track(player.id, 'trialVotes');
    this.broadcast({ e: 'vote_cast', by: player.id });
    // Si ya votaron todos, no hace falta esperar al temporizador.
    if (this.trial.allVoted()) this.enterPhase('results');
    return r;
  }

  // ───── Bucle ─────

  /** Llamar a ~20 Hz. Avanza fases y envía deltas filtrados por jugador. */
  tick(): void {
    const now = this.opts.now();
    this.channels.tick();
    this.tickSocial(now);
    if (this.state.phase === 'lobby' && this.state.startsAt !== null && now >= this.state.startsAt) this.startGame();
    if (this.state.phase === 'emergency') {
      if (this.state.phaseEndsAt !== null && now >= this.state.phaseEndsAt) {
        if (this.state.emergency?.result) this.resumeInvestigation();
        else this.resolveEmergency();
      }
    } else if (this.state.phaseEndsAt !== null && now >= this.state.phaseEndsAt) {
      const next = NEXT_PHASE[this.state.phase];
      if (next) this.enterPhase(next);
    }

    for (const [id, p] of this.state.players) {
      if (!p.connected) continue;
      const next = this.projector.snapshotFor(id);
      const prev = this.lastSent.get(id);
      if (!prev) { this.transport.send(id, { t: 'snapshot', snapshot: next }); this.lastSent.set(id, next); continue; }
      const ops = this.encoder.diff({ ...prev, version: 0 }, { ...next, version: 0 });
      if (ops.length === 0) continue;
      this.transport.send(id, { t: 'delta', from: prev.version, to: next.version, ops });
      this.lastSent.set(id, next);
    }
  }

  private enterPhase(phase: RoomPhase): void {
    this.state.phase = phase;
    if (phase === 'investigation' || phase === 'discussion') this.abilities?.reset();
    if (phase === 'investigation' && this.state.investigationStartedAt === null) this.state.investigationStartedAt = this.opts.now();
    if (phase !== 'emergency') this.state.emergency = null;
    for (const p of this.state.players.values()) if (p.ghostChannel && phase !== 'investigation') this.cancelGhostTask(p, 'wrong_phase');
    const d = this.opts.phaseDurationsMs[phase];
    this.state.phaseEndsAt = d ? this.opts.now() + d : null;
    if (phase === 'results') this.resolution ??= this.resolve();
    this.state.bump();
    this.broadcast({ e: 'phase_changed', phase, endsAt: this.state.phaseEndsAt });
    if (this.resolution && phase === 'results') {
      this.broadcast({ e: 'game_over', resolution: this.resolution });
      for (const p of this.state.players.values()) {
        const a = this.activity.get(p.id) ?? emptyActivity();
        a.survived = this.standing(p);
        this.activity.set(p.id, a);
      }
      this.opts.onResolved?.(this.resolution, this.activity);
    }
  }

  private currentVerdict(): Verdict {
    return this.verdictOverride ?? this.trial.verdict();
  }

  private resolve(forcedEnding: string | null = null): Resolution {
    const verdict = this.currentVerdict();
    const context: ResolutionContext = {
      forcedEnding,
      verdictOptionId: verdict.optionId,
      accused: verdict.accused,
      roleOf: (p) => this.roles.getRoleOf(p)?.id,
      revealed: this.evidence.revealedDefinitionIds(),
      revealedTags: this.evidence.revealedTags(),
      destroyed: this.evidence.destroyedDefinitionIds(),
      holdersOf: (d) => this.evidence.holdersOf(d),
      heldByRole: (roleId) => [...new Set([...this.state.players.keys()]
        .filter((p) => this.roles.getRoleOf(p)?.id === roleId)
        .flatMap((p) => this.evidence.inventoryOf(p).map((i) => i.definitionId)))],
    };
    return this.resolver.resolve({
      verdict,
      context,
      objectiveWorld: this.objectiveWorld,
      players: [...this.state.players.values()].map((p) => ({ id: p.id, name: p.name })),
    });
  }

  // ───── Silenciar, escoltar, cuerpos, emergencias y fantasmas ─────

  private hasPower(playerId: PlayerId, power: string): boolean {
    return this.roles.getRoleOf(playerId)?.powers?.includes(power) ?? false;
  }

  private distance(a: Vec2, b: Vec2): number {
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  /** Cuándo puede volver a silenciar (incluye los primeros 60 s de la investigación). */
  silenceReadyAt(playerId: PlayerId): number {
    const p = this.state.players.get(playerId);
    const start = this.state.investigationStartedAt
      ?? (this.state.phase === 'briefing' && this.state.phaseEndsAt !== null ? this.state.phaseEndsAt : this.opts.now());
    return Math.max(p?.silenceReadyAt ?? 0, start + SOCIAL.silenceGraceMs);
  }

  /** ¿Tiene `killer` motivo para silenciar a `target`? (sección 6: solo con móvil). */
  motiveFor(killerId: PlayerId, targetId: PlayerId): MotiveTarget | null {
    const killerRole = this.roles.getRoleOf(killerId);
    const target = this.state.players.get(targetId);
    if (!killerRole || !target) return null;
    // Nunca contra los de tu propio equipo (los culpables se conocen entre sí).
    if (this.roles.getRoleOf(targetId)?.team === killerRole.team) return null;
    const against = (defId: string) => this.evidence.catalogIncriminates(defId).includes(killerRole.id);
    const carried = this.evidence.inventoryOf(targetId).find((i) => against(i.definitionId));
    if (carried) return { playerId: targetId, reason: 'evidence', evidence: this.evidence.catalogName(carried.definitionId) };
    const sameTeam = (k: PlayerId) => k === killerId || this.roles.getRoleOf(k)?.team === killerRole.team;
    if ([...target.witnessed].some(sameTeam)) return { playerId: targetId, reason: 'witness' };
    const copied = this.evidence.copiedBy(targetId).find(against);
    if (copied) return { playerId: targetId, reason: 'backup', evidence: this.evidence.catalogName(copied) };
    const targetRole = this.roles.getRoleOf(targetId);
    if (targetRole && killerRole.motiveTargets?.includes(targetRole.id)) return { playerId: targetId, reason: 'story' };
    return null;
  }

  /** Jugadores a los que el receptor (rol con silence) puede silenciar ahora y por qué. */
  motiveTargets(viewer: PlayerId): MotiveTarget[] | undefined {
    if (!this.hasPower(viewer, 'silence')) return undefined;
    const out: MotiveTarget[] = [];
    for (const p of this.state.players.values()) {
      if (p.id === viewer || !this.standing(p) || this.isKnocked(p)) continue;
      const m = this.motiveFor(viewer, p.id);
      if (m) out.push(m);
    }
    return out;
  }

  private silence(killer: PlayerRecord, targetId: Pid): Result<null> {
    const now = this.opts.now();
    if (this.state.phase !== 'investigation') return fail('wrong_phase');
    if (!this.standing(killer)) return fail('not_alive');
    if (!this.hasPower(killer.id, 'silence')) return fail('no_power');
    if (this.state.investigationStartedAt !== null && now < this.state.investigationStartedAt + SOCIAL.silenceGraceMs) return fail('too_early');
    if (now < killer.silenceReadyAt) return fail('on_cooldown');
    const target = this.state.players.get(targetId);
    if (!target || target.id === killer.id || !this.standing(target) || this.isKnocked(target)) return fail('target_not_alive');
    if (this.distance(killer.position, target.position) > SOCIAL.silenceRange) return fail('too_far');
    if (!this.motiveFor(killer.id, target.id)) return fail('no_motive');

    killer.silenceReadyAt = now + SOCIAL.silenceCooldownMs;
    const guard = [...this.state.players.values()].find((g) => g.escort.protecting === target.id && (g.escort.until ?? 0) > now);
    if (guard) {
      guard.escort.protecting = null;
      guard.escort.until = null;
      this.state.bump();
      const event: GameEvent = { e: 'escort_blocked', target: target.id };
      for (const id of new Set([killer.id, guard.id, target.id])) this.sendEvent(id, event);
      return fail('target_protected');
    }

    target.timesSilenced += 1;
    const knocked = target.timesSilenced === 1;
    this.channels.cancel(target.id, 'silenced');
    this.dropBelongings(target);
    const bodyId = `body:${target.id}`;
    this.state.bodies = this.state.bodies.filter((b) => b.id !== bodyId);
    if (knocked) {
      target.knockedUntil = now + SOCIAL.knockMs;
      target.wasKnocked = true;
      this.state.bodies.push({ id: bodyId, playerId: target.id, position: { ...target.position }, reported: false, kind: 'knocked', until: target.knockedUntil });
    } else {
      this.state.bodies.push({ id: bodyId, playerId: target.id, position: { ...target.position }, reported: false, kind: 'dead' });
      this.makeGhost(target);
    }

    const until = knocked ? { until: target.knockedUntil! } : {};
    this.sendEvent(killer.id, { e: 'silenced', killer: killer.id, victim: target.id, at: now, knocked, ...until });
    this.sendEvent(target.id, { e: 'silenced', victim: target.id, at: now, knocked, ...until });
    this.notifyWitnesses(killer, target, now);
    this.state.bump();
    if (!knocked) this.checkSilenceVictory();
    return ok(null);
  }

  /** Testigos: vivos (no noqueados) con línea de vista del asesino. */
  private notifyWitnesses(killer: PlayerRecord, victim: PlayerRecord, at: number): void {
    for (const w of this.state.players.values()) {
      if (w.id === killer.id || w.id === victim.id || !this.standing(w) || this.isKnocked(w)) continue;
      const sees = this.lineOfSight
        ? this.lineOfSight.canSee(w.position, killer.position, SOCIAL.witnessRange)
        : this.distance(w.position, killer.position) <= SOCIAL.witnessRange;
      if (!sees) continue;
      // Un compañero del asesino no es un testigo peligroso para él (ya lo sabe).
      if (this.roles.getRoleOf(w.id)?.team === this.roles.getRoleOf(killer.id)?.team) continue;
      w.witnessed.add(killer.id);
      this.sendEvent(w.id, { e: 'witnessed', killer: killer.id, victim: victim.id, at });
    }
  }

  /** Su inventario cae en un contenedor "body" ("Objetos caídos de X") donde está. */
  private dropBelongings(p: PlayerRecord): void {
    const n = (this.bodySeq.get(p.id) ?? 0) + 1;
    this.bodySeq.set(p.id, n);
    const id = n === 1 ? `body:${p.id}` : `body:${p.id}#${n}`;
    const container = new BodyContainer(id, { ...p.position }, SOCIAL.bodyRadius, p.id, `Objetos caídos de ${p.name}`);
    this.evidence.addInteractable(container);
    this.evidence.moveInventoryTo(p.id, container);
  }

  private makeGhost(p: PlayerRecord): void {
    p.alive = false;
    p.ghost = true;
    p.knockedUntil = null;
    p.lastSeenPosition = { ...p.position };
    p.ghostPingReadyAt = 0;
    this.channels.cancel(p.id, 'not_alive');
    while (p.ghostTasks.filter((t) => !t.done).length < SOCIAL.ghostTasksAtOnce && p.ghostTasks.length < SOCIAL.ghostTasksMax) {
      if (!this.assignGhostTask(p)) break;
    }
  }

  private reportBody(player: PlayerRecord, bodyId: string): Result<null> {
    if (this.state.phase !== 'investigation') return fail('wrong_phase');
    if (!this.standing(player)) return fail('not_alive');
    const body = this.state.bodies.find((b) => b.id === bodyId && !b.reported);
    if (!body) return fail('unknown_body');
    if (this.distance(player.position, body.position) > SOCIAL.reportRange) return fail('too_far');
    body.reported = true;
    this.track(player.id, 'reported');
    this.broadcast({ e: 'body_reported', by: player.id, bodyId, victim: body.playerId });
    if (this.state.emergenciesHeld < this.emergencyRules.maxPerMatch) this.openEmergency(player.id, bodyId);
    return ok(null);
  }

  /**
   * Botón de emergencia: abre la asamblea de emergencia (sin cuerpo) durante la investigación.
   * Una vez por jugador y partida; cuenta para el máximo de emergencias. Solo vivos no noqueados
   * (los fantasmas/noqueados los rechaza gate()).
   */
  private callMeeting(player: PlayerRecord): Result<null> {
    if (this.state.phase !== 'investigation') return fail('wrong_phase');
    if (!this.standing(player)) return fail('not_alive');
    if (player.meetingUsed) return fail('meeting_used');
    if (this.state.emergenciesHeld >= this.emergencyRules.maxPerMatch) return fail('no_meetings_left');
    player.meetingUsed = true;
    this.track(player.id, 'meetings');
    this.broadcast({ e: 'meeting_called', by: player.id });
    this.openEmergency(player.id, null);
    return ok(null);
  }

  /** Juicio final: pasar del debate a la votación. */
  private skipToVoting(_player: PlayerRecord): Result<null> {
    if (this.state.phase !== 'discussion') return fail('wrong_phase');
    this.enterPhase('voting');
    return ok(null);
  }

  private openEmergency(calledBy: PlayerId, bodyId: string | null): void {
    const now = this.opts.now();
    const remaining = Math.max(0, (this.state.phaseEndsAt ?? now) - now);
    this.state.emergenciesHeld += 1;
    for (const c of this.channels.all()) this.channels.cancel(c.playerId, 'wrong_phase');
    for (const p of this.state.players.values()) if (p.ghostChannel) this.cancelGhostTask(p, 'wrong_phase');
    const endsAt = now + (this.opts.phaseDurationsMs.emergency ?? 75_000);
    this.state.phase = 'emergency';
    this.state.phaseEndsAt = endsAt;
    this.state.emergency = { calledBy, bodyId, votes: new Map(), endsAt, remaining, result: null };
    this.state.bump();
    this.broadcast({ e: 'phase_changed', phase: 'emergency', endsAt });
  }

  private emergencyVote(player: PlayerRecord, targetId: Pid | 'skip' | null): Result<null> {
    const em = this.state.emergency;
    if (this.state.phase !== 'emergency' || !em || em.result) return fail('wrong_phase');
    if (!this.standing(player)) return fail('not_alive');
    if (targetId === null) { em.votes.delete(player.id); return ok(null); }
    if (targetId !== 'skip' && !this.standing(this.state.players.get(targetId))) return fail('unknown_target');
    if (!em.votes.has(player.id)) this.track(player.id, 'emergencyVotes');
    em.votes.set(player.id, targetId);
    const voters = [...this.state.players.values()].filter((p) => this.standing(p) && p.connected);
    if (voters.every((p) => em.votes.has(p.id))) this.resolveEmergency();
    return ok(null);
  }

  /** Mayoría ESTRICTA de los votos emitidos (y no skip) → expulsado. */
  private resolveEmergency(): void {
    const em = this.state.emergency;
    if (!em || em.result) return;
    const tally: Record<string, number> = {};
    for (const v of em.votes.values()) tally[v] = (tally[v] ?? 0) + 1;
    const cast = em.votes.size;
    const top = Object.entries(tally).sort((a, b) => b[1] - a[1])[0];
    const expelledId = top && top[0] !== 'skip' && top[1] * 2 > cast ? top[0] : null;
    em.result = { expelled: expelledId, tally };
    this.broadcast({ e: 'emergency_result', expelled: expelledId, tally });

    const expelled = expelledId ? this.state.players.get(expelledId) : undefined;
    if (expelled) {
      this.dropBelongings(expelled);
      this.makeGhost(expelled);
      const option = this.emergencyRules.expelEndsGame[this.roles.getRoleOf(expelled.id)?.id ?? ''];
      if (option) {
        this.verdictOverride = this.trial.forcedVerdict(option, tally);
        this.enterPhase('results');
        return;
      }
      if (this.checkSilenceVictory()) return;
    }
    this.state.phaseEndsAt = this.opts.now() + SOCIAL.emergencyResultMs;
    this.state.bump();
  }

  /** Vuelve a la investigación con el tiempo que quedaba (sin reiniciar habilidades). */
  private resumeInvestigation(): void {
    const remaining = this.state.emergency?.remaining ?? 0;
    this.state.emergency = null;
    this.state.phase = 'investigation';
    this.state.phaseEndsAt = this.opts.now() + remaining;
    this.state.bump();
    this.broadcast({ e: 'phase_changed', phase: 'investigation', endsAt: this.state.phaseEndsAt });
  }

  /** silencio_total: los culpables en pie igualan o superan al resto (noqueados cuentan en pie). */
  private checkSilenceVictory(): boolean {
    if (this.state.phase === 'results') return false;
    const ending = this.endings.find((e) => e.id === SILENCE_ENDING_ID);
    if (!ending) return false;
    const isKiller = (p: PlayerId) => {
      const r = this.roles.getRoleOf(p);
      return !!r && (!!ending.winners.roles?.includes(r.id) || !!ending.winners.teams?.includes(r.team));
    };
    const standing = [...this.state.players.values()].filter((p) => this.standing(p));
    const killers = standing.filter((p) => isKiller(p.id)).length;
    if (killers === 0 || killers < standing.length - killers) return false;
    this.resolution = this.resolve(SILENCE_ENDING_ID);
    this.enterPhase('results');
    return true;
  }

  private escort(guard: PlayerRecord, targetId: Pid): Result<null> {
    const now = this.opts.now();
    if (this.state.phase !== 'investigation') return fail('wrong_phase');
    if (!this.standing(guard)) return fail('not_alive');
    if (!this.hasPower(guard.id, 'escort')) return fail('no_power');
    if (now < guard.escort.readyAt) return fail('on_cooldown');
    const target = this.state.players.get(targetId);
    if (!target || target.id === guard.id || !this.standing(target)) return fail('target_not_alive');
    if (this.distance(guard.position, target.position) > SOCIAL.escortRange) return fail('too_far');
    guard.escort = { readyAt: now + SOCIAL.escortCooldownMs, protecting: target.id, until: now + SOCIAL.escortMs };
    return ok(null);
  }

  private ghostPing(ghost: PlayerRecord, position: Vec2): Result<null> {
    const now = this.opts.now();
    if (!ghost.ghost) return fail('not_ghost');
    if (this.state.phase === 'lobby' || this.state.phase === 'results') return fail('wrong_phase');
    if (!position || !Number.isFinite(position.x) || !Number.isFinite(position.y)) return fail('bad_position');
    if (now < ghost.ghostPingReadyAt) return fail('on_cooldown');
    ghost.ghostPingReadyAt = now + SOCIAL.ghostPingCooldownMs;
    const team = this.roles.getRoleOf(ghost.id)?.team;
    const event: GameEvent = { e: 'ghost_ping', by: ghost.id, position: { x: position.x, y: position.y }, until: now + SOCIAL.ghostPingMs };
    for (const p of this.state.players.values()) {
      if (p.id !== ghost.id && this.standing(p) && this.roles.getRoleOf(p.id)?.team === team) this.sendEvent(p.id, event);
    }
    this.sendEvent(ghost.id, event);   // eco para quien la pone
    return ok(null);
  }

  // ───── Misiones de fantasma ─────

  private assignGhostTask(p: PlayerRecord): boolean {
    const points = this.ghostTaskPoints?.length
      ? this.ghostTaskPoints
      : this.evidence.listInteractables().filter((i) => i.type === 'evidence_spot').map((i) => ({ position: i.position, label: 'Hacer parpadear las luces' }));
    if (!points.length) return false;
    const used = new Set(p.ghostTasks.map((t) => `${t.position.x},${t.position.y}`));
    const fresh = points.filter((pt) => !used.has(`${pt.position.x},${pt.position.y}`));
    const pool = fresh.length ? fresh : points;
    const pick = pool[Math.floor(this.rng.next() * pool.length)]!;
    p.ghostTasks.push({ id: `gt_${++this.ghostTaskSeq}`, label: pick.label, position: { ...pick.position }, done: false });
    return true;
  }

  private startGhostTask(p: PlayerRecord, taskId: string): Result<null> {
    if (!p.ghost) return fail('not_ghost');
    if (this.state.phase !== 'investigation') return fail('wrong_phase');
    const task = p.ghostTasks.find((t) => t.id === taskId && !t.done);
    if (!task) return fail('unknown_task');
    if (this.distance(p.position, task.position) > SOCIAL.ghostTaskRange) return fail('too_far');
    if (p.ghostChannel) return fail('already_channeling');
    p.ghostChannel = { taskId, label: task.label, startedAt: this.opts.now(), durationMs: SOCIAL.ghostTaskMs, origin: { ...p.position } };
    this.sendToGhosts({ e: 'channel_started', by: p.id, channel: { kind: 'ghost_task', label: task.label, startedAt: p.ghostChannel.startedAt, durationMs: SOCIAL.ghostTaskMs } });
    return ok(null);
  }

  private cancelGhostTask(p: PlayerRecord, reason: string): void {
    if (!p.ghostChannel) return;
    p.ghostChannel = null;
    this.state.bump();
    this.sendToGhosts({ e: 'channel_finished', by: p.id, ok: false, reason });
  }

  /** Al completar: reaparece una pista destruida, o la pista más cercana brilla para los vivos. */
  private completeGhostTask(p: PlayerRecord): void {
    const gc = p.ghostChannel!;
    p.ghostChannel = null;
    const task = p.ghostTasks.find((t) => t.id === gc.taskId);
    if (task) task.done = true;
    this.track(p.id, 'ghostTasks');
    this.sendToGhosts({ e: 'channel_finished', by: p.id, ok: true });
    const near = task?.position ?? p.position;
    if (!this.evidence.restoreDestroyed(near, p.id)) {
      const spot = this.evidence.listInteractables()
        .filter((i) => i.type === 'evidence_spot' && i.contents().length > 0)
        .sort((a, b) => this.distance(a.position, near) - this.distance(b.position, near))[0];
      if (spot) {
        const event: GameEvent = { e: 'ghost_reveal', interactableId: spot.id, position: { ...spot.position }, until: this.opts.now() + SOCIAL.ghostRevealMs };
        for (const o of this.state.players.values()) if (this.standing(o)) this.sendEvent(o.id, event);
      }
    }
    if (p.ghostTasks.length < SOCIAL.ghostTasksMax) this.assignGhostTask(p);
    this.state.bump();
  }

  /** Noqueos que terminan, escoltas que caducan y misiones de fantasma completadas. */
  private tickSocial(now: number): void {
    for (const p of this.state.players.values()) {
      if (p.knockedUntil !== null && now >= p.knockedUntil) {
        p.knockedUntil = null;
        this.state.bodies = this.state.bodies.filter((b) => !(b.playerId === p.id && b.kind === 'knocked'));
        this.state.bump();
      }
      if (p.escort.until !== null && now >= p.escort.until) {
        p.escort.protecting = null;
        p.escort.until = null;
        this.state.bump();
      }
      if (p.ghostChannel && now >= p.ghostChannel.startedAt + p.ghostChannel.durationMs) this.completeGhostTask(p);
    }
  }

  private sendEvent(playerId: PlayerId, event: GameEvent): void {
    if (this.state.players.get(playerId)?.connected) this.transport.send(playerId, { t: 'event', version: this.state.version, event });
  }

  private sendToGhosts(event: GameEvent): void {
    for (const p of this.state.players.values()) if (p.ghost) this.sendEvent(p.id, event);
  }

  // ───── Eventos ─────

  private wireDomainEvents(): void {
    this.bus.on('evidence.collected', ({ playerId, interactableId, instanceId }) => {
      this.track(playerId, 'collected');
      this.broadcast({ e: 'evidence_collected', by: playerId, interactableId, evidence: { instanceId, visibility: 'partial' } });
    });
    this.bus.on('evidence.copied', ({ playerId }) => this.track(playerId, 'backups'));
    this.bus.on('evidence.dropped', ({ playerId, interactableId }) =>
      this.broadcast({ e: 'evidence_dropped', by: playerId, interactableId }));
    this.bus.on('evidence.destroyed', ({ playerId }) =>
      this.broadcast({ e: 'evidence_destroyed', by: playerId }));
    this.bus.on('channel.started', (c) =>
      this.broadcast({ e: 'channel_started', by: c.playerId, channel: { kind: c.kind, label: c.label, startedAt: c.startedAt, durationMs: c.durationMs } }));
    this.bus.on('channel.finished', ({ channel, ok, reason }) => {
      this.state.bump();
      this.broadcast({ e: 'channel_finished', by: channel.playerId, ok, ...(reason ? { reason } : {}) });
    });
    this.bus.on('evidence.presented', ({ playerId, instanceId }) => {
      this.track(playerId, 'presented');
      this.broadcast({ e: 'evidence_presented', by: playerId, evidence: { instanceId, visibility: 'partial' } });
    });
  }

  private broadcast(event: GameEvent): void {
    for (const [id, p] of this.state.players) {
      if (!p.connected) continue;
      const projected = this.projector.projectEvent(id, event);
      if (projected) this.transport.send(id, { t: 'event', version: this.state.version, event: projected });
    }
  }

}
