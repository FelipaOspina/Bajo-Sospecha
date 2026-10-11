import type { IEventSink } from '../../core/EventBus.js';
import { fail, ok, type Result } from '../../core/Result.js';
import type { IRoleQuery } from '../roles/types.js';
import type { EvidenceSystem } from './EvidenceSystem.js';
import type { EvidenceActionConfig, EvidenceActionKind, IWorldQuery, PlayerId, Vec2 } from './types.js';

/** Acción en curso: el jugador debe quedarse quieto hasta `startedAt + durationMs`. */
export interface Channel {
  playerId: PlayerId;
  kind: EvidenceActionKind;
  label: string;
  instanceId: string;
  startedAt: number;
  durationMs: number;
  origin: Vec2;
}

export interface ChannelEvents {
  'channel.started': Channel;
  'channel.finished': { channel: Channel; ok: boolean; reason?: string };
}

/** Distancia que se tolera (jitter de red) antes de considerar que el jugador se ha movido. */
const MOVE_TOLERANCE = 6;

/** Ajustes por jugador (habilidades del animal): duración y cuánto puede moverse. */
export interface ChannelModifiers {
  /** Multiplica la duración de una acción que empieza ahora (<1 = más rápida). */
  durationMultiplier(playerId: PlayerId): number;
  /** Píxeles que puede moverse sin cortar la acción (como mínimo MOVE_TOLERANCE). */
  moveTolerance(playerId: PlayerId): number;
}

/**
 * Acciones con tiempo de canalización sobre pruebas (borrar logs, sacar una copia,
 * tomar una foto). Valida al empezar y otra vez al terminar; moverse, morir o
 * cambiar de fase la interrumpe. Al completarse delega en EvidenceSystem.
 */
export class ChannelSystem {
  private readonly active = new Map<PlayerId, Channel>();

  constructor(
    private readonly evidence: EvidenceSystem,
    private readonly roles: IRoleQuery,
    private readonly world: IWorldQuery,
    private readonly events: IEventSink<ChannelEvents>,
    private readonly modifiers?: ChannelModifiers,
  ) {}

  /** Acciones que este jugador podría hacer sobre la pieza (para pintar los botones). */
  availableActions(playerId: PlayerId, instanceId: string): EvidenceActionConfig[] {
    const def = this.evidence.definitionOf(instanceId);
    const roleId = this.roles.getRoleOf(playerId)?.id;
    if (!def?.actions || !roleId) return [];
    const isCopy = !!this.evidence.getInstance(instanceId)?.copyOf;
    // Una copia ya es la copia: no se vuelve a copiar.
    return def.actions.filter((a) => a.roles.includes(roleId) && !(isCopy && a.kind === 'backup'));
  }

  get(playerId: PlayerId): Channel | undefined { return this.active.get(playerId); }
  all(): Channel[] { return [...this.active.values()]; }

  start(playerId: PlayerId, instanceId: string, kind: EvidenceActionKind): Result<Channel> {
    if (this.world.currentPhase() !== 'investigation') return fail('wrong_phase');
    if (!this.world.isAlive(playerId)) return fail('not_alive');
    if (this.active.has(playerId)) return fail('already_channeling');
    const action = this.availableActions(playerId, instanceId).find((a) => a.kind === kind);
    if (!action) return fail('action_not_allowed');
    if (!this.evidence.reachable(playerId, instanceId)) return fail('out_of_range');

    const channel: Channel = {
      playerId, kind, instanceId, label: action.label,
      startedAt: this.world.now(),
      durationMs: Math.max(0, Math.round(action.seconds * 1000 * (this.modifiers?.durationMultiplier(playerId) ?? 1))),
      origin: { ...this.world.positionOf(playerId)! },
    };
    this.active.set(playerId, channel);
    this.events.emit('channel.started', channel);
    if (channel.durationMs === 0) this.complete(channel);
    return ok(channel);
  }

  cancel(playerId: PlayerId, reason = 'cancelled'): void {
    const c = this.active.get(playerId);
    if (!c) return;
    this.active.delete(playerId);
    this.events.emit('channel.finished', { channel: c, ok: false, reason });
  }

  /** Llamar cuando el servidor acepta un movimiento. */
  onMove(playerId: PlayerId, to: Vec2): void {
    const c = this.active.get(playerId);
    const tolerance = Math.max(MOVE_TOLERANCE, this.modifiers?.moveTolerance(playerId) ?? 0);
    if (c && Math.hypot(to.x - c.origin.x, to.y - c.origin.y) > tolerance) this.cancel(playerId, 'moved');
  }

  /** Llamar en cada tick: completa las que han cumplido su tiempo. */
  tick(): void {
    const now = this.world.now();
    for (const c of [...this.active.values()]) {
      if (this.world.currentPhase() !== 'investigation') { this.cancel(c.playerId, 'wrong_phase'); continue; }
      if (!this.world.isAlive(c.playerId)) { this.cancel(c.playerId, 'not_alive'); continue; }
      if (now >= c.startedAt + c.durationMs) this.complete(c);
    }
  }

  private complete(c: Channel): void {
    this.active.delete(c.playerId);
    if (!this.evidence.reachable(c.playerId, c.instanceId)) {
      this.events.emit('channel.finished', { channel: c, ok: false, reason: 'nothing_found' });
      return;
    }
    const r = c.kind === 'delete' ? this.evidence.forceDestroy(c.playerId, c.instanceId) : this.evidence.backup(c.playerId, c.instanceId);
    this.events.emit('channel.finished', r.ok ? { channel: c, ok: true } : { channel: c, ok: false, reason: r.error });
  }
}
