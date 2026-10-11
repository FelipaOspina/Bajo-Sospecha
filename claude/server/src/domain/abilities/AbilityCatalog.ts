/**
 * shared/config/abilities/abilities.json: una pasiva y una activa por animal (skin).
 * Las habilidades van con el animal, que es gratis para todos: no se compran.
 */

/** Efectos de una habilidad. Multiplicadores salvo inventory (suma) y moveTolerance (px). */
export interface AbilityEffects {
  speed?: number;
  interactRange?: number;
  inventory?: number;
  channelSpeed?: number;
  watchRadius?: number;
  stealthRadius?: number;
  moveTolerance?: number;
  interruptImmune?: boolean;
  /** Solo visual (linterna del cliente). */
  flashlight?: number;
  colony?: { radius: number; channelSpeed: number };
  disguise?: string;
}

export interface PassiveAbility {
  id: string;
  name: string;
  description: string;
  trait?: string;
  effects: AbilityEffects;
}

export interface ActiveAbility {
  id: string;
  name: string;
  description: string;
  trait?: string;
  icon?: string;
  /** Segundos. */
  cooldown: number;
  duration?: number;
  /** 'nearby': los efectos también para quien esté a `radius` px. */
  area?: 'self' | 'nearby';
  radius?: number;
  /** scent: marca escondites con pruebas visibles; roar: corta acciones cercanas. */
  instant?: 'scent' | 'roar';
  /** Solo se entera quien la usa. */
  secret?: boolean;
  effects?: AbilityEffects;
}

export interface AnimalKit {
  passive: PassiveAbility;
  active: ActiveAbility;
}

export interface AbilityConfig {
  version: number;
  abilities: Record<string, AnimalKit>;
}

const MULTIPLIERS = ['speed', 'interactRange', 'channelSpeed', 'watchRadius', 'stealthRadius', 'flashlight'] as const;
/** Lo que cambia las estadísticas del jugador solo puede ser pasivo (se calcula una vez). */
const PASSIVE_ONLY = ['interactRange', 'inventory'] as const;
/** Topes de cordura: ninguna habilidad puede romper el juego aunque se edite mal el JSON. */
const LIMITS: Record<(typeof MULTIPLIERS)[number], [number, number]> = {
  speed: [0.5, 2.5], interactRange: [0.5, 2], channelSpeed: [0.3, 2], watchRadius: [0.3, 3], stealthRadius: [0, 2], flashlight: [0.5, 2],
};

export class AbilityCatalog {
  constructor(private readonly config: AbilityConfig) {
    for (const [animal, kit] of Object.entries(config.abilities)) {
      const where = `habilidades de ${animal}`;
      if (!kit.passive?.id || !kit.active?.id) throw new Error(`${where}: falta la pasiva o la activa`);
      if (!(kit.active.cooldown > 0)) throw new Error(`${where}: cooldown debe ser > 0`);
      if (kit.active.instant && !(Number(kit.active.radius) > 0)) throw new Error(`${where}: ${kit.active.instant} necesita radius`);
      if (kit.active.area === 'nearby' && !(Number(kit.active.radius) > 0)) throw new Error(`${where}: area nearby necesita radius`);
      if ((kit.active.effects || kit.active.instant === 'scent') && !(Number(kit.active.duration) > 0)) throw new Error(`${where}: falta duration`);
      for (const effects of [kit.passive.effects, kit.active.effects]) {
        for (const key of MULTIPLIERS) {
          const v = effects?.[key];
          if (v !== undefined && !(v >= LIMITS[key][0] && v <= LIMITS[key][1])) throw new Error(`${where}: ${key}=${v} fuera de [${LIMITS[key]}]`);
        }
      }
      for (const key of PASSIVE_ONLY) {
        if (kit.active.effects?.[key] !== undefined) throw new Error(`${where}: ${key} solo puede ser pasiva`);
      }
      const inv = kit.passive.effects?.inventory;
      if (inv !== undefined && !(Number.isInteger(inv) && inv >= 0 && inv <= 3)) throw new Error(`${where}: inventory debe ser 0..3`);
    }
  }

  animals(): string[] { return Object.keys(this.config.abilities); }

  forSkin(skinId: string | undefined): AnimalKit | undefined {
    return skinId ? this.config.abilities[skinId] : undefined;
  }
}
