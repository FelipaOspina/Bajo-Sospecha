import type { DeckCard, PlayerId, VerdictOption } from '../../../../shared/protocol/protocol.js';
import { fail, ok, type Result } from '../../core/Result.js';
import type { TrialConfig, TrialOptionConfig } from './types.js';

export interface TrialPlayers {
  ids(): PlayerId[];
  nameOf(id: PlayerId): string;
  isAlive(id: PlayerId): boolean;
  playersWithRole(roleId: string): PlayerId[];
}

/** Lo que TrialSystem necesita del sistema de pruebas para exponer una. */
export interface IEvidencePresenter {
  present(playerId: PlayerId, instanceId: string): Result<unknown>;
}

export interface Verdict {
  optionId: string | null;
  label: string;
  tally: Record<string, number>;
  accused: PlayerId[];
}

const ACCUSE_PREFIX = 'accuse:';
const ABSTAIN_ID = 'abstain';

/**
 * Fase de confrontación:
 *  - Mesa pública (PublicEvidenceDeck): pruebas expuestas, visibles para todos.
 *  - Votación secreta a decisiones narrativas (del escenario o "Acusar a X").
 *  - Recuento y veredicto (empate = sin veredicto).
 */
export class TrialSystem {
  readonly deck: DeckCard[] = [];
  private readonly votes = new Map<PlayerId, string>();
  private readonly config: Required<Pick<TrialConfig, 'max_presented_per_player' | 'allow_player_accusation' | 'allow_abstain' | 'public_tally'>> & { options: TrialOptionConfig[] };

  constructor(
    config: TrialConfig | undefined,
    private readonly players: TrialPlayers,
    private readonly evidence: IEvidencePresenter,
    private readonly cardFor: (instanceId: string) => DeckCard['evidence'],
    private readonly now: () => number,
  ) {
    const options = config?.options ?? [];
    this.config = {
      options,
      max_presented_per_player: config?.max_presented_per_player ?? 2,
      allow_player_accusation: config?.allow_player_accusation ?? options.length === 0,
      allow_abstain: config?.allow_abstain ?? true,
      public_tally: config?.public_tally ?? false,
    };
  }

  get maxPresentedPerPlayer() { return this.config.max_presented_per_player; }
  get publicTally() { return this.config.public_tally; }

  /** Opciones actuales (las de "Acusar a X" dependen de quién está en la sala). */
  options(): VerdictOption[] {
    const out: VerdictOption[] = this.config.options.map(({ id, label, description, accuses_role }) => ({
      id, label, ...(description ? { description } : {}), ...(accuses_role ? { accusesRole: accuses_role } : {}),
    }));
    if (this.config.allow_player_accusation) {
      for (const p of this.players.ids()) out.push({ id: ACCUSE_PREFIX + p, label: `Acusar a ${this.players.nameOf(p)}` });
    }
    if (this.config.allow_abstain) out.push({ id: ABSTAIN_ID, label: 'No acusar a nadie' });
    return out;
  }

  // ───── Mesa pública ─────

  present(playerId: PlayerId, instanceId: string): Result<DeckCard> {
    if (this.deck.some((c) => c.instanceId === instanceId)) return fail('already_presented');
    if (this.deck.filter((c) => c.presentedBy === playerId).length >= this.config.max_presented_per_player) {
      return fail('present_limit');
    }
    const r = this.evidence.present(playerId, instanceId);
    if (!r.ok) return r;
    const card: DeckCard = { instanceId, presentedBy: playerId, at: this.now(), evidence: this.cardFor(instanceId) };
    this.deck.push(card);
    return ok(card);
  }

  // ───── Votación ─────

  vote(playerId: PlayerId, optionId: string | null): Result<null> {
    if (!this.players.isAlive(playerId)) return fail('not_alive');
    if (optionId === null) { this.votes.delete(playerId); return ok(null); }
    if (!this.options().some((o) => o.id === optionId)) return fail('unknown_option');
    this.votes.set(playerId, optionId);
    return ok(null);
  }

  voteOf(playerId: PlayerId): string | null { return this.votes.get(playerId) ?? null; }
  voters(): PlayerId[] { return [...this.votes.keys()]; }

  allVoted(): boolean {
    const alive = this.players.ids().filter((p) => this.players.isAlive(p));
    return alive.length > 0 && alive.every((p) => this.votes.has(p));
  }

  verdict(): Verdict {
    const tally: Record<string, number> = {};
    for (const v of this.votes.values()) tally[v] = (tally[v] ?? 0) + 1;
    const sorted = Object.entries(tally).sort((a, b) => b[1] - a[1]);
    const top = sorted[0];
    const tie = !top || (sorted[1] !== undefined && sorted[1][1] === top[1]);
    if (tie) return { optionId: null, label: top ? 'Sin veredicto (empate)' : 'Sin votos', tally, accused: [] };

    const optionId = top[0];
    const label = this.options().find((o) => o.id === optionId)?.label ?? optionId;
    return { optionId, label, tally, accused: this.accusedBy(optionId) };
  }

  private accusedBy(optionId: string): PlayerId[] {
    if (optionId.startsWith(ACCUSE_PREFIX)) return [optionId.slice(ACCUSE_PREFIX.length)];
    const role = this.config.options.find((o) => o.id === optionId)?.accuses_role;
    return role ? this.players.playersWithRole(role) : [];
  }
}
