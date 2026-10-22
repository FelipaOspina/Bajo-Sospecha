import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { LineOfSight } from '../src/domain/world/LineOfSight.js';
import { give, startGame } from './helpers.js';

/** p0 CEO, p1 Abogado, p2 CTO, p3 Inversor, p4 Filtrador, p5 Seguridad. */
const SIX = ['ROLE_CEO', 'ROLE_ACCOMPLICE', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'];

test('silence: too_early los primeros 60 s, después noquea 30 s; cooldown de 60 s', () => {
  const g = startGame(SIX);
  g.place('p0', 0, 0); g.place('p4', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), 'too_early');
  const you = g.room['projector'].snapshotFor('p0').you!;
  assert.equal(you.powers!.silence!.readyAt, g.room.state.investigationStartedAt! + 60_000, 'readyAt incluye los 60 s iniciales');
  g.wait(60_000);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  const victim = g.room.state.players.get('p4')!;
  assert.equal(victim.alive, true);
  assert.equal(victim.knockedUntil, g.clock.t + 30_000);
  assert.deepEqual(g.room.state.bodies.map((b) => [b.id, b.kind, b.reported]), [['body:p4', 'knocked', false]]);
  // Al asesino le llega completo; a la víctima, sin killer.
  assert.equal((g.out.events('p0', 'silenced')[0] as { killer?: string }).killer, 'p0');
  const toVictim = g.out.events('p4', 'silenced')[0] as Record<string, unknown>;
  assert.equal('killer' in toVictim, false);
  assert.equal(toVictim.knocked, true);
  assert.equal(g.out.events('p2', 'silenced').length, 0);
  // Noqueado: ni moverse ni que le vuelvan a silenciar.
  assert.equal(g.act('p4', { t: 'move', position: { x: 60, y: 0 } }), 'knocked');
  g.place('p2', 40, 0);
  give(g, 'p2', 'CLUE_CASINO_DEBTS');
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p2' }), 'on_cooldown');
  g.wait(60_000);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null, 'tras levantarse sí');
});

test('silence: target_not_alive con noqueados, too_far, no_power, no_motive', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p0', 0, 0); g.place('p4', 50, 0); g.place('p2', 60, 0); g.place('p1', 2000, 2000);
  assert.equal(g.act('p2', { t: 'silence', targetId: 'p4' }), 'no_power');
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p2' }), 'no_motive');
  g.place('p4', 91, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), 'too_far');
  g.place('p4', 89, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  g.place('p1', 80, 0);
  assert.equal(g.act('p1', { t: 'silence', targetId: 'p4' }), 'target_not_alive', 'ya está noqueado');
  assert.equal(g.act('p1', { t: 'silence', targetId: 'nadie' }), 'target_not_alive');
});

