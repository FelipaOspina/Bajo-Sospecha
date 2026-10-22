import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import type { ClientIntent, ServerMessage } from '../../shared/protocol/protocol.js';
import { CosmeticCatalog, type CosmeticConfig } from '../src/domain/cosmetics/CosmeticCatalog.js';
import { emptyActivity, FORBIDDEN_STATS, levelProgress, xpForLevel, xpToReach } from '../src/domain/profile/DetectivePath.js';
import { ProfileService } from '../src/domain/profile/ProfileService.js';
import { InMemoryProfileStore } from '../src/domain/profile/ProfileStore.js';
import type { MatchActivity, PlayerProfile, ProgressionConfig } from '../src/domain/profile/types.js';
import { GameGateway } from '../src/net/GameGateway.js';
import { DEV, give, startGame } from './helpers.js';

const cfgPath = `${DEV}shared/config/progression/progression.json`;
const config = (): ProgressionConfig => JSON.parse(readFileSync(cfgPath, 'utf8')) as ProgressionConfig;
const skins = (JSON.parse(readFileSync(`${DEV}shared/config/skins/skins.json`, 'utf8')) as { skins: { id: string }[] }).skins.map((s) => s.id);
const cosmetics = new CosmeticCatalog(JSON.parse(readFileSync(`${DEV}shared/config/cosmetics/cosmetics.json`, 'utf8')) as CosmeticConfig);

function service(cfg = config()) {
  let n = 0;
  return new ProfileService(cfg, new InMemoryProfileStore(), { has: (s) => skins.includes(s) }, () => 1000, () => `perfil-${++n}-xxxxxxxx`, cosmetics);
}

/** Perfil justo al principio de `level`, con las recompensas de nivel ya entregadas. */
function atLevel(svc: ProfileService, level: number): PlayerProfile {
  const p = svc.load(undefined, 'Ana');
  p.xp = xpToReach(level, svc.config);
  p.path!.rewarded = Array.from({ length: level }, (_, i) => i + 1);
  return p;
}

test('curva de nivel creciente: 300, 450, 600… con tope, y nivel ⇄ XP coherentes', () => {
  const cfg = config();
  const c = cfg.profile_level_curve!;
  assert.deepEqual([1, 2, 3, 4, 5].map((l) => xpForLevel(l, cfg)), [300, 450, 600, 750, 900]);
  assert.equal(xpForLevel(50, cfg), c.max_per_level, 'tope por nivel');
  for (let l = 1; l < 60; l++) assert.ok(xpForLevel(l + 1, cfg) >= xpForLevel(l, cfg), 'nunca baja');
  for (const l of [1, 2, 5, 10, 15, 30]) {
    const start = xpToReach(l, cfg);
    assert.deepEqual(levelProgress(start, cfg), { level: l, into: 0, need: xpForLevel(l, cfg) });
    assert.equal(levelProgress(start - 1, cfg).level, Math.max(1, l - 1));
  }
  assert.equal(xpToReach(5, cfg), 300 + 450 + 600 + 750);
  // Sin curva: lineal como antes.
  const linear = { ...cfg, profile_level_curve: undefined };
  assert.equal(levelProgress(2500, linear).level, 1 + Math.floor(2500 / cfg.profile_xp_per_level));

  const svc = service();
  const p = svc.load(undefined, 'Ana');
  p.xp = xpToReach(3, cfg) + 120;
  const v = svc.view(p);
  assert.deepEqual([v.level, v.xpIntoLevel, v.xpForLevel], [3, 120, 600]);
  assert.deepEqual(v.path, { tutorialDone: false, done: [], progress: {}, rewarded: [1] });
});

