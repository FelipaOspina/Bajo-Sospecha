import { randomUUID } from 'node:crypto';
import { fail, ok, type Result } from '../../core/Result.js';
import type { ProfileStore } from './ProfileStore.js';
import { COSMETIC_SLOTS, type CosmeticSlot, type ICosmeticCatalog } from '../cosmetics/CosmeticCatalog.js';
import type {
  ChallengeReward, Currency, LevelReward, MatchResult, MatchRewards, PassReward, PassTrack, PathProgress, PlayerProfile, Price, ProgressionConfig,
} from './types.js';
import { emptyActivity, levelProgress, pathLevels, statValue } from './DetectivePath.js';

const ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

const NO_COSMETICS: ICosmeticCatalog = { has: () => false, slotOf: () => undefined };

/**
 * Perfil, economía y Executive Pass. Todo lo decide el servidor: el cliente solo pide
 * (reclamar, comprar, ponerse algo, elegir animal) y recibe el perfil actualizado.
 * Sin pagos reales y sin pagar por ventaja: los 12 animales y sus habilidades son de
 * todos; con monedas del juego solo se compran el Premium y cosméticos.
 */
export class ProfileService {
  constructor(
    readonly config: ProgressionConfig,
    private readonly store: ProfileStore,
    private readonly catalog: { has(skinId: string): boolean },
    private readonly now: () => number = () => Date.now(),
    private readonly newId: () => string = () => randomUUID(),
    private readonly cosmetics: ICosmeticCatalog = NO_COSMETICS,
  ) {}

  /** Perfil por id; si no existe (o el id no es válido) crea uno nuevo. */
  load(id: string | undefined, name: string): PlayerProfile {
    const existing = id && ID_PATTERN.test(id) ? this.store.get(id) : undefined;
    if (existing) {
      const migrated = this.migrate(existing);
      const renamed = !!name && existing.name !== name;
      if (renamed) existing.name = name;
      if (migrated || renamed) this.save(existing);
      return existing;
    }
    const starters = this.starterSkins();
    const profile: PlayerProfile = {
      id: id && ID_PATTERN.test(id) ? id : this.newId(),
      name: name || 'Jugador',
      xp: 0,
      coins: this.config.starting_coins,
      credits: this.config.starting_credits,
      pass: { id: this.config.battle_pass.id, xp: 0, premium: false, claimed: { free: [], premium: [] } },
      skins: starters,
      selectedSkin: starters[0] ?? '',
      cosmetics: this.starterCosmetics(),
      equipped: {},
      stats: { played: 0, won: 0 },
      path: ProfileService.freshPath(),
      createdAt: this.now(),
      updatedAt: this.now(),
    };
    this.save(profile);
    return profile;
  }

  /** Perfiles anteriores a la economía actual: reciben todos los animales y los cosméticos de inicio. */
  private migrate(p: PlayerProfile): boolean {
    const before = JSON.stringify([p.skins, p.cosmetics, p.equipped, p.path, p.coins]);
    p.skins = [...new Set([...(p.skins ?? []), ...this.starterSkins()])];
    p.cosmetics = [...new Set([...(p.cosmetics ?? []), ...this.starterCosmetics()])];
    p.equipped ??= {};
    p.path = { ...ProfileService.freshPath(), ...(p.path ?? {}) };
    // Perfiles con XP de antes de la Ruta: reciben las recompensas de los niveles que ya tienen.
    this.settleLevelRewards(p);
    return JSON.stringify([p.skins, p.cosmetics, p.equipped, p.path, p.coins]) !== before;
  }

  static freshPath(): PathProgress {
    return { tutorialDone: false, done: [], progress: {}, rewarded: [1] };
  }

  private pathOf(p: PlayerProfile): PathProgress {
    p.path ??= ProfileService.freshPath();
    return p.path;
  }

  private starterSkins(): string[] {
    return this.config.starter_skins.filter((s) => this.catalog.has(s));
  }

