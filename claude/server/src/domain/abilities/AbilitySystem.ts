import { fail, ok, type Result } from '../../core/Result.js';
import type { PlayerId, RoomPhase, Vec2 } from '../../../../shared/protocol/protocol.js';
import type { AbilityCatalog, AbilityEffects, AnimalKit } from './AbilityCatalog.js';

export interface AbilityWorld {
  players(): PlayerId[];
  skinOf(playerId: PlayerId): string | undefined;
  positionOf(playerId: PlayerId): Vec2 | undefined;
  isAlive(playerId: PlayerId): boolean;
  currentPhase(): RoomPhase;
  now(): number;
}

/** Lo que una habilidad instantánea hace fuera de este sistema. */
export interface AbilityHooks {
  /** Rugido: cortar la acción en curso de este jugador (true si tenía una). */
  interrupt(playerId: PlayerId): boolean;
  /** Olfato: escondites a `radius` px con pruebas que este jugador puede percibir. */
  scent(playerId: PlayerId, radius: number): string[];
}

/** Resultado de usar la activa (va al evento ability_used). */
export interface AbilityUse {
  by: PlayerId;
  abilityId: string;
  endsAt: number | null;
  readyAt: number;
  secret: boolean;
  /** Olfato: ids de los escondites marcados (solo para quien la usa). */
  marks?: string[];
  /** Aullido/rugido: a quién ha afectado. */
  affected?: PlayerId[];
}

/** Efectos ya combinados de un jugador en un instante. */
export interface EffectiveAbilities {
  speed: number;
  interactRange: number;
  inventory: number;
  channelSpeed: number;
  watchRadius: number;
  stealthRadius: number;
  moveTolerance: number;
  interruptImmune: boolean;
  colony?: { radius: number; channelSpeed: number };
  disguise?: string;
}

interface Buff { from: PlayerId; abilityId: string; until: number; effects: AbilityEffects }

/** Tras acabar un acelerón, el servidor tolera la velocidad un poco más (latencia). */
export const SPEED_GRACE_MS = 600;

const BASE = (): EffectiveAbilities => ({
  speed: 1, interactRange: 1, inventory: 0, channelSpeed: 1, watchRadius: 1, stealthRadius: 1, moveTolerance: 0, interruptImmune: false,
});

const dist = (a: Vec2, b: Vec2) => Math.hypot(a.x - b.x, a.y - b.y);

/**
 * Habilidades tácticas por animal, autoritativas: el cliente solo pide usar la activa
 * ('use_ability') y el servidor comprueba fase, vida y enfriamiento, aplica el efecto
 * y expone los efectos combinados a los demás sistemas (movimiento, acciones
 * canalizadas, quién ve qué barra, inventario y alcance).
 *
 * La habilidad sale del animal (skin pública), nunca del rol, y ningún efecto da
 * información sobre roles.
 */
export class AbilitySystem {
  private readonly readyAt = new Map<PlayerId, number>();
  private readonly buffs = new Map<PlayerId, Buff[]>();

  constructor(
    private readonly catalog: AbilityCatalog,
    private readonly world: AbilityWorld,
    private readonly hooks: AbilityHooks,
  ) {}

  kitOf(playerId: PlayerId): AnimalKit | undefined {
    return this.catalog.forSkin(this.world.skinOf(playerId));
  }

  /** Nueva investigación: todas las activas disponibles y sin efectos en curso. */
  reset(): void {
    this.readyAt.clear();
    this.buffs.clear();
  }

