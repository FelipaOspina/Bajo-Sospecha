import type { Look } from '../cosmetics/CosmeticCatalog.js';

/** Moneda del juego: Monedas Corporativas (coins) o Créditos Nexus (credits). Sin dinero real. */
export type Currency = 'coins' | 'credits';
export type PassTrack = 'free' | 'premium';
export type Price = Partial<Record<Currency, number>>;

/** shared/config/progression/progression.json */
export interface ProgressionConfig {
  starting_coins: number;
  starting_credits: number;
  /** Animales de todos los perfiles: los 12 (gratis, con sus habilidades). */
  starter_skins: string[];
  /** Cosméticos con los que empieza cada perfil. */
  starter_cosmetics?: string[];
  /** Antiguo (lineal). Sin profile_level_curve se usa este valor fijo por nivel. */
  profile_xp_per_level: number;
  /** Curva creciente: XP del nivel N al N+1 = min(max_per_level, base + step × (N − 1)). */
  profile_level_curve?: LevelCurveConfig;
  /** Ruta del Detective: lecciones y retos por nivel, y la recompensa del tutorial. */
  detective_path?: DetectivePathConfig;
  match_rewards: { xp_played: number; xp_win: number; xp_per_objective: number; coins_played: number; coins_win: number };
  battle_pass: {
    id: string;
    name: string;
    season: string;
    max_level: number;
    xp_per_level: number;
    premium_price: Price;
    free_coins_per_level: number;
    premium_coins_per_level: number;
    /** Antiguo: el pase daba animales. Ahora todos son gratis y da cosméticos. */
    skin_rewards?: { level: number; track: PassTrack; skin: string }[];
    cosmetic_rewards?: { level: number; track: PassTrack; cosmetic: string }[];
    credit_rewards: { level: number; track: PassTrack; amount: number }[];
  };
  /** Precios de la tienda: solo cosméticos (skins queda por compatibilidad, vacío). */
  shop: { skins?: Record<string, Price>; cosmetics?: Record<string, Price> };
}

export interface LevelCurveConfig { base: number; step: number; max_per_level: number }

/** Reto de un nivel de la Ruta: `stat` de MatchActivity (o played/won/objectives/survived/tutorial).
 *  scope match = en una misma partida; total = acumulado entre partidas. */
export interface PathChallengeConfig {
  id: string;
  text: string;
  stat: string;
  target: number;
  scope: 'match' | 'total';
  xp: number;
  coins?: number;
}

export interface PathLevelConfig {
  level: number;
  title: string;
  /** Tarjeta de la lección (solo la pinta el cliente). */
  lesson?: Record<string, unknown>;
  challenge?: PathChallengeConfig;
  /** Al llegar al nivel: solo monedas o cosméticos (nada que dé ventaja). */
  reward?: { coins?: number; cosmetic?: string };
}

export interface DetectivePathConfig {
  name: string;
  tutorial_reward: { xp: number; coins: number };
  /** Hasta qué nivel se muestran los consejos en partida (el cliente). */
  hint_max_level?: number;
  levels: PathLevelConfig[];
}

/** Lo que hizo un jugador en una partida (lo cuenta Room; privado, solo para su perfil). */
export interface MatchActivity {
  collected: number;
  backups: number;
  presented: number;
  emergencyVotes: number;
  trialVotes: number;
  reported: number;
  meetings: number;
  chats: number;
  ghostTasks: number;
  abilities: number;
  /** Terminó la partida en pie (no fantasma). */
  survived: boolean;
}

/** Progreso en la Ruta del Detective. */
export interface PathProgress {
  tutorialDone: boolean;
  /** Retos cumplidos (ids). */
  done: string[];
  /** Retos acumulados (scope total) a medias: id → cuenta. */
  progress: Record<string, number>;
  /** Niveles cuya recompensa ya se entregó. */
  rewarded: number[];
}

/** Lo que se guarda de cada jugador (mock JSON; ver ProfileStore). */
export interface PlayerProfile {
  id: string;
  name: string;
  xp: number;
  coins: number;
  credits: number;
  pass: { id: string; xp: number; premium: boolean; claimed: Record<PassTrack, number[]> };
  /** Animales desbloqueados: todos (son gratis). */
  skins: string[];
  selectedSkin: string;
  /** Cosméticos que tiene y los que lleva puestos (un objeto por hueco). */
  cosmetics: string[];
  equipped: Look;
  stats: { played: number; won: number };
  /** Ruta del Detective (perfiles antiguos: se crea al cargar). */
  path?: PathProgress;
  createdAt: number;
  updatedAt: number;
}

export type PassReward =
  | { kind: 'coins'; amount: number }
  | { kind: 'credits'; amount: number }
  | { kind: 'skin'; skin: string }
  | { kind: 'cosmetic'; cosmetic: string };

export interface MatchResult { won: boolean; objectivesCompleted: number; activity?: MatchActivity }

/** Reto cumplido en esta partida (o con el tutorial). */
export interface ChallengeReward { id: string; text: string; level: number; xp: number; coins: number }
/** Recompensa por llegar a un nivel de la Ruta. */
export interface LevelReward { level: number; coins?: number; cosmetic?: string }

export interface MatchRewards {
  /** Total de XP ganada (partida + retos). */
  xp: number;
  coins: number;
  won: boolean;
  levelsGained: number;
  passLevelsGained: number;
  /** De dónde viene: una partida o el tutorial. */
  source?: 'match' | 'tutorial';
  /** XP solo de la partida (sin retos). */
  matchXp?: number;
  levelBefore?: number;
  level?: number;
  challenges?: ChallengeReward[];
  levelRewards?: LevelReward[];
}
