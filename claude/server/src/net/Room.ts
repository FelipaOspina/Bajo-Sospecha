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
import { JsonDeltaEncoder, type IDeltaEncoder } from './DeltaEncoder.js';
import { RoomState, type PlayerRecord, type RoomVisibility } from './RoomState.js';
import { StateProjector } from './StateProjector.js';

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
}

export interface RoomOptions {
  phaseDurationsMs: Partial<Record<RoomPhase, number>>;
  maxSpeedPxPerSec: number;
  now: () => number;
  /** private (por código) o public (matchmaking: arranca sola con autoStartDelayMs). */
  visibility: RoomVisibility;
  autoStartDelayMs: number;
  /** Al terminar la partida (recompensas de perfil). */
  onResolved?: (resolution: Resolution) => void;
}

/** Al entrar: skins que puede llevar, la que prefiere y sus cosméticos puestos (de su perfil). */
export interface JoinOptions {
  ownedSkins?: string[];
  preferredSkin?: string;
  look?: Record<string, string>;
}

const MAX_CHAT_LENGTH = 200;

const DEFAULTS: RoomOptions = {
  phaseDurationsMs: { briefing: 10_000, investigation: 180_000, discussion: 90_000, voting: 45_000 },
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
  private readonly skins?: SkinCatalog;
  readonly abilities?: AbilitySystem;

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
      accusedPlayers: () => this.trial.verdict().accused,
      verdict: () => this.trial.verdict().optionId,
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
    this.projector = new StateProjector(this.state, roles, objectives, this.evidence, this.objectiveWorld, this.trial, () => this.resolution, this.channels, this.abilities);
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

    const result = this.apply(player, intent);
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
      case 'present_evidence': return this.trial.present(player.id, intent.evidenceInstanceId);
      case 'use_ability': return this.useAbility(player);
      case 'vote': return this.vote(player, intent.optionId);
      default: return { ok: false, error: 'unknown_intent' };   // menú/perfil: los atiende GameGateway
    }
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

  private chat(player: PlayerRecord, text: unknown): Result<null> {
    if (this.state.phase !== 'lobby') return { ok: false, error: 'wrong_phase' };
    const clean = String(text ?? '').replace(/\s+/g, ' ').trim().slice(0, MAX_CHAT_LENGTH);
    if (!clean) return { ok: false, error: 'empty_message' };
    this.broadcast({ e: 'chat', by: player.id, name: player.name, text: clean, at: this.opts.now() });
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
    this.channels.onMove(player.id, player.position);
    return { ok: true, value: null };
  }

  // ───── Habilidades ─────

  private useAbility(player: PlayerRecord): Result<AbilityUse> {
    if (!this.abilities) return { ok: false, error: 'no_ability' };
    const r = this.abilities.use(player.id);
    if (r.ok) this.sendAbilityEvent(r.value);
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
    if (this.state.phase === 'lobby' && this.state.startsAt !== null && now >= this.state.startsAt) this.startGame();
    if (this.state.phaseEndsAt !== null && now >= this.state.phaseEndsAt) {
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
    const d = this.opts.phaseDurationsMs[phase];
    this.state.phaseEndsAt = d ? this.opts.now() + d : null;
    if (phase === 'results') this.resolution = this.resolve();
    this.state.bump();
    this.broadcast({ e: 'phase_changed', phase, endsAt: this.state.phaseEndsAt });
    if (this.resolution && phase === 'results') {
      this.broadcast({ e: 'game_over', resolution: this.resolution });
      this.opts.onResolved?.(this.resolution);
    }
  }

  private resolve(): Resolution {
    const verdict = this.trial.verdict();
    const context: ResolutionContext = {
      verdictOptionId: verdict.optionId,
      accused: verdict.accused,
      roleOf: (p) => this.roles.getRoleOf(p)?.id,
      revealed: this.evidence.revealedDefinitionIds(),
      revealedTags: this.evidence.revealedTags(),
      destroyed: this.evidence.destroyedDefinitionIds(),
      holdersOf: (d) => this.evidence.holdersOf(d),
    };
    return this.resolver.resolve({
      verdict,
      context,
      objectiveWorld: this.objectiveWorld,
      players: [...this.state.players.values()].map((p) => ({ id: p.id, name: p.name })),
    });
  }

  // ───── Eventos ─────

  private wireDomainEvents(): void {
    this.bus.on('evidence.collected', ({ playerId, interactableId, instanceId }) =>
      this.broadcast({ e: 'evidence_collected', by: playerId, interactableId, evidence: { instanceId, visibility: 'partial' } }));
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
    this.bus.on('evidence.presented', ({ playerId, instanceId }) =>
      this.broadcast({ e: 'evidence_presented', by: playerId, evidence: { instanceId, visibility: 'partial' } }));
  }

  private broadcast(event: GameEvent): void {
    for (const [id, p] of this.state.players) {
      if (!p.connected) continue;
      const projected = this.projector.projectEvent(id, event);
      if (projected) this.transport.send(id, { t: 'event', version: this.state.version, event: projected });
    }
  }

}