  use(playerId: PlayerId): Result<AbilityUse> {
    if (this.world.currentPhase() !== 'investigation') return fail('wrong_phase');
    if (!this.world.isAlive(playerId)) return fail('not_alive');
    const kit = this.kitOf(playerId);
    if (!kit) return fail('no_ability');
    const now = this.world.now();
    if (now < (this.readyAt.get(playerId) ?? 0)) return fail('on_cooldown');

    const a = kit.active;
    const readyAt = now + a.cooldown * 1000;
    const endsAt = a.duration ? now + a.duration * 1000 : null;
    this.readyAt.set(playerId, readyAt);
    const use: AbilityUse = { by: playerId, abilityId: a.id, endsAt, readyAt, secret: a.secret === true };

    if (a.instant === 'roar') {
      use.affected = this.nearby(playerId, a.radius ?? 0)
        .filter((p) => !this.effects(p, now).interruptImmune)
        .filter((p) => this.hooks.interrupt(p));
    }
    if (a.instant === 'scent') use.marks = this.hooks.scent(playerId, a.radius ?? 0);
    if (endsAt !== null) {
      // Con duración: un efecto temporal (vacío si solo marca, como el olfato) para saber hasta cuándo dura.
      const targets = a.effects && a.area === 'nearby' ? [playerId, ...this.nearby(playerId, a.radius ?? 0)] : [playerId];
      for (const p of targets) {
        const list = (this.buffs.get(p) ?? []).filter((b) => b.until > now - SPEED_GRACE_MS && !(b.from === playerId && b.abilityId === a.id));
        list.push({ from: playerId, abilityId: a.id, until: endsAt, effects: a.effects ?? {} });
        this.buffs.set(p, list);
      }
      if (a.effects && a.area === 'nearby') use.affected = targets.filter((p) => p !== playerId);
    }
    return ok(use);
  }

  /** Efectos combinados: la pasiva del animal más lo que siga activo en `at`. */
  effects(playerId: PlayerId, at = this.world.now()): EffectiveAbilities {
    const out = BASE();
    const kit = this.kitOf(playerId);
    const apply = (e: AbilityEffects | undefined) => {
      if (!e) return;
      if (e.speed !== undefined) out.speed *= e.speed;
      if (e.interactRange !== undefined) out.interactRange *= e.interactRange;
      if (e.channelSpeed !== undefined) out.channelSpeed *= e.channelSpeed;
      if (e.watchRadius !== undefined) out.watchRadius *= e.watchRadius;
      if (e.stealthRadius !== undefined) out.stealthRadius *= e.stealthRadius;
      if (e.inventory !== undefined) out.inventory += e.inventory;
      if (e.moveTolerance !== undefined) out.moveTolerance = Math.max(out.moveTolerance, e.moveTolerance);
      if (e.interruptImmune) out.interruptImmune = true;
      if (e.colony) out.colony = e.colony;
      if (e.disguise) out.disguise = e.disguise;
    };
    apply(kit?.passive.effects);
    for (const b of this.buffs.get(playerId) ?? []) if (b.until > at) apply(b.effects);
    return out;
  }

  /** Velocidad máxima permitida (con margen tras acabar un acelerón). */
  speedMultiplier(playerId: PlayerId): number {
    const now = this.world.now();
    return Math.max(this.effects(playerId, now).speed, this.effects(playerId, now - SPEED_GRACE_MS).speed);
  }

  /** Multiplicador de la duración de una acción que empieza ahora (incluye la colonia). */
  channelMultiplier(playerId: PlayerId): number {
    const e = this.effects(playerId);
    let m = e.channelSpeed;
    if (e.colony && this.nearby(playerId, e.colony.radius).length > 0) m *= e.colony.channelSpeed;
    return m;
  }

  /** Para el cliente: su activa, cuándo vuelve a estar lista y hasta cuándo dura. */
  stateFor(playerId: PlayerId): { id: string; readyAt: number; activeUntil: number | null; cooldownMs: number } | undefined {
    const kit = this.kitOf(playerId);
    if (!kit) return undefined;
    const now = this.world.now();
    const own = (this.buffs.get(playerId) ?? []).filter((b) => b.from === playerId && b.abilityId === kit.active.id && b.until > now);
    return {
      id: kit.active.id,
      readyAt: this.readyAt.get(playerId) ?? 0,
      activeUntil: own.length ? Math.max(...own.map((b) => b.until)) : null,
      cooldownMs: kit.active.cooldown * 1000,
    };
  }

  private nearby(playerId: PlayerId, radius: number): PlayerId[] {
    const here = this.world.positionOf(playerId);
    if (!here) return [];
    return this.world.players().filter((p) => {
      if (p === playerId || !this.world.isAlive(p)) return false;
      const there = this.world.positionOf(p);
      return !!there && dist(here, there) <= radius;
    });
  }
}