  private starterCosmetics(): string[] {
    return (this.config.starter_cosmetics ?? []).filter((c) => this.cosmetics.has(c));
  }

  // ───── Niveles ─────

  /** Nivel del perfil con la curva creciente (profile_level_curve; sin ella, lineal). */
  level(xp: number): number {
    return levelProgress(xp, this.config).level;
  }

  passLevel(passXp: number): number {
    const bp = this.config.battle_pass;
    return Math.min(bp.max_level, 1 + Math.floor(passXp / bp.xp_per_level));
  }

  /** Recompensa de un nivel del pase en una pista: cosmético, créditos o monedas. */
  rewardAt(level: number, track: PassTrack): PassReward {
    const bp = this.config.battle_pass;
    const cosmetic = bp.cosmetic_rewards?.find((r) => r.level === level && r.track === track);
    if (cosmetic) return { kind: 'cosmetic', cosmetic: cosmetic.cosmetic };
    const skin = bp.skin_rewards?.find((r) => r.level === level && r.track === track);
    if (skin) return { kind: 'skin', skin: skin.skin };
    const credits = bp.credit_rewards.find((r) => r.level === level && r.track === track);
    if (credits) return { kind: 'credits', amount: credits.amount };
    return { kind: 'coins', amount: track === 'free' ? bp.free_coins_per_level : bp.premium_coins_per_level };
  }

  /** Niveles alcanzados y sin reclamar (premium solo si se tiene el pase). */
  claimable(p: PlayerProfile): Record<PassTrack, number[]> {
    const reached = this.passLevel(p.pass.xp);
    const pending = (track: PassTrack) =>
      Array.from({ length: reached }, (_, i) => i + 1).filter((l) => !p.pass.claimed[track].includes(l));
    return { free: pending('free'), premium: p.pass.premium ? pending('premium') : [] };
  }

  // ───── Acciones del jugador ─────

  claim(p: PlayerProfile, level: number, track: PassTrack): Result<PassReward> {
    if (track !== 'free' && track !== 'premium') return fail('bad_track');
    if (!Number.isInteger(level) || level < 1 || level > this.config.battle_pass.max_level) return fail('bad_level');
    if (level > this.passLevel(p.pass.xp)) return fail('level_not_reached');
    if (track === 'premium' && !p.pass.premium) return fail('premium_required');
    if (p.pass.claimed[track].includes(level)) return fail('already_claimed');
    const reward = this.rewardAt(level, track);
    if (reward.kind === 'skin') {
      if (!p.skins.includes(reward.skin)) p.skins.push(reward.skin);
    } else if (reward.kind === 'cosmetic') {
      if (!p.cosmetics.includes(reward.cosmetic)) p.cosmetics.push(reward.cosmetic);
    } else {
      p[reward.kind] += reward.amount;
    }
    p.pass.claimed[track].push(level);
    this.save(p);
    return ok(reward);
  }

  /** Los animales ya son gratis: queda por compatibilidad (casi siempre already_owned). */
  buySkin(p: PlayerProfile, skinId: string): Result<null> {
    if (!this.catalog.has(skinId)) return fail('unknown_skin');
    if (p.skins.includes(skinId)) return fail('already_owned');
    const price = this.config.shop.skins?.[skinId];
    if (!price) return fail('not_for_sale');
    const paid = this.pay(p, price);
    if (!paid.ok) return paid;
    p.skins.push(skinId);
    this.save(p);
    return ok(null);
  }

  buyCosmetic(p: PlayerProfile, cosmeticId: string): Result<null> {
    if (!this.cosmetics.has(cosmeticId)) return fail('unknown_cosmetic');
    if (p.cosmetics.includes(cosmeticId)) return fail('already_owned');
    const price = this.config.shop.cosmetics?.[cosmeticId];
    if (!price) return fail('not_for_sale');
    const paid = this.pay(p, price);
    if (!paid.ok) return paid;
    p.cosmetics.push(cosmeticId);
    this.save(p);
    return ok(null);
  }