test('Ruta del Detective: niveles 1–15 con lección y reto; ningún reto delata un rol; solo cosméticos o monedas', () => {
  const cfg = config();
  const levels = cfg.detective_path!.levels;
  assert.deepEqual(levels.map((l) => l.level), Array.from({ length: 15 }, (_, i) => i + 1));
  const ids = new Set<string>();
  for (const l of levels) {
    assert.ok(l.title && l.lesson, `nivel ${l.level}: título y lección`);
    const lesson = l.lesson as { title?: string; body?: string[]; controls?: unknown[] };
    assert.ok(lesson.title && lesson.body?.length && lesson.controls?.length, `nivel ${l.level}: tarjeta completa`);
    assert.ok(l.challenge, `nivel ${l.level}: reto`);
    assert.ok(!ids.has(l.challenge!.id), 'ids únicos');
    ids.add(l.challenge!.id);
    assert.ok(!FORBIDDEN_STATS.has(l.challenge!.stat), `nivel ${l.level}: ${l.challenge!.stat} delataría un rol`);
    assert.ok(['played', 'won', 'objectives', 'survived', 'tutorial', ...Object.keys(emptyActivity())].includes(l.challenge!.stat), `stat conocida: ${l.challenge!.stat}`);
    for (const k of Object.keys(l.reward ?? {})) assert.ok(['coins', 'cosmetic'].includes(k), 'solo monedas o cosméticos');
    if (l.reward?.cosmetic) assert.ok(cosmetics.has(l.reward.cosmetic), `${l.reward.cosmetic} existe`);
  }
  assert.equal(levels[0]!.challenge!.stat, 'tutorial', 'el nivel 1 es el tutorial');
  // La copia del cliente (CLIENT_DIR, si existe) es idéntica.
  const client = `${process.env.CLIENT_DIR ?? `${DEV}../w3d`}/data/progression/progression.json`;
  if (existsSync(client)) assert.equal(readFileSync(client, 'utf8'), readFileSync(cfgPath, 'utf8'), `${client} = shared`);
});

test('retos: se cuentan con lo que pasó en la partida, solo los desbloqueados, una sola vez', () => {
  const svc = service();
  const cfg = svc.config;
  const activity: MatchActivity = { ...emptyActivity(), collected: 2, reported: 1, emergencyVotes: 1, chats: 2, trialVotes: 1, presented: 1, survived: true };

  // Nivel 2: solo los retos de los niveles 1–2 (jugar una partida); recoger 2 es del nivel 3.
  const low = atLevel(svc, 2);
  const r1 = svc.grantMatch(low, { won: false, objectivesCompleted: 0, activity });
  assert.deepEqual(r1.challenges!.map((c) => c.id), ['jugar_1']);
  const matchXp = cfg.match_rewards.xp_played;
  assert.equal(r1.matchXp, matchXp);
  assert.equal(r1.xp, matchXp + 100, 'la XP del reto se suma');
  assert.equal(r1.levelBefore, 2);
  assert.equal(r1.level, svc.level(low.xp));
  assert.equal(low.path!.progress.recoger_2, undefined, 'un reto bloqueado no acumula');

  // Nivel 15: todo desbloqueado.
  const high = atLevel(svc, 15);
  const r2 = svc.grantMatch(high, { won: false, objectivesCompleted: 0, activity });
  assert.deepEqual(r2.challenges!.map((c) => c.id).sort(),
    ['debate_1', 'en_pie_1', 'exponer_1', 'jugar_1', 'recoger_2', 'reportar_1', 'veredicto_1', 'votar_asamblea'].sort());
  assert.ok(!r2.challenges!.some((c) => c.id === 'tutorial'), 'el tutorial no se cumple jugando');
  const again = svc.grantMatch(high, { won: false, objectivesCompleted: 0, activity });
  assert.deepEqual(again.challenges, [], 'cada reto da XP una sola vez');

  // scope match: 1 prueba por partida nunca cumple «recoge 2 en una partida».
  const p = atLevel(svc, 3);
  for (let i = 0; i < 3; i++) svc.grantMatch(p, { won: false, objectivesCompleted: 0, activity: { ...emptyActivity(), collected: 1 } });
  assert.ok(!p.path!.done.includes('recoger_2'));
  // scope total: «gana 3 partidas» se acumula entre partidas.
  const w = atLevel(svc, 15);
  w.path!.done.push('ganar_1');
  svc.grantMatch(w, { won: true, objectivesCompleted: 0 });
  svc.grantMatch(w, { won: false, objectivesCompleted: 0 });
  assert.equal(w.path!.progress.ganar_3, 1);
  svc.grantMatch(w, { won: true, objectivesCompleted: 0 });
  assert.equal(w.path!.progress.ganar_3, 2);
  const third = svc.grantMatch(w, { won: true, objectivesCompleted: 1 });
  assert.ok(third.challenges!.some((c) => c.id === 'ganar_3'));
  assert.equal(w.path!.progress.ganar_3, undefined);
});

