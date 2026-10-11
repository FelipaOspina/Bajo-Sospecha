import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import type { GameEvent, RoomSnapshot, ServerMessage } from '../../shared/protocol/protocol.js';
import { SeededRandom } from '../src/core/Random.js';
import { AbilityCatalog, type AbilityConfig } from '../src/domain/abilities/index.js';
import { createRoleManager, InMemoryRoleConfigSource } from '../src/domain/roles/index.js';
import { compileScenario } from '../src/domain/scenario/ScenarioAdapter.js';
import { SkinCatalog, type SkinConfig } from '../src/domain/skins/SkinCatalog.js';
import { Room } from '../src/net/Room.js';

const cfg = (p: string) => fileURLToPath(new URL(`../../../../${p}`, import.meta.url));
const json = async <T>(p: string) => JSON.parse(await readFile(cfg(p), 'utf8')) as T;

const abilityConfig = () => json<AbilityConfig>('shared/config/abilities/abilities.json');

/** Sala del caso NexusCore con 4 jugadores, cada uno con el animal pedido y un rol fijo. */
async function setup(animals: Record<string, [skin: string, role: string]>) {
  const compiled = compileScenario(await json('shared/config/scenarios/nexuscore_fraude.json'));
  const { roleManager, objectives } = createRoleManager(
    new InMemoryRoleConfigSource({ [compiled.roleSet.id]: compiled.roleSet }), new SeededRandom(1));
  roleManager.useRoleSet(compiled.roleSet);
  let now = 0;
  const inbox = new Map<string, ServerMessage[]>();
  const room = new Room('T', {
    roles: roleManager, objectives, map: compiled.map, trial: compiled.trial, endings: compiled.endings,
    skins: new SkinCatalog(await json<SkinConfig>('shared/config/skins/skins.json'), new SeededRandom(2)),
    abilities: new AbilityCatalog(await abilityConfig()),
  }, { send: (p, m) => inbox.set(p, [...(inbox.get(p) ?? []), structuredClone(m)]) }, { now: () => now, phaseDurationsMs: compiled.phaseDurationsMs });

  const ids = Object.keys(animals);
  for (const [id, [skin]] of Object.entries(animals)) room.connect(id, id.toUpperCase(), { preferredSkin: skin });
  const seq = new Map(ids.map((i) => [i, 0]));
  const send = (id: string, intent: Record<string, unknown>) => {
    seq.set(id, seq.get(id)! + 1);
    room.handleIntent(id, { ...intent, seq: seq.get(id)! } as never);
    const last = inbox.get(id)!.at(-1)!;
    return last.t === 'rejected' ? last.reason : 'ok';
  };
  const ability = (id: string) => send(id, { t: 'use_ability' });
  const lobbyAttempt = ability(ids[0]!);
  ids.forEach((id) => send(id, { t: 'ready', ready: true }));
  for (const [id, [, role]] of Object.entries(animals)) roleManager.setRole(id, role);
  now += 60_000; room.tick();
  assert.equal(room.phase, 'investigation');

  const walkTo = (id: string, x: number, y: number) => {
    for (;;) {
      const p = room.state.players.get(id)!.position;
      const d = Math.hypot(x - p.x, y - p.y);
      if (d < 1) return;
      const k = Math.min(1, 50 / d);
      now += 200;
      send(id, { t: 'move', position: { x: p.x + (x - p.x) * k, y: p.y + (y - p.y) * k } });
    }
  };
  const advance = (ms: number) => { now += ms; room.tick(); };
  const snap = (id: string): RoomSnapshot => room['projector'].snapshotFor(id);
  const events = (id: string, e: GameEvent['e']) =>
    (inbox.get(id) ?? []).flatMap((m) => (m.t === 'event' && m.event.e === e ? [m.event] : []));
  /** Un paso de `px` en `ms`: 'ok' o 'too_fast'. */
  const step = (id: string, px: number, ms: number) => {
    const p = room.state.players.get(id)!.position;
    now += ms;
    return send(id, { t: 'move', position: { x: p.x + px, y: p.y } });
  };
  return { room, inbox, send, ability, walkTo, advance, snap, events, step, lobbyAttempt, roleManager };
}

const FOUR = {
  ceo: ['zorro', 'ROLE_CEO'], cto: ['leon', 'ROLE_CTO'], inv: ['conejo', 'ROLE_INVESTOR'], leak: ['panda', 'ROLE_LEAKER'],
} as Record<string, [string, string]>;

