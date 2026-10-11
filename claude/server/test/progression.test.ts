import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { ProfileService } from '../src/domain/profile/ProfileService.js';
import { InMemoryProfileStore, JsonFileProfileStore } from '../src/domain/profile/ProfileStore.js';
import type { PlayerProfile, ProgressionConfig } from '../src/domain/profile/types.js';
import { CosmeticCatalog, type CosmeticConfig } from '../src/domain/cosmetics/CosmeticCatalog.js';

const cfgUrl = (p: string) => fileURLToPath(new URL(`../../../../shared/config/${p}`, import.meta.url));
const config = async () => JSON.parse(await readFile(cfgUrl('progression/progression.json'), 'utf8')) as ProgressionConfig;
const skins = async () => (JSON.parse(await readFile(cfgUrl('skins/skins.json'), 'utf8')) as { skins: { id: string }[] }).skins.map((s) => s.id);
const cosmetics = async () => new CosmeticCatalog(JSON.parse(await readFile(cfgUrl('cosmetics/cosmetics.json'), 'utf8')) as CosmeticConfig);

async function service() {
  const ids = await skins();
  const store = new InMemoryProfileStore();
  let n = 0;
  return { svc: new ProfileService(await config(), store, { has: (s) => ids.includes(s) }, () => 1000, () => `perfil-${++n}-xxxxxxxx`, await cosmetics()), store };
}

test('perfil nuevo: los 12 animales, cosméticos de inicio, monedas y pase en el nivel 1', async () => {
  const { svc, store } = await service();
  const cfg = await config();
  const p = svc.load(undefined, 'Ana');
  assert.match(p.id, /^perfil-1/);
  assert.deepEqual([...p.skins].sort(), [...await skins()].sort(), 'todos los animales (y sus habilidades) son de todos');
  assert.deepEqual(p.cosmetics, cfg.starter_cosmetics);
  assert.deepEqual(p.equipped, {});
  assert.equal(p.coins, cfg.starting_coins);
  assert.equal(p.credits, cfg.starting_credits);
  const v = svc.view(p);
  assert.equal(v.level, 1);
  assert.equal(v.pass.level, 1);
  assert.equal(v.pass.maxLevel, 50);
  assert.deepEqual(v.pass.claimable, { free: [1], premium: [] }, 'premium bloqueado sin el pase');
  assert.equal(svc.load(p.id, 'Ana B').name, 'Ana B', 'mismo id = mismo perfil');
  assert.equal(store.profiles.size, 1);
  assert.notEqual(svc.load('corto', 'X').id, 'corto', 'un id inválido no se usa');
});

test('partida: XP para perfil y pase, monedas y subidas de nivel', async () => {
  const { svc } = await service();
  const cfg = await config();
  const p = svc.load(undefined, 'Ana');
  const r = svc.grantMatch(p, { won: true, objectivesCompleted: 2 });
  const xp = cfg.match_rewards.xp_played + cfg.match_rewards.xp_win + 2 * cfg.match_rewards.xp_per_objective;
  assert.deepEqual(r, { xp, coins: cfg.match_rewards.coins_played + cfg.match_rewards.coins_win, won: true, levelsGained: 0, passLevelsGained: Math.floor(xp / cfg.battle_pass.xp_per_level) });
  assert.equal(p.stats.won, 1);
  for (let i = 0; i < 400; i++) svc.grantMatch(p, { won: false, objectivesCompleted: 0 });
  assert.equal(svc.view(p).pass.level, 50, 'el pase se queda en 50');
  assert.ok(svc.view(p).level > 40);
});

test('Executive Pass: reclamar gratis y premium, cosméticos y créditos', async () => {
  const { svc } = await service();
  const cfg = await config();
  const p = svc.load(undefined, 'Ana');
  assert.deepEqual(svc.claim(p, 2, 'free'), { ok: false, error: 'level_not_reached' });
  const coins = p.coins;
  assert.deepEqual(svc.claim(p, 1, 'free'), { ok: true, value: { kind: 'coins', amount: cfg.battle_pass.free_coins_per_level } });
  assert.equal(p.coins, coins + cfg.battle_pass.free_coins_per_level);
  assert.deepEqual(svc.claim(p, 1, 'free'), { ok: false, error: 'already_claimed' });

  p.pass.xp = 9 * cfg.battle_pass.xp_per_level;   // nivel 10
  assert.deepEqual(svc.claim(p, 5, 'free'), { ok: true, value: { kind: 'cosmetic', cosmetic: 'mochila_naranja' } });
  assert.ok(p.cosmetics.includes('mochila_naranja'));
  assert.deepEqual(svc.claim(p, 10, 'free'), { ok: true, value: { kind: 'credits', amount: 20 } });
  assert.deepEqual(svc.claim(p, 10, 'premium'), { ok: false, error: 'premium_required' });

  assert.deepEqual(svc.buyPremium(p), { ok: false, error: 'not_enough_coins' });
  p.coins = 1000;
  assert.ok(svc.buyPremium(p).ok);
  assert.equal(p.coins, 1000 - (cfg.battle_pass.premium_price.coins ?? 0));
  assert.deepEqual(svc.claim(p, 10, 'premium'), { ok: true, value: { kind: 'cosmetic', cosmetic: 'traje_burdeos' } });
  // Ninguna recompensa del pase es un animal: no se paga por ventaja.
  for (let l = 1; l <= cfg.battle_pass.max_level; l++) {
    for (const t of ['free', 'premium'] as const) assert.notEqual(svc.rewardAt(l, t).kind, 'skin');
  }
  assert.ok(svc.view(p).pass.claimable.premium.includes(5));
});

