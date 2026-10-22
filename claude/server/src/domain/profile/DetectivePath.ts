import type { LevelCurveConfig, MatchActivity, PathChallengeConfig, PathLevelConfig, ProgressionConfig } from './types.js';

/**
 * Curva de niveles del perfil y retos de la Ruta del Detective (funciones puras).
 * El servidor decide; el cliente replica la curva (scripts/menu/DetectivePath.gd) solo para pintar.
 */

/** XP que hace falta para pasar del nivel `level` al siguiente. */
export function xpForLevel(level: number, config: Pick<ProgressionConfig, 'profile_level_curve' | 'profile_xp_per_level'>): number {
  const c = config.profile_level_curve;
  if (!c) return config.profile_xp_per_level;
  return Math.min(c.max_per_level, c.base + c.step * Math.max(0, level - 1));
}

/** XP total acumulada para estar justo al principio de `level`. */
export function xpToReach(level: number, config: Pick<ProgressionConfig, 'profile_level_curve' | 'profile_xp_per_level'>): number {
  let total = 0;
  for (let l = 1; l < level; l++) total += xpForLevel(l, config);
  return total;
}

/** Nivel con esa XP, cuánta lleva dentro del nivel y cuánta necesita para el siguiente. */
export function levelProgress(xp: number, config: Pick<ProgressionConfig, 'profile_level_curve' | 'profile_xp_per_level'>): { level: number; into: number; need: number } {
  let level = 1;
  let left = Math.max(0, Math.floor(xp));
  // Tope de seguridad: con max_per_level ≥ 1 el bucle siempre termina.
  for (;;) {
    const need = Math.max(1, xpForLevel(level, config));
    if (left < need || level >= 999) return { level, into: left, need };
    left -= need;
    level += 1;
  }
}

/** Contadores de una partida vacíos (los rellena Room con lo que hace cada jugador). */
export function emptyActivity(): MatchActivity {
  return { collected: 0, backups: 0, presented: 0, emergencyVotes: 0, trialVotes: 0, reported: 0, meetings: 0, chats: 0, ghostTasks: 0, abilities: 0, survived: false };
}

/** Lo que cuenta un reto en esta partida (estadísticas de Room + resultado). */
export function statValue(stat: string, activity: MatchActivity, result: { won: boolean; objectivesCompleted: number }): number {
  switch (stat) {
    case 'played': return 1;
    case 'won': return result.won ? 1 : 0;
    case 'objectives': return Math.max(0, result.objectivesCompleted);
    case 'survived': return activity.survived ? 1 : 0;
    case 'tutorial': return 0;   // solo con claim_tutorial_reward
    default: {
      const v = (activity as unknown as Record<string, unknown>)[stat];
      return typeof v === 'number' ? v : 0;
    }
  }
}

export function pathLevels(config: ProgressionConfig): PathLevelConfig[] {
  return config.detective_path?.levels ?? [];
}

export function challengeById(config: ProgressionConfig, id: string): { level: number; challenge: PathChallengeConfig } | undefined {
  for (const l of pathLevels(config)) if (l.challenge?.id === id) return { level: l.level, challenge: l.challenge };
  return undefined;
}

/** Estadísticas que ningún reto puede usar: delatarían un rol (silenciar, borrar, escoltar). */
export const FORBIDDEN_STATS: ReadonlySet<string> = new Set(['silenced', 'silences', 'kills', 'destroyed', 'deleted', 'escorts']);

export type { LevelCurveConfig };