test('catálogo: los 12 animales del juego tienen pasiva y activa válidas', async () => {
  const config = await abilityConfig();
  const catalog = new AbilityCatalog(config);
  const skins = (await json<SkinConfig>('shared/config/skins/skins.json')).skins.map((s) => s.id);
  assert.equal(skins.length, 12);
  assert.deepEqual(catalog.animals().sort(), [...skins].sort());
  for (const id of skins) {
    const kit = catalog.forSkin(id)!;
    assert.ok(kit.passive.name && kit.active.name && kit.active.cooldown > 0, id);
  }
  // Un JSON mal editado no arranca: nada de multiplicadores absurdos ni pasivas en la activa.
  const broken = structuredClone(config);
  broken.abilities.conejo!.active.effects = { speed: 9 };
  assert.throws(() => new AbilityCatalog(broken), /speed/);
  const sneaky = structuredClone(config);
  sneaky.abilities.oso!.active.effects = { inventory: 2 };
  assert.throws(() => new AbilityCatalog(sneaky), /pasiva/);
});

test('validación: solo en la investigación, una vez por enfriamiento', async () => {
  const { ability, advance, snap, lobbyAttempt, room, send } = await setup(FOUR);
  assert.equal(lobbyAttempt, 'wrong_phase', 'en el lobby no hay habilidades');
  const before = snap('inv').you!.ability!;
  assert.deepEqual([before.id, before.readyAt, before.activeUntil], ['salto', 0, null]);
  assert.equal(ability('inv'), 'ok');
  assert.equal(ability('inv'), 'on_cooldown');
  const state = snap('inv').you!.ability!;
  assert.equal(state.cooldownMs, 18_000);
  advance(17_000);
  assert.equal(ability('inv'), 'on_cooldown');
  advance(1_000);
  assert.equal(ability('inv'), 'ok');
  // En la discusión ya no.
  advance(10 * 60_000);
  assert.equal(room.phase, 'discussion');
  assert.equal(ability('ceo'), 'wrong_phase');
  assert.equal(send('ceo', { t: 'use_ability' }), 'wrong_phase');
});

test('acelerón: el servidor acepta más velocidad solo mientras dura (con un margen)', async () => {
  const { ability, step, snap, advance } = await setup(FOUR);
  // Conejo: 260 px/s × 1.5 de margen = 390 px/s. Un paso de 60 px en 100 ms (600 px/s) se rechaza.
  assert.equal(step('inv', 0, 100), 'ok');
  assert.equal(step('inv', 60, 100), 'too_fast');
  assert.equal(ability('inv'), 'ok');                     // Salto: ×1.9 durante 1,2 s → 741 px/s
  assert.equal(snap('inv').you!.speedMultiplier, 1.9);
  assert.equal(step('inv', 60, 100), 'ok');
  advance(2_000);                                         // acabado y pasado el margen
  assert.equal(snap('inv').you!.speedMultiplier, 1);
  assert.equal(step('inv', 0, 100), 'ok');
  assert.equal(step('inv', 60, 100), 'too_fast');
});

test('rugido: corta las acciones cercanas, salvo la del panda (calma); nunca dice roles', async () => {
  const { ability, send, walkTo, snap, events, inbox } = await setup(FOUR);
  walkTo('ceo', 200, 150);
  walkTo('leak', 230, 170);
  walkTo('cto', 260, 150);
  const logs = snap('ceo').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents[0]!.instanceId;
  assert.equal(send('ceo', { t: 'channel_start', evidenceInstanceId: logs, action: 'delete' }), 'ok');
  inbox.clear();
  assert.equal(ability('cto'), 'ok');
  const finished = events('ceo', 'channel_finished').at(-1);
  assert.ok(finished && finished.e === 'channel_finished' && finished.reason === 'interrupted');
  assert.equal(snap('ceo').players.find((p) => p.id === 'ceo')!.channel, undefined);
  const roar = events('inv', 'ability_used').at(-1)!;
  assert.ok(roar.e === 'ability_used' && roar.abilityId === 'rugido');
  assert.deepEqual(roar.affected, ['ceo'], 'el panda está al lado pero no le afecta');
  assert.ok(!JSON.stringify(inbox).includes('ROLE_'), 'ningún mensaje de habilidades lleva roles');
});

