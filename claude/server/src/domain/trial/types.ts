import type { PlayerId } from '../../../../shared/protocol/protocol.js';

export interface TrialOptionConfig {
  id: string;
  label: string;
  description?: string;
  /** Si gana esta opción, se considera acusados a los jugadores con este rol. */
  accuses_role?: string;
}

export interface TrialConfig {
  /** Cuántas pruebas puede exponer cada jugador en la mesa. */
  max_presented_per_player?: number;
  /** Decisiones narrativas del escenario. */
  options?: TrialOptionConfig[];
  /** Añade "Acusar a <jugador>" por cada jugador. Por defecto: true si no hay options. */
  allow_player_accusation?: boolean;
  /** Añade "No acusar a nadie". Por defecto: true. */
  allow_abstain?: boolean;
  /** Muestra el recuento de votos en vivo. Por defecto: false (secreto hasta la resolución). */
  public_tally?: boolean;
}

/**
 * Condición de final. Un objeto con UNA clave:
 *   { "verdict": "id" | ["id", ...] }          ganó alguna de esas opciones
 *   { "revealed_all": ["CLUE_A", ...] }         todas expuestas en la mesa
 *   { "revealed_any": [...] }                   alguna expuesta
 *   { "revealed_count": { "tags": [...], "min": 2 } }
 *   { "destroyed_all": [...] } / { "destroyed_any": [...] }
 *   { "held_by_role": { "role": "ROLE_X", "evidence": "CLUE_Y" } }
 *   { "accused_role": "ROLE_X" }                el veredicto acusa a quien tiene ese rol
 *   { "all": [cond, ...] } / { "any": [cond, ...] } / { "not": cond }
 */
export type Condition = Record<string, unknown>;

export interface EndingConfig {
  id: string;
  title: string;
  description?: string;
  when: Condition;
  winners: { roles?: string[]; teams?: string[] };
}

/** Lo que una condición puede consultar al cerrar la partida. */
export interface ResolutionContext {
  verdictOptionId: string | null;
  accused: PlayerId[];
  roleOf(playerId: PlayerId): string | undefined;
  revealed: ReadonlySet<string>;          // ids de definición expuestos
  revealedTags: readonly string[][];
  destroyed: ReadonlySet<string>;         // ids de definición destruidos
  holdersOf(definitionId: string): PlayerId[];
}
