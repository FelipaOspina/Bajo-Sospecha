import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { give, startGame, type Game } from './helpers.js';

const SIX = ['ROLE_CEO', 'ROLE_ACCOMPLICE', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'];

/** El CEO (p0) noquea al Filtrador (p4) y el CTO (p2) reporta el cuerpo. */
function knockAndReport(g: Game): number {
  g.place('p0', 0, 0); g.place('p4', 50, 0); g.place('p2', 100, 100);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  const remaining = g.room.state.phaseEndsAt! - g.clock.t;
  assert.equal(g.act('p2', { t: 'report_body', bodyId: 'body:p4' }), null);
  return remaining;
}

test('report_body: rechazos', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p0', 0, 0); g.place('p4', 50, 0); g.place('p2', 400, 0);
  assert.equal(g.act('p2', { t: 'report_body', bodyId: 'body:p4' }), 'unknown_body');
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  assert.equal(g.act('p2', { t: 'report_body', bodyId: 'body:p4' }), 'too_far');
  assert.equal(g.act('p4', { t: 'report_body', bodyId: 'body:p4' }), 'knocked');
  assert.equal(g.act('p2', { t: 'emergency_vote', targetId: 'skip' }), 'wrong_phase');
});

test('report → emergencia → expulsión (sin revelar rol) → vuelve con el tiempo restante', () => {
  const g = startGame(SIX, { skipGrace: true });
  const remaining = knockAndReport(g);
  assert.equal(g.room.phase, 'emergency');
  for (const p of ['p0', 'p1', 'p2', 'p3', 'p4', 'p5']) assert.deepEqual(g.out.events(p, 'body_reported'), [{ e: 'body_reported', by: 'p2', bodyId: 'body:p4', victim: 'p4' }]);
  const snap = g.room['projector'].snapshotFor('p3');
  assert.equal(snap.emergency!.calledBy, 'p2');
  assert.equal(snap.emergency!.remaining, remaining);
  assert.equal(snap.phaseEndsAt, g.clock.t + 75_000);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p3' }), 'wrong_phase');
  // Votan los 6 en pie (el noqueado también); 4 de 6 al Abogado = mayoría estricta.
  assert.equal(g.act('p2', { t: 'emergency_vote', targetId: 'p1' }), null);
  assert.equal(g.act('p2', { t: 'emergency_vote', targetId: 'nadie' }), 'unknown_target');
  g.wait(5_000);
  for (const p of ['p3', 'p4', 'p5']) assert.equal(g.act(p, { t: 'emergency_vote', targetId: 'p1' }), null);
  assert.equal(g.room['projector'].snapshotFor('p3').emergency!.myVote, 'p1');
  assert.deepEqual(g.room['projector'].snapshotFor('p3').emergency!.voted.sort(), ['p2', 'p3', 'p4', 'p5']);
  assert.equal(g.act('p0', { t: 'emergency_vote', targetId: 'skip' }), null);
  assert.equal(g.act('p1', { t: 'emergency_vote', targetId: 'skip' }), null);
  // Todos votaron: recuento.
  const p1 = g.room.state.players.get('p1')!;
  assert.deepEqual([p1.alive, p1.ghost], [false, true]);
  assert.equal(g.room.state.bodies.some((b) => b.playerId === 'p1'), false, 'sin cuerpo');
  assert.deepEqual(g.out.events('p2', 'emergency_result'), [{ e: 'emergency_result', expelled: 'p1', tally: { p1: 4, skip: 2 } }]);
  assert.equal(g.room['projector'].snapshotFor('p2').players.find((p) => p.id === 'p1')!.roleId, undefined, 'el rol no se revela');
  assert.equal(g.room.phase, 'emergency', 'se ve el resultado unos segundos');
  assert.deepEqual(g.room['projector'].snapshotFor('p2').emergency!.result, { expelled: 'p1', tally: { p1: 4, skip: 2 } });
  g.wait(4_000);
  assert.equal(g.room.phase, 'investigation');
  assert.equal(g.room.state.phaseEndsAt, g.clock.t + remaining);
  assert.equal(g.room['projector'].snapshotFor('p2').emergency, null);
  assert.equal(g.act('p1', { t: 'emergency_vote', targetId: 'skip' }), 'not_alive');
});

test('emergencia: sin mayoría estricta (o skip) no se expulsa; el temporizador también cierra', () => {
  const g = startGame(SIX, { skipGrace: true });
  knockAndReport(g);
  g.act('p2', { t: 'emergency_vote', targetId: 'p1' });
  g.act('p3', { t: 'emergency_vote', targetId: 'p1' });
  g.act('p0', { t: 'emergency_vote', targetId: 'skip' });
  g.act('p1', { t: 'emergency_vote', targetId: 'p3' });
  g.wait(75_000);
  assert.deepEqual(g.out.events('p2', 'emergency_result').at(-1), { e: 'emergency_result', expelled: null, tally: { p1: 2, skip: 1, p3: 1 } });
  assert.equal(g.room.state.players.get('p1')!.alive, true);
  g.wait(4_000);
  assert.equal(g.room.phase, 'investigation');
});