test('recompensas de nivel: monedas y cosméticos al llegar, una sola vez', () => {
  const svc = service();
  const p = svc.load(undefined, 'Ana');
  p.path!.done.push('jugar_1');
  p.xp = xpToReach(10, svc.config) - 10;
  p.path!.rewarded = Array.from({ length: 9 }, (_, i) => i + 1);
  const coins = p.coins;
  const r = svc.grantMatch(p, { won: false, objectivesCompleted: 0 });
  assert.equal(r.level, 10);
  assert.deepEqual(r.levelRewards, [{ level: 10, cosmetic: 'gorra_negra' }]);
  assert.ok(p.cosmetics.includes('gorra_negra'));
  assert.equal(p.coins, coins + svc.config.match_rewards.coins_played);
  assert.deepEqual(svc.grantMatch(p, { won: false, objectivesCompleted: 0 }).levelRewards, []);
  // Perfil antiguo con mucha XP: al cargarlo recibe las recompensas de los niveles que ya tiene.
  const old = svc.load(undefined, 'Viejo');
  old.xp = xpToReach(6, svc.config);
  delete old.path;
  const before = old.coins;
  const reloaded = svc.load(old.id, 'Viejo');
  assert.equal(reloaded.coins, before + 100 + 200, 'niveles 2 y 5');
  assert.deepEqual(reloaded.path!.rewarded, [1, 2, 3, 4, 5, 6]);
});