test('tienda: los animales no se venden; los cosméticos se compran con MC o CN', async () => {
  const { svc } = await service();
  const cfg = await config();
  const p = svc.load(undefined, 'Ana');
  assert.deepEqual(cfg.shop.skins ?? {}, {}, 'ningún animal a la venta');
  assert.deepEqual(svc.buySkin(p, 'leon'), { ok: false, error: 'already_owned' });
  assert.deepEqual(svc.buySkin(p, 'dragon'), { ok: false, error: 'unknown_skin' });
  assert.ok(svc.selectSkin(p, 'leon').ok, 'cualquier animal se puede elegir');
  assert.equal(p.selectedSkin, 'leon');

  assert.deepEqual(svc.buyCosmetic(p, 'capa_invisible'), { ok: false, error: 'unknown_cosmetic' });
  assert.deepEqual(svc.buyCosmetic(p, 'traje_carbon'), { ok: false, error: 'already_owned' });
  assert.deepEqual(svc.buyCosmetic(p, 'traje_marino'), { ok: false, error: 'not_enough_coins' });
  p.coins = 1000;
  assert.ok(svc.buyCosmetic(p, 'traje_marino').ok);
  assert.equal(p.coins, 1000 - (cfg.shop.cosmetics!.traje_marino!.coins ?? 0));
  assert.deepEqual(svc.buyCosmetic(p, 'mochila_plata'), { ok: false, error: 'not_enough_credits' });
  p.credits = 120;
  assert.ok(svc.buyCosmetic(p, 'mochila_plata').ok);
  assert.equal(p.credits, 0);
});

test('vestuario: ponerse y quitarse cosméticos propios, cada uno en su hueco', async () => {
  const { svc } = await service();
  const p = svc.load(undefined, 'Ana');
  assert.ok(svc.equipCosmetic(p, 'outfit', 'sudadera_gris').ok);
  assert.ok(svc.equipCosmetic(p, 'shoes', 'zapas_blancas').ok);
  assert.deepEqual(p.equipped, { outfit: 'sudadera_gris', shoes: 'zapas_blancas' });
  assert.deepEqual(svc.equipCosmetic(p, 'outfit', 'zapas_blancas'), { ok: false, error: 'wrong_slot' });
  assert.deepEqual(svc.equipCosmetic(p, 'hat', 'gorra_azul'), { ok: false, error: 'cosmetic_locked' });
  assert.deepEqual(svc.equipCosmetic(p, 'cola' as never, 'gorra_azul'), { ok: false, error: 'bad_slot' });
  assert.ok(svc.equipCosmetic(p, 'outfit', null).ok);
  assert.deepEqual(p.equipped, { shoes: 'zapas_blancas' });
});

test('perfiles antiguos: reciben los 12 animales y los cosméticos de inicio', async () => {
  const { svc, store } = await service();
  const cfg = await config();
  const old = { ...svc.load(undefined, 'Ana'), skins: ['zorro', 'gato'] } as Partial<PlayerProfile>;
  delete old.cosmetics;
  delete old.equipped;
  store.put(old as PlayerProfile);
  const p = svc.load(old.id, 'Ana');
  assert.equal(p.skins.length, 12);
  assert.deepEqual(p.cosmetics, cfg.starter_cosmetics);
  assert.deepEqual(p.equipped, {});
});

test('persistencia JSON: los perfiles sobreviven a un reinicio', async () => {
  const cfg = await config();
  const ids = await skins();
  const file = join(mkdtempSync(join(tmpdir(), 'perfiles-')), 'profiles.json');
  const store = new JsonFileProfileStore(file);
  const svc = new ProfileService(cfg, store, { has: (s) => ids.includes(s) });
  const p = svc.load(undefined, 'Ana');
  svc.grantMatch(p, { won: true, objectivesCompleted: 1 });
  store.flush();
  const saved = JSON.parse(readFileSync(file, 'utf8'));
  assert.equal(saved.version, 1);
  const again = new ProfileService(cfg, new JsonFileProfileStore(file), { has: (s) => ids.includes(s) }).load(p.id, 'Ana');
  assert.equal(again.xp, p.xp);
  assert.equal(again.coins, p.coins);
  assert.deepEqual(again.skins, p.skins);
});