  /** Ponerse un cosmético que tienes en su hueco, o quitarse el del hueco (null). */
  equipCosmetic(p: PlayerProfile, slot: CosmeticSlot, cosmeticId: string | null): Result<null> {
    if (!COSMETIC_SLOTS.includes(slot)) return fail('bad_slot');
    if (cosmeticId === null) {
      delete p.equipped[slot];
    } else {
      if (!this.cosmetics.has(cosmeticId)) return fail('unknown_cosmetic');
      if (this.cosmetics.slotOf(cosmeticId) !== slot) return fail('wrong_slot');
      if (!p.cosmetics.includes(cosmeticId)) return fail('cosmetic_locked');
      p.equipped[slot] = cosmeticId;
    }
    this.save(p);
    return ok(null);
  }

  buyPremium(p: PlayerProfile): Result<null> {
    if (p.pass.premium) return fail('already_owned');
    const paid = this.pay(p, this.config.battle_pass.premium_price);
    if (!paid.ok) return paid;
    p.pass.premium = true;
    this.save(p);
    return ok(null);
  }

  /** Skin preferida: la que el servidor intenta darte al entrar en una sala. */
  selectSkin(p: PlayerProfile, skinId: string): Result<null> {
    if (!p.skins.includes(skinId)) return fail('skin_locked');
    p.selectedSkin = skinId;
    this.save(p);
    return ok(null);
  }

  /**
   * Al terminar una partida: XP para el perfil y para el pase, monedas, retos de la Ruta del
   * Detective cumplidos (con lo que contó Room de esta partida) y recompensas de nivel.
   * Los retos activos son los de los niveles que ya tenías al empezar la partida.
   */
  grantMatch(p: PlayerProfile, result: MatchResult): MatchRewards {
    const r = this.config.match_rewards;
    const matchXp = r.xp_played + (result.won ? r.xp_win : 0) + r.xp_per_objective * Math.max(0, result.objectivesCompleted);
    const matchCoins = r.coins_played + (result.won ? r.coins_win : 0);
    const levelBefore = this.level(p.xp);
    const passBefore = this.passLevel(p.pass.xp);
    const challenges = this.evaluateChallenges(p, levelBefore, result);
    const xp = matchXp + challenges.reduce((a, c) => a + c.xp, 0);
    const coinsBefore = p.coins;
    p.xp += xp;
    p.pass.xp += xp;
    p.coins += matchCoins + challenges.reduce((a, c) => a + c.coins, 0);
    p.stats.played += 1;
    if (result.won) p.stats.won += 1;
    const levelRewards = this.settleLevelRewards(p);
    this.save(p);
    const level = this.level(p.xp);
    return {
      source: 'match',
      xp, matchXp, coins: p.coins - coinsBefore, won: result.won,
      levelsGained: level - levelBefore,
      passLevelsGained: this.passLevel(p.pass.xp) - passBefore,
      levelBefore, level, challenges, levelRewards,
    };
  }

  /** Marca los retos cumplidos en esta partida y devuelve los nuevos (con su XP y monedas). */
  private evaluateChallenges(p: PlayerProfile, level: number, result: MatchResult): ChallengeReward[] {
    const path = this.pathOf(p);
    const activity = result.activity ?? emptyActivity();
    const out: ChallengeReward[] = [];
    for (const l of pathLevels(this.config)) {
      const c = l.challenge;
      if (!c || l.level > level || path.done.includes(c.id) || c.stat === 'tutorial') continue;
      const value = statValue(c.stat, activity, result);
      let reached: boolean;
      if (c.scope === 'total') {
        const total = (path.progress[c.id] ?? 0) + value;
        reached = total >= c.target;
        if (reached) delete path.progress[c.id];
        else if (value > 0) path.progress[c.id] = total;
      } else {
        reached = value >= c.target;
      }
      if (!reached) continue;
      path.done.push(c.id);
      out.push({ id: c.id, text: c.text, level: l.level, xp: c.xp, coins: c.coins ?? 0 });
    }
    return out;
  }

