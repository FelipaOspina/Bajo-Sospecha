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
  profile_xp_per_level: number;
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
  createdAt: number;
  updatedAt: number;
}

export type PassReward =
  | { kind: 'coins'; amount: number }
  | { kind: 'credits'; amount: number }
  | { kind: 'skin'; skin: string }
  | { kind: 'cosmetic'; cosmetic: string };

export interface MatchResult { won: boolean; objectivesCompleted: number }

export interface MatchRewards {
  xp: number;
  coins: number;
  won: boolean;
  levelsGained: number;
  passLevelsGained: number;
}
