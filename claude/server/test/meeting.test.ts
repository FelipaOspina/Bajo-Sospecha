import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { startGame, type Game } from './helpers.js';

/**
 * Fusión con los cambios del usuario: su `call_meeting` es ahora el botón de emergencia
 * (abre la asamblea de emergencia, no el juicio), `skip_to_voting` sigue siendo del juicio final
 * y el chat se abre en discussion/voting/emergency, pero no para fantasmas.
 */
const SIX = ['ROLE_CEO', 'ROLE_ACCOMPLICE', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'];
const ALL = ['p0', 'p1', 'p2', 'p3', 'p4', 'p5'];

/** Todos los que pueden votan skip y se espera a que vuelva la investigación. */
function closeEmergency(g: Game): void {
  for (const p of ALL) g.act(p, { t: 'emergency_vote', targetId: 'skip' });
  g.wait(4_000);
  assert.equal(g.room.phase, 'investigation');
}

/** Deja a p4 (Filtrador) como fantasma: el CEO le silencia dos veces. */
function ghostP4(g: Game): void {
  for (let k = 0; k < 2; k++) {
    g.place('p0', 0, 0); g.place('p4', 50, 0);
    assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
    g.wait(60_000);
  }
  assert.equal(g.room.state.players.get('p4')!.ghost, true);
}

test('call_meeting abre la asamblea de EMERGENCIA (calledBy, sin cuerpo) y conserva el tiempo de la investigación', () => {
  const g = startGame(SIX);
  g.wait(5_000);
  const remaining = g.room.state.phaseEndsAt! - g.clock.t;
  assert.equal(g.act('p3', { t: 'call_meeting' }), null);
  assert.equal(g.room.phase, 'emergency', 'no salta al juicio final');
  for (const p of ALL) assert.deepEqual(g.out.events(p, 'meeting_called'), [{ e: 'meeting_called', by: 'p3' }]);
  const snap = g.room['projector'].snapshotFor('p2');
  assert.equal(snap.emergency!.calledBy, 'p3');
  assert.equal(snap.emergency!.bodyId, null);
  assert.equal(snap.emergency!.remaining, remaining);
  assert.equal(g.room['projector'].snapshotFor('p3').you!.meetingUsed, true);
  assert.equal(g.room['projector'].snapshotFor('p2').you!.meetingUsed, undefined);
  assert.equal(g.act('p2', { t: 'call_meeting' }), 'wrong_phase', 'no se convoca durante otra emergencia');
  closeEmergency(g);
  assert.equal(g.room.state.phaseEndsAt, g.clock.t + remaining);
});

test('call_meeting: una vez por jugador y partida, y cuenta para el máximo de 3 emergencias', () => {
  const g = startGame(SIX);
  assert.equal(g.act('p0', { t: 'call_meeting' }), null);
  closeEmergency(g);
  assert.equal(g.act('p0', { t: 'call_meeting' }), 'meeting_used');
  assert.equal(g.room.phase, 'investigation');
  assert.equal(g.act('p1', { t: 'call_meeting' }), null);
  closeEmergency(g);
  assert.equal(g.act('p2', { t: 'call_meeting' }), null);
  closeEmergency(g);
  assert.equal(g.room.state.emergenciesHeld, 3);
  assert.equal(g.act('p3', { t: 'call_meeting' }), 'no_meetings_left');
  assert.equal(g.room.phase, 'investigation');
  assert.equal(g.room['projector'].snapshotFor('p3').you!.meetingUsed, undefined, 'el rechazo no gasta su botón');
});

test('call_meeting: noqueados y fantasmas no pueden; fuera de la investigación, wrong_phase', () => {
  const g = startGame(SIX, { skipGrace: true });
  g.place('p0', 0, 0); g.place('p4', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  assert.equal(g.act('p4', { t: 'call_meeting' }), 'knocked');
  g.wait(60_000);
  g.place('p0', 0, 0); g.place('p4', 50, 0);
  assert.equal(g.act('p0', { t: 'silence', targetId: 'p4' }), null);
  assert.equal(g.room.state.players.get('p4')!.ghost, true);
  assert.equal(g.act('p4', { t: 'call_meeting' }), 'not_alive');
  assert.equal(g.room.phase, 'investigation');
  g.wait(g.room.state.phaseEndsAt! - g.clock.t + 1);
  assert.equal(g.room.phase, 'discussion');
  assert.equal(g.act('p2', { t: 'call_meeting' }), 'wrong_phase');
});

test('chat: cerrado en la investigación; abierto en emergencia, debate y votación; los fantasmas no escriben', () => {
  const g = startGame(SIX, { skipGrace: true });
  ghostP4(g);
  assert.equal(g.act('p2', { t: 'chat', text: 'hola' }), 'wrong_phase', 'en la investigación no hay chat');

  // Emergencia: hablan los vivos; el fantasma no.
  assert.equal(g.act('p2', { t: 'call_meeting' }), null);
  assert.equal(g.act('p2', { t: 'chat', text: '  Vi al   CEO en el pasillo ' }), null);
  for (const p of ALL) {
    const ev = g.out.events(p, 'chat').at(-1) as { by: string; text: string } | undefined;
    assert.deepEqual([ev?.by, ev?.text], ['p2', 'Vi al CEO en el pasillo'], `${p} recibe el chat (también el fantasma lo lee)`);
  }
  const before = g.out.events('p2', 'chat').length;
  assert.equal(g.act('p4', { t: 'chat', text: 'fui yo… no, el CEO' }), 'not_alive');
  assert.equal(g.out.events('p2', 'chat').length, before, 'el mensaje del fantasma no llega a nadie');
  closeEmergency(g);

  // Juicio final: debate y votación.
  g.wait(g.room.state.phaseEndsAt! - g.clock.t + 1);
  assert.equal(g.room.phase, 'discussion');
  assert.equal(g.act('p3', { t: 'chat', text: 'Presento los logs' }), null);
  assert.equal(g.act('p4', { t: 'chat', text: '¡escuchadme!' }), 'not_alive');
  assert.equal(g.act('p4', { t: 'skip_to_voting' }), 'not_alive', 'un fantasma no adelanta la votación');
  assert.equal(g.act('p3', { t: 'skip_to_voting' }), null);
  assert.equal(g.room.phase, 'voting');
  assert.equal(g.act('p0', { t: 'chat', text: 'Votad al CTO' }), null);
  assert.equal(g.act('p4', { t: 'chat', text: 'no' }), 'not_alive');
  assert.equal(g.act('p0', { t: 'skip_to_voting' }), 'wrong_phase');
});