  /** Recompensas (monedas o cosméticos) de los niveles de la Ruta alcanzados y aún sin entregar. */
  private settleLevelRewards(p: PlayerProfile): LevelReward[] {
    const path = this.pathOf(p);
    const level = this.level(p.xp);
    const out: LevelReward[] = [];
    for (const l of pathLevels(this.config)) {
      if (l.level > level || path.rewarded.includes(l.level)) continue;
      path.rewarded.push(l.level);
      if (!l.reward) continue;
      const given: LevelReward = { level: l.level };
      if (l.reward.coins) { p.coins += l.reward.coins; given.coins = l.reward.coins; }
      if (l.reward.cosmetic && this.cosmetics.has(l.reward.cosmetic)) {
        if (!p.cosmetics.includes(l.reward.cosmetic)) p.cosmetics.push(l.reward.cosmetic);
        given.cosmetic = l.reward.cosmetic;
      }
      if (given.coins || given.cosmetic) out.push(given);
    }
    return out;
  }

  /**
   * Tutorial «Primer día en NexusCore» (práctica local): su recompensa se entrega una sola vez
   * por perfil. Cuenta como el reto del nivel 1 de la Ruta.
   */
  completeTutorial(p: PlayerProfile): Result<MatchRewards> {
    const path = this.pathOf(p);
    if (path.tutorialDone) return fail('already_claimed');
    const reward = this.config.detective_path?.tutorial_reward ?? { xp: 0, coins: 0 };
    const levelBefore = this.level(p.xp);
    const passBefore = this.passLevel(p.pass.xp);
    const coinsBefore = p.coins;
    path.tutorialDone = true;
    const first = pathLevels(this.config).find((l) => l.challenge?.stat === 'tutorial');
    const challenges: ChallengeReward[] = [];
    if (first?.challenge && !path.done.includes(first.challenge.id)) {
      path.done.push(first.challenge.id);
      challenges.push({ id: first.challenge.id, text: first.challenge.text, level: first.level, xp: reward.xp, coins: reward.coins });
    }
    p.xp += reward.xp;
    p.pass.xp += reward.xp;
    p.coins += reward.coins;
    const levelRewards = this.settleLevelRewards(p);
    this.save(p);
    const level = this.level(p.xp);
    return ok({
      source: 'tutorial', xp: reward.xp, matchXp: 0, coins: p.coins - coinsBefore, won: false,
      levelsGained: level - levelBefore, passLevelsGained: this.passLevel(p.pass.xp) - passBefore,
      levelBefore, level, challenges, levelRewards,
    });
  }

  /** Lo que se envía al cliente: el perfil y los valores derivados para pintar barras. */
  view(p: PlayerProfile) {
    const bp = this.config.battle_pass;
    const progress = levelProgress(p.xp, this.config);
    const passLevel = this.passLevel(p.pass.xp);
    return {
      ...structuredClone(p),
      path: structuredClone(this.pathOf(p)),
      level: progress.level,
      xpIntoLevel: progress.into,
      xpForLevel: progress.need,
      pass: {
        ...structuredClone(p.pass),
        name: bp.name,
        season: bp.season,
        level: passLevel,
        maxLevel: bp.max_level,
        xpIntoLevel: passLevel >= bp.max_level ? bp.xp_per_level : p.pass.xp - (passLevel - 1) * bp.xp_per_level,
        xpForLevel: bp.xp_per_level,
        claimable: this.claimable(p),
      },
    };
  }

  private pay(p: PlayerProfile, price: Price): Result<null> {
    for (const [currency, amount] of Object.entries(price) as [Currency, number][]) {
      if (p[currency] < amount) return fail(currency === 'coins' ? 'not_enough_coins' : 'not_enough_credits');
    }
    for (const [currency, amount] of Object.entries(price) as [Currency, number][]) p[currency] -= amount;
    return ok(null);
  }

  private save(p: PlayerProfile): void {
    p.updatedAt = this.now();
    this.store.put(p);
  }
}

export type ProfileView = ReturnType<ProfileService['view']>;
