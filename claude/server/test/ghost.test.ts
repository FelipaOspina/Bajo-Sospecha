import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { startGame, type Game } from './helpers.js';

const SIX = ['ROLE_CEO', 'ROLE_ACCOMPLICE', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'];

/** Deja a p4 (Filtrador) como fantasma. */
function ghostP4(): Game {
  const g = startGame(SIX, { skipGrace: true });
  for (let k = 0; k < 2; k++) {
    g.place('p0', 0, 0); g.place('p4', 50, 0);
    assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
    g.wait(60_000);
  }
  assert.equal(g.room.state.players.get('p4')!.ghost, true);
  return g;
}

test('fantasma oculto para los vivos (sin posición actualizada); los fantasmas ven a todos', () => {
  const g = ghostP4();
  g.wait(2_000);
  assert.equal(g.act('p4', { t: 'move', position: { x: 400, y: 0 } }), null, 'se mueve libremente');
  const forAlive = g.room['projector'].snapshotFor('p2').players.find((p) => p.id === 'p4')!;
  assert.deepEqual([forAlive.hidden, forAlive.ghost, forAlive.alive], [true, true, false]);
  assert.deepEqual(forAlive.position, { x: 50, y: 0 });
  const forSelf = g.room['projector'].snapshotFor('p4');
  assert.deepEqual(forSelf.players.find((p) => p.id === 'p4')!.position, { x: 400, y: 0 });
  assert.equal(forSelf.players.find((p) => p.id === 'p4')!.hidden, undefined);
  assert.equal(forSelf.you!.ghost, true);
  assert.equal(forSelf.you!.ghostTasks!.length, 3);
  assert.equal(g.room['projector'].snapshotFor('p2').you!.ghost, false);
});

test('fantasma: no interactúa, ni canaliza, ni presenta, ni vota, ni silencia', () => {
  const g = ghostP4();
  const spot = g.room.evidence.listInteractables().find((i) => i.id === 'spawn_CLUE_HIDDEN_RECORDER')!;
  g.place('p4', spot.position.x, spot.position.y);
  assert.equal(g.act('p4', { t: 'interact', interactableId: spot.id }), 'not_alive');
  assert.equal(g.act('p4', { t: 'channel_start', evidenceInstanceId: spot.contents()[0]!, action: 'backup' }), 'not_alive');
  assert.equal(g.act('p4', { t: 'report_body', bodyId: 'body:p4' }), 'not_alive');
  assert.equal(g.act('p4', { t: 'vote', optionId: 'despedir_ceo' }), 'not_alive');
  assert.equal(g.act('p2', { t: 'ghost_ping', position: { x: 1, y: 1 } }), 'not_ghost');
});

test('ghost_ping: a los vivos de su equipo, cada 20 s', () => {
  const g = startGame(SIX, { skipGrace: true });
  // El CTO (inocentes) como fantasma: le llega al Inversor y al Jefe de Seguridad.
  const p2 = g.room.state.players.get('p2')!;
  p2.alive = false; p2.ghost = true;
  assert.equal(g.act('p2', { t: 'ghost_ping', position: { x: 10, y: 20 } }), null);
  assert.deepEqual(g.out.events('p3', 'ghost_ping'), [{ e: 'ghost_ping', by: 'p2', position: { x: 10, y: 20 }, until: g.clock.t + 6_000 }]);
  assert.equal(g.out.events('p5', 'ghost_ping').length, 1);
  assert.equal(g.out.events('p0', 'ghost_ping').length, 0);
  assert.equal(g.out.events('p4', 'ghost_ping').length, 0, 'el Filtrador es mercenario');
  assert.equal(g.act('p2', { t: 'ghost_ping', position: { x: 10, y: 20 } }), 'on_cooldown');
  g.wait(20_000);
  assert.equal(g.act('p2', { t: 'ghost_ping', position: { x: 10, y: 20 } }), null);
});

test('misiones fantasma: 6 s, moverse cancela; al completar brilla una pista o reaparece una destruida', () => {
  const g = ghostP4();
  const task = () => g.room.state.players.get('p4')!.ghostTasks.find((t) => !t.done)!;
  let t = task();
  g.place('p4', t.position.x + 200, t.position.y);
  assert.equal(g.act('p4', { t: 'ghost_task', taskId: t.id }), 'too_far');
  assert.equal(g.act('p4', { t: 'ghost_task', taskId: 'gt_x' }), 'unknown_task');
  g.place('p4', t.position.x, t.position.y);
  assert.equal(g.act('p4', { t: 'ghost_task', taskId: t.id }), null);
  assert.equal(g.room['projector'].snapshotFor('p4').players.find((p) => p.id === 'p4')!.channel!.kind, 'ghost_task');
  assert.equal(g.room['projector'].snapshotFor('p2').players.find((p) => p.id === 'p4')!.channel, undefined);
  g.wait(1_000);
  assert.equal(g.act('p4', { t: 'move', position: { x: t.position.x + 50, y: t.position.y } }), null);
  assert.equal(g.room.state.players.get('p4')!.ghostChannel, null, 'moverse cancela');
  // Completar: sin pistas destruidas → brilla la más cercana para los vivos.
  g.place('p4', t.position.x, t.position.y);
  assert.equal(g.act('p4', { t: 'ghost_task', taskId: t.id }), null);
  g.wait(6_000);
  assert.equal(t.done, true);
  assert.equal(g.room.state.players.get('p4')!.ghostTasks.length, 4, 'se asigna otra');
  const reveal = g.out.events('p2', 'ghost_reveal')[0] as { interactableId: string; until: number };
  assert.ok(reveal.interactableId.startsWith('spawn_'));
  assert.equal(reveal.until, g.clock.t + 20_000);
  assert.equal(g.out.events('p4', 'ghost_reveal').length, 0, 'solo a los vivos');
  // Con una pista destruida: reaparece una copia en su sitio.
  const laptopSpot = g.room.evidence.listInteractables().find((i) => i.id === 'spawn_CLUE_UNLOCKED_LAPTOP')!;
  g.room.evidence.forceDestroy('p0', laptopSpot.contents()[0]!);
  assert.equal(laptopSpot.contents().length, 0);
  t = task();
  g.place('p4', t.position.x, t.position.y);
  assert.equal(g.act('p4', { t: 'ghost_task', taskId: t.id }), null);
  g.wait(6_000);
  assert.equal(laptopSpot.contents().length, 1);
  assert.ok(g.room.evidence.getInstance(laptopSpot.contents()[0]!)!.copyOf);
  // Máximo 6 misiones en total.
  for (let k = 0; k < 10; k++) {
    const next = g.room.state.players.get('p4')!.ghostTasks.find((x) => !x.done);
    if (!next) break;
    g.place('p4', next.position.x, next.position.y);
    g.act('p4', { t: 'ghost_task', taskId: next.id });
    g.wait(6_000);
  }
  assert.equal(g.room.state.players.get('p4')!.ghostTasks.length, 6);
});