test('CEO expulsado → fin inmediato como si el juicio votara despedir_ceo', () => {
  const g = startGame(SIX, { skipGrace: true });
  knockAndReport(g);
  for (const p of ['p1', 'p2', 'p3', 'p4', 'p5']) g.act(p, { t: 'emergency_vote', targetId: 'p0' });
  g.act('p0', { t: 'emergency_vote', targetId: 'p2' });
  assert.equal(g.room.phase, 'results');
  const over = g.out.events('p2', 'game_over')[0] as { resolution: { verdict: { optionId: string }; endings: { id: string }[]; winners: string[] } };
  assert.equal(over.resolution.verdict.optionId, 'despedir_ceo');
  assert.ok(over.resolution.endings.some((e) => e.id === 'empleados'));
  assert.ok(over.resolution.winners.includes('p5'), 'el Jefe de Seguridad gana con la plantilla');
  assert.ok(!over.resolution.winners.includes('p0'));
});

test('máximo 3 emergencias: después report_body solo retira el cuerpo', () => {
  const g = startGame(['ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE'], { skipGrace: true });
  const victims = ['p3', 'p1', 'p2', 'p4'];
  // Testigos: los que lo ven dan motivo. El CEO siempre puede con el Filtrador; para el resto, una prueba.
  for (const [i, v] of victims.entries()) {
    if (v !== 'p3') give(g, v, ['CLUE_CASINO_DEBTS', 'CLUE_HIDDEN_RECORDER', 'CLUE_FAKE_INVOICES'][i - 1]!);
    g.place('p0', 0, 0); g.place(v, 50, 0); g.place('p7', 100, 100);
    assert.equal(g.act('p0', { t: 'silence', targetId: v }), null, `silencio ${i}`);
    assert.equal(g.act('p7', { t: 'report_body', bodyId: `body:${v}` }), null);
    if (i < 3) {
      assert.equal(g.room.phase, 'emergency');
      g.wait(75_000); g.wait(4_000);
      assert.equal(g.room.phase, 'investigation');
    } else {
      assert.equal(g.room.phase, 'investigation', 'la 4.ª no abre asamblea');
      assert.equal(g.room.state.bodies.find((b) => b.id === `body:${v}`)!.reported, true);
    }
    g.wait(60_000);
  }
  assert.equal(g.room.state.emergenciesHeld, 3);
});

test('silencio_total: culpables en pie >= resto → ganan CEO y cómplices en el acto', () => {
  const g = startGame(['ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER'], { skipGrace: true });
  give(g, 'p1', 'CLUE_CASINO_DEBTS');
  const silenceTwice = (v: string) => {
    for (let k = 0; k < 2; k++) {
      g.place('p0', 0, 0); g.place(v, 50, 0);
      assert.equal(g.act('p0', { t: 'silence', targetId: v }), null);
      g.wait(60_000);
    }
  };
  silenceTwice('p3');
  assert.equal(g.room.phase, 'investigation', '1 contra 2: sigue');
  // El CTO soltó la prueba al ser noqueado: hay que dársela otra vez para tener motivo la 2.ª vez.
  g.place('p0', 0, 0); g.place('p1', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p1' }), null);
  assert.equal(g.room.phase, 'investigation', 'noqueado cuenta en pie');
  g.wait(60_000);
  give(g, 'p1', 'CLUE_FAKE_INVOICES');
  g.place('p0', 0, 0); g.place('p1', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p1' }), null);
  assert.equal(g.room.phase, 'results');
  const over = g.out.events('p2', 'game_over')[0] as { resolution: { endings: { id: string }[]; winners: string[] } };
  assert.deepEqual(over.resolution.endings.map((e) => e.id), ['silencio_total']);
  assert.deepEqual(over.resolution.winners, ['p0']);
});

test('noqueado antes: no puede presentar pruebas en el juicio (knocked_before), pero sí votar', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p0', 0, 0); g.place('p4', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  g.wait(30_000);
  give(g, 'p4', 'CLUE_HIDDEN_RECORDER');
  give(g, 'p3', 'CLUE_CASINO_DEBTS');
  g.wait(300_000);   // fin de la investigación
  assert.equal(g.room.phase, 'discussion');
  const mine = g.room.evidence.inventoryOf('p4')[0]!.instanceId;
  assert.equal(g.act('p4', { t: 'present_evidence', evidenceInstanceId: mine }), 'knocked_before');
  assert.equal(g.act('p3', { t: 'present_evidence', evidenceInstanceId: g.room.evidence.inventoryOf('p3')[0]!.instanceId }), null);
  g.wait(120_000);
  assert.equal(g.room.phase, 'voting');
  assert.equal(g.act('p4', { t: 'vote', optionId: 'despedir_ceo' }), null);
});
