import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import type { ServerMessage } from '../../shared/protocol/protocol.js';
import { SeededRandom } from '../src/core/Random.js';
import type { EvidenceMapConfig } from '../src/domain/evidence/index.js';
import { createRoleManager, InMemoryRoleConfigSource, type RoleSetConfig } from '../src/domain/roles/index.js';
import { Room } from '../src/net/Room.js';

const cfgUrl = (p: string) => fileURLToPath(new URL(`../../../../shared/config/${p}`, import.meta.url));

test('flujo de sala: lobby → roles → investigación, con estado filtrado por jugador', async () => {
  const roles = JSON.parse(await readFile(cfgUrl('roles/mansion_clasica.json'), 'utf8')) as RoleSetConfig;
  const map = JSON.parse(await readFile(cfgUrl('evidence/mansion_clasica.json'), 'utf8')) as EvidenceMapConfig;
  const { roleManager, objectives } = createRoleManager(new InMemoryRoleConfigSource({ [roles.id]: roles }), new SeededRandom(7));
  await roleManager.loadRoleSet(roles.id);

  let now = 0;
  const inbox = new Map<string, ServerMessage[]>();
  const room = new Room('t', { roles: roleManager, objectives, map }, {
    send: (p, m) => inbox.set(p, [...(inbox.get(p) ?? []), m]),
  }, { now: () => now });

  const ids = ['p1', 'p2', 'p3', 'p4'];
  ids.forEach((id) => room.connect(id, id.toUpperCase()));
  ids.forEach((id) => room.handleIntent(id, { t: 'ready', seq: 1, ready: true }));
  assert.equal(room.state.phase, 'briefing');

  now += 10_000;
  room.tick();
  assert.equal(room.state.phase, 'investigation');

  // Cada jugador solo ve su propio rol (salvo compañeros conocidos).
  for (const id of ids) {
    const snap = room['projector'].snapshotFor(id);
    const visibleRoles = snap.players.filter((p) => p.roleId).map((p) => p.id);
    assert.ok(visibleRoles.includes(id));
    assert.equal(visibleRoles.length, 1 + roleManager.knownTeammates(id).length);
  }

  // Mover a saltos pequeños hasta el cajón y recoger.
  const p = 'p1';
  let seq = 1;
  for (const x of [40, 80, 110]) { now += 200; room.handleIntent(p, { t: 'move', seq: ++seq, position: { x, y: 340 } }); }
  inbox.clear();
  room.handleIntent(p, { t: 'interact', seq: ++seq, interactableId: 'cocina_cajon' });
  const mine = inbox.get(p)!;
  const collected = mine.find((m) => m.t === 'event' && m.event.e === 'evidence_collected');
  assert.ok(collected && collected.t === 'event' && collected.event.e === 'evidence_collected');
  assert.equal(collected.event.evidence?.visibility, 'full');
  const other = inbox.get('p2')!.find((m) => m.t === 'event' && m.event.e === 'evidence_collected');
  assert.ok(other && other.t === 'event' && other.event.e === 'evidence_collected' && other.event.evidence === undefined,
    'los demás saben que alguien cogió algo, pero no qué');
  assert.ok(mine.some((m) => m.t === 'ack'));

  // La carta del estudio pide una llave: el visor recibe el candado y el nombre de la llave.
  const carta = room['projector'].snapshotFor('p2').interactables.find((i) => i.id === 'estudio_mesa')!.contents[0]!;
  assert.equal(carta.locked, 'view');
  assert.deepEqual(carta.requiredItems, ['Llave del estudio']);
  assert.equal(carta.name, undefined, 'sin la llave no llegan los detalles');

  // Un teletransporte se rechaza.
  now += 50;
  room.handleIntent(p, { t: 'move', seq: ++seq, position: { x: 900, y: 900 } });
  assert.ok(inbox.get(p)!.some((m) => m.t === 'rejected' && m.reason === 'too_fast'));

  // El siguiente tick manda un delta con el inventario nuevo.
  inbox.clear();
  room.tick();
  const delta = inbox.get(p)!.find((m) => m.t === 'delta');
  assert.ok(delta && delta.t === 'delta' && delta.ops.some((o) => o.path[0] === 'you'));
});