test('Room cuenta la actividad de cada jugador (privada) y la entrega al terminar', () => {
  const g = startGame(['ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_EMPLOYEE'], { skipGrace: true });
  let delivered: ReadonlyMap<string, MatchActivity> | null = null;
  (g.room as unknown as { opts: { onResolved: (r: unknown, a: ReadonlyMap<string, MatchActivity>) => void } }).opts.onResolved = (_r, a) => { delivered = a; };
  give(g, 'p2', 'CLUE_CASINO_DEBTS');
  give(g, 'p2', 'CLUE_FAKE_INVOICES');
  // Copia de seguridad (el CTO saca el dump de los logs).
  const logs = g.room.evidence.listInteractables().find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!;
  g.place('p1', logs.position.x, logs.position.y);
  assert.equal(g.act('p1', { t: 'channel_start', evidenceInstanceId: logs.contents()[0]!, action: 'backup' }), null);
  g.wait(10_000);
  // Silencio + reporte + voto en la asamblea + chat.
  g.place('p0', 0, 0); g.place('p3', 50, 0); g.place('p4', 120, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p3' }), null);
  assert.equal(g.act('p4', { t: 'report_body', bodyId: 'body:p3' }), null);
  assert.equal(g.act('p2', { t: 'chat', text: 'Yo estaba en Finanzas' }), null);
  assert.equal(g.act('p2', { t: 'emergency_vote', targetId: 'p0' }), null);
  assert.equal(g.act('p2', { t: 'emergency_vote', targetId: 'skip' }), null, 'cambiar el voto no cuenta doble');
  g.wait(75_000); g.wait(4_000);
  assert.equal(g.room.phase, 'investigation');
  g.wait(g.room.state.phaseEndsAt! - g.clock.t + 1);
  assert.equal(g.room.phase, 'discussion');
  assert.equal(g.act('p2', { t: 'present_evidence', evidenceInstanceId: g.room.evidence.inventoryOf('p2')[0]!.instanceId }), null);
  assert.equal(g.act('p2', { t: 'skip_to_voting' }), null);
  assert.equal(g.act('p2', { t: 'vote', optionId: 'despedir_ceo' }), null);

  // Nada de esto viaja en los snapshots (otros no pueden deducir qué hizo nadie).
  assert.ok(!JSON.stringify(g.room['projector'].snapshotFor('p0')).includes('emergencyVotes'));

  g.wait(600_000);
  assert.equal(g.room.phase, 'results');
  assert.ok(delivered, 'onResolved recibe la actividad');
  const a = (delivered as unknown as ReadonlyMap<string, MatchActivity>);
  assert.equal(a.get('p2')!.collected, 2);
  assert.equal(a.get('p2')!.chats, 1);
  assert.equal(a.get('p2')!.emergencyVotes, 1);
  assert.equal(a.get('p2')!.presented, 1);
  assert.equal(a.get('p2')!.trialVotes, 1);
  assert.equal(a.get('p2')!.survived, true);
  assert.equal(a.get('p1')!.backups, 1);
  assert.equal(a.get('p4')!.reported, 1);
  assert.equal(a.get('p3')!.survived, true, 'noqueado (no fantasma) termina en pie');
  assert.ok(!('silences' in a.get('p0')!), 'silenciar no se cuenta para nada');
});

test('tutorial: recompensa una sola vez por perfil (claim_tutorial_reward)', () => {
  const svc = service();
  const gateway = new GameGateway(svc, 4);
  const inbox: ServerMessage[] = [];
  gateway.open('c1', (m) => inbox.push(structuredClone(m)));
  let seq = 0;
  const send = (intent: Record<string, unknown>) => {
    gateway.message('c1', { ...intent, seq: ++seq } as ClientIntent);
    const reply = inbox.filter((m) => m.t === 'ack' || m.t === 'rejected').at(-1)!;
    return reply.t === 'rejected' ? reply.reason : 'ok';
  };
  assert.equal(send({ t: 'claim_tutorial_reward' }), 'no_profile', 'sin hello no hay perfil');
  assert.equal(send({ t: 'hello', name: 'Ana', protocol: 1 }), 'ok');
  const cfg = svc.config.detective_path!.tutorial_reward;
  const coins = svc.config.starting_coins;
  assert.equal(send({ t: 'claim_tutorial_reward' }), 'ok');
  const rewards = inbox.filter((m) => m.t === 'rewards').at(-1) as Extract<ServerMessage, { t: 'rewards' }>;
  assert.equal(rewards.rewards.source, 'tutorial');
  assert.equal(rewards.rewards.xp, cfg.xp);
  assert.equal(rewards.rewards.levelBefore, 1);
  assert.equal(rewards.rewards.level, 2, '300 XP: nivel 2');
  assert.deepEqual(rewards.rewards.levelRewards, [{ level: 2, coins: 100 }]);
  const profile = (inbox.filter((m) => m.t === 'profile').at(-1) as { profile: { xp: number; coins: number; level: number; path: { tutorialDone: boolean; done: string[] } } }).profile;
  assert.equal(profile.xp, cfg.xp);
  assert.equal(profile.coins, coins + cfg.coins + 100);
  assert.deepEqual([profile.path.tutorialDone, profile.path.done], [true, ['tutorial']]);
  assert.equal(send({ t: 'claim_tutorial_reward' }), 'already_claimed');
  assert.equal(inbox.filter((m) => m.t === 'rewards').length, 1);
});