test('motivos: evidence, witness (también del compañero), backup y story', () => {
  const g = startGame(SIX, { skipGrace: true });
  const motives = (viewer: string) => g.room['projector'].snapshotFor(viewer).you!.motiveTargets!;
  // story: el CEO siempre tiene motivo contra el Filtrador; el Abogado también.
  assert.deepEqual(motives('p0'), [{ playerId: 'p4', reason: 'story' }]);
  assert.deepEqual(motives('p1').map((m) => m.reason), ['story']);
  assert.equal(g.room['projector'].snapshotFor('p2').you!.motiveTargets, undefined, 'solo roles con silence');
  // evidence: el CTO lleva los avisos de cobro (incriminan al CEO, no al Abogado).
  give(g, 'p2', 'CLUE_CASINO_DEBTS');
  assert.deepEqual(motives('p0').find((m) => m.playerId === 'p2'), { playerId: 'p2', reason: 'evidence', evidence: 'Avisos de Cobro junto a la Caja Fuerte' });
  assert.equal(motives('p1').some((m) => m.playerId === 'p2'), false);
  // backup: el Inversor fotografía la laptop y tira la foto.
  const laptop = g.room.evidence.listInteractables().find((i) => i.id === 'spawn_CLUE_UNLOCKED_LAPTOP')!.contents()[0]!;
  const copy = g.room.evidence.backup('p3', laptop);
  assert.ok(copy.ok);
  assert.equal(motives('p0').find((m) => m.playerId === 'p3')!.reason, 'evidence');
  g.room.evidence.forceDestroy('p3', copy.value.instanceId);
  assert.equal(motives('p0').find((m) => m.playerId === 'p3')!.reason, 'backup');
  // witness: el Jefe de Seguridad ve al CEO noquear al Filtrador → motivo para el CEO y para su Abogado.
  g.place('p0', 0, 0); g.place('p4', 50, 0); g.place('p5', 400, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  assert.equal(motives('p0').find((m) => m.playerId === 'p5')!.reason, 'witness');
  assert.equal(motives('p1').find((m) => m.playerId === 'p5')!.reason, 'witness');
  assert.equal(motives('p0').some((m) => m.playerId === 'p4'), false, 'los noqueados no salen');
});

test('motivos: nunca contra un compañero de equipo', () => {
  const g = startGame(SIX, { skipGrace: true });
  const motives = (viewer: string) => g.room['projector'].snapshotFor(viewer).you!.motiveTargets!;
  // El Abogado lleva una prueba contra el CEO: aun así el CEO no puede silenciarle.
  give(g, 'p1', 'CLUE_CASINO_DEBTS');
  assert.equal(motives('p0').some((m) => m.playerId === 'p1'), false);
  g.place('p0', 0, 0); g.place('p1', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p1' }), 'no_motive');
});

test('testigos: solo vivos a ≤900 px; un muro tapa la vista', () => {
  const walls = new LineOfSight([[300, -500, 300, 500]]);
  for (const withWall of [false, true]) {
    const g = startGame(SIX, { skipGrace: true, ...(withWall ? { lineOfSight: walls } : {}) });
    g.place('p0', 0, 0); g.place('p4', 50, 0);
    g.place('p3', 500, 0);    // al otro lado del muro
    g.place('p2', -800, 0);   // mismo lado, a 800 px
    g.place('p5', -950, 0);   // demasiado lejos
    g.place('p1', 0, 60);     // el compañero lo ve, pero no cuenta como testigo
    assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
    const w = (p: string) => g.out.events(p, 'witnessed') as { killer: string; victim: string }[];
    assert.equal(w('p1').length, 0, 'un compañero del asesino no es testigo');
    assert.equal(w('p3').length, withWall ? 0 : 1, `muro=${withWall}`);
    assert.deepEqual(w('p2').map((e) => [e.killer, e.victim]), [['p0', 'p4']]);
    assert.equal(w('p5').length, 0);
    assert.equal(w('p4').length, 0, 'la víctima no es testigo');
    assert.equal(w('p0').length, 0);
  }
});

test('LineOfSight.load sin archivo → null (solo distancia)', () => {
  assert.equal(LineOfSight.load('/no/existe/office_walls.json'), null);
});

test('escolta: protege, consume la escolta, pone el cooldown y avisa a los tres', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p0', 0, 0); g.place('p4', 50, 0); g.place('p5', 150, 0); g.place('p2', 600, 0);
  assert.equal(g.act('p2', { t: 'escort', targetId: 'p4' }), 'no_power');
  assert.equal(g.act('p5', { t: 'escort', targetId: 'p2' }), 'too_far');
  assert.equal(g.act('p5', { t: 'escort', targetId: 'p4' }), null);
  const esc = g.room['projector'].snapshotFor('p5').you!.powers!.escort!;
  assert.deepEqual(esc, { readyAt: g.clock.t + 90_000, protecting: 'p4', until: g.clock.t + 45_000 });
  assert.equal(g.act('p5', { t: 'escort', targetId: 'p2' }), 'on_cooldown');
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), 'target_protected');
  for (const p of ['p0', 'p5', 'p4']) assert.deepEqual(g.out.events(p, 'escort_blocked'), [{ e: 'escort_blocked', target: 'p4' }]);
  assert.equal(g.out.events('p2', 'escort_blocked').length, 0);
  assert.equal(g.room.state.players.get('p4')!.knockedUntil, null);
  assert.equal(g.room.state.players.get('p5')!.escort.protecting, null);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), 'on_cooldown', 'el cooldown se pone igualmente');
  g.wait(60_000);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null, 'la escolta ya se consumió');
});

test('escolta: caduca a los 45 s', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p4', 50, 0); g.place('p5', 150, 0);
  assert.equal(g.act('p5', { t: 'escort', targetId: 'p4' }), null);
  g.wait(45_000);
  assert.equal(g.room.state.players.get('p5')!.escort.protecting, null);
});

test('2.º silencio → fantasma con cuerpo dead; inventario en "Objetos caídos de X"', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p0', 0, 0); g.place('p4', 50, 0);
  give(g, 'p4', 'CLUE_HIDDEN_RECORDER');
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  const box = g.room.evidence.listInteractables().find((i) => i.id === 'body:p4')!;
  assert.equal(box.type, 'body');
  assert.equal(box.contents().length, 1);
  const view = g.room['projector'].snapshotFor('p2').interactables.find((i) => i.id === 'body:p4')!;
  assert.deepEqual([view.type, view.ownerId, view.label], ['body', 'p4', 'Objetos caídos de P4']);
  g.wait(30_000);
  assert.equal(g.room.state.bodies.length, 0, 'al levantarse desaparece el cuerpo');
  assert.ok(g.room.evidence.listInteractables().some((i) => i.id === 'body:p4'), 'el contenedor se queda');
  assert.equal(g.room['projector'].snapshotFor('p4').you!.wasKnocked, true);
  g.wait(30_000);
  g.place('p4', 300, 0); g.place('p0', 260, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  const p4 = g.room.state.players.get('p4')!;
  assert.deepEqual([p4.alive, p4.ghost], [false, true]);
  assert.deepEqual(g.room.state.bodies.map((b) => [b.id, b.kind]), [['body:p4', 'dead']]);
  assert.equal((g.out.events('p4', 'silenced').at(-1) as { knocked: boolean }).knocked, false);
});
