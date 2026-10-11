import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import type { ServerMessage } from '../../shared/protocol/protocol.js';
import { SeededRandom } from '../src/core/Random.js';
import type { EvidenceMapConfig } from '../src/domain/evidence/index.js';
import { createRoleManager, InMemoryRoleConfigSource, type RoleSetConfig } from '../src/domain/roles/index.js';
import { SkinCatalog, type SkinConfig } from '../src/domain/skins/SkinCatalog.js';
import { Room } from '../src/net/Room.js';

const cfgUrl = (p: string) => fileURLToPath(new URL(`../../../../shared/config/${p}`, import.meta.url));

async function lobby(skinConfig: SkinConfig) {
  const roles = JSON.parse(await readFile(cfgUrl('roles/mansion_clasica.json'), 'utf8')) as RoleSetConfig;
  const map = JSON.parse(await readFile(cfgUrl('evidence/mansion_clasica.json'), 'utf8')) as EvidenceMapConfig;
  const { roleManager, objectives } = createRoleManager(new InMemoryRoleConfigSource({ [roles.id]: roles }), new SeededRandom(3));
  await roleManager.loadRoleSet(roles.id);
  const inbox = new Map<string, ServerMessage[]>();
  const room = new Room('s', { roles: roleManager, objectives, map, skins: new SkinCatalog(skinConfig, new SeededRandom(5)) }, {
    send: (p, m) => inbox.set(p, [...(inbox.get(p) ?? []), m]),
  }, { now: () => 0 });
  const ids = ['p1', 'p2', 'p3', 'p4'];
  ids.forEach((id) => room.connect(id, id.toUpperCase()));
  const reply = (id: string) => { const m = inbox.get(id)!.at(-1)!; return m.t === 'rejected' ? m.reason : m.t; };
  return { room, ids, roleManager, reply, skinOf: (viewer: string, id: string) => room['projector'].snapshotFor(viewer).players.find((p) => p.id === id)?.skinId };
}

test('skins: cada jugador recibe una distinta, visible para todos y sin relación con su rol', async () => {
  const config = JSON.parse(await readFile(cfgUrl('skins/skins.json'), 'utf8')) as SkinConfig;
  assert.equal(config.assign_by_role, false, 'el mapeo rol → skin viene desactivado: delataría los roles');
  const { room, ids, reply, skinOf } = await lobby(config);

  const skins = ids.map((id) => skinOf('p1', id));
  assert.ok(skins.every((s) => s && config.skins.some((c) => c.id === s)));
  assert.equal(new Set(skins).size, ids.length, 'sin repetir mientras haya libres');
  assert.equal(skinOf('p2', 'p3'), skinOf('p3', 'p3'), 'todos ven la misma skin');

  // Elegir en el lobby: libre sí, ocupada o inexistente no.
  const free = config.skins.map((s) => s.id).find((s) => !skins.includes(s))!;
  room.handleIntent('p1', { t: 'choose_skin', seq: 1, skinId: free });
  assert.equal(reply('p1'), 'ack');
  assert.equal(skinOf('p2', 'p1'), free);
  room.handleIntent('p2', { t: 'choose_skin', seq: 1, skinId: free });
  assert.equal(reply('p2'), 'skin_taken');
  room.handleIntent('p2', { t: 'choose_skin', seq: 2, skinId: 'dragon' });
  assert.equal(reply('p2'), 'unknown_skin');

  // Empieza la partida: la skin no cambia con el rol.
  const before = ids.map((id) => skinOf('p1', id));
  ids.forEach((id) => room.handleIntent(id, { t: 'ready', seq: 10, ready: true }));
  assert.equal(room.phase, 'briefing');
  assert.deepEqual(ids.map((id) => skinOf('p1', id)), before);
  room.handleIntent('p3', { t: 'choose_skin', seq: 11, skinId: free });
  assert.equal(reply('p3'), 'wrong_phase');
});

test('skins: con assign_by_role activo, cada rol lleva su animal al empezar', async () => {
  const roles = JSON.parse(await readFile(cfgUrl('roles/mansion_clasica.json'), 'utf8')) as RoleSetConfig;
  const roleIds = roles.roles.map((r) => r.id);
  const animals = ['leon', 'lobo', 'tigre', 'zorro', 'oso', 'panda'];
  const config: SkinConfig = {
    assign_by_role: true,
    role_skins: Object.fromEntries(roleIds.map((r, i) => [r, animals[i % animals.length]!])),
    skins: animals.map((id) => ({ id, name: id })),
  };
  const { room, ids, roleManager, skinOf } = await lobby(config);
  ids.forEach((id) => room.handleIntent(id, { t: 'ready', seq: 1, ready: true }));
  for (const id of ids) assert.equal(skinOf(id, id), config.role_skins![roleManager.getRoleOf(id)!.id]);
});