test('sigilo, engaño y oído: quién ve la barra de acción de quién', async () => {
  const { ability, send, walkTo, snap } = await setup({
    ceo: ['mapache', 'ROLE_CEO'], cto: ['zorro', 'ROLE_CTO'], inv: ['conejo', 'ROLE_INVESTOR'], leak: ['oso', 'ROLE_LEAKER'],
  });
  walkTo('ceo', 200, 150);
  walkTo('leak', 260, 200);
  const logs = snap('ceo').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents[0]!.instanceId;
  assert.equal(send('ceo', { t: 'channel_start', evidenceInstanceId: logs, action: 'delete' }), 'ok');
  // Mapache: manos hábiles, 15 % más rápido (10 s → 8,5 s).
  assert.equal(snap('ceo').players.find((p) => p.id === 'ceo')!.channel!.durationMs, 8_500);
  assert.ok(snap('leak').players.find((p) => p.id === 'ceo')!.channel, 'el oso, al lado, la ve');
  // Antifaz: nadie más la ve; él sí.
  assert.equal(ability('ceo'), 'ok');
  assert.equal(snap('leak').players.find((p) => p.id === 'ceo')!.channel, undefined);
  assert.ok(snap('ceo').players.find((p) => p.id === 'ceo')!.channel);

  // Orejas largas (conejo, ×1.4): ve una barra a 600 px que el oso no vería.
  const { send: send2, walkTo: walk2, snap: snap2, ability: ability2 } = await setup({
    ceo: ['zorro', 'ROLE_CEO'], cto: ['leon', 'ROLE_CTO'], inv: ['conejo', 'ROLE_INVESTOR'], leak: ['oso', 'ROLE_LEAKER'],
  });
  walk2('ceo', 200, 150);
  walk2('inv', 200, 560);   // 410 px: dentro de 500 × 0.7 (astucia del zorro) × 1.4 = 490
  walk2('leak', 200, 540);  // 390 px: fuera de 500 × 0.7 = 350
  const logs2 = snap2('ceo').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents[0]!.instanceId;
  assert.equal(send2('ceo', { t: 'channel_start', evidenceInstanceId: logs2, action: 'delete' }), 'ok');
  assert.equal(snap2('inv').players.find((p) => p.id === 'ceo')!.channel?.label, 'Purgar partición /var/log/audit.log');
  assert.equal(snap2('leak').players.find((p) => p.id === 'ceo')!.channel, undefined);
  // Engaño del zorro: los demás ven otra etiqueta y una acción neutra.
  assert.equal(ability2('ceo'), 'ok');
  const seen = snap2('inv').players.find((p) => p.id === 'ceo')!.channel!;
  assert.deepEqual([seen.kind, seen.label], ['backup', 'Revisando papeles…']);
  assert.equal(snap2('ceo').players.find((p) => p.id === 'ceo')!.channel!.label, 'Purgar partición /var/log/audit.log');
});

test('secretas solo para quien las usa; olfato marca escondites con pruebas que ves', async () => {
  const { ability, walkTo, events } = await setup({
    ceo: ['perro', 'ROLE_CEO'], cto: ['lobo', 'ROLE_CTO'], inv: ['conejo', 'ROLE_INVESTOR'], leak: ['oso', 'ROLE_LEAKER'],
  });
  walkTo('ceo', 200, 150);
  walkTo('cto', 240, 160);
  assert.equal(ability('ceo'), 'ok');
  const mine = events('ceo', 'ability_used').at(-1)!;
  assert.ok(mine.e === 'ability_used' && mine.abilityId === 'olfato' && mine.marks!.includes('spawn_CLUE_SERVER_LOGS'));
  assert.equal(events('cto', 'ability_used').length, 0, 'el olfato es secreto');
  // El aullido es público y acelera también a quien esté cerca.
  assert.equal(ability('cto'), 'ok');
  const howl = events('ceo', 'ability_used').at(-1)!;
  assert.ok(howl.e === 'ability_used' && howl.abilityId === 'aullido_manada' && howl.marks === undefined);
  assert.deepEqual(howl.affected, ['ceo']);
});

test('pasivas en las estadísticas: el oso carga una prueba más y el gato alcanza más lejos', async () => {
  const { room, roleManager } = await setup({
    ceo: ['oso', 'ROLE_CEO'], cto: ['gato', 'ROLE_CTO'], inv: ['conejo', 'ROLE_INVESTOR'], leak: ['panda', 'ROLE_LEAKER'],
  });
  const stats = (p: string) => room.evidence['deps'].roles.getStats(p);
  assert.equal(stats('ceo').inventoryCapacity, roleManager.getStats('ceo').inventoryCapacity + 1);
  assert.equal(stats('cto').interactRange, roleManager.getStats('cto').interactRange * 1.15);
  assert.equal(stats('inv').interactRange, roleManager.getStats('inv').interactRange);
});
