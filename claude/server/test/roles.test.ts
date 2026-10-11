import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { SeededRandom } from '../src/core/Random.js';
import { createRoleManager, InMemoryRoleConfigSource, RoleConfigError, type RoleSetConfig } from '../src/domain/roles/index.js';

const rolesPath = fileURLToPath(new URL('../../../../shared/config/roles/mansion_clasica.json', import.meta.url));
const loadConfig = async () => JSON.parse(await readFile(rolesPath, 'utf8')) as RoleSetConfig;

async function setup(seed = 1) {
  const cfg = await loadConfig();
  const { roleManager } = createRoleManager(new InMemoryRoleConfigSource({ [cfg.id]: cfg }), new SeededRandom(seed));
  await roleManager.loadRoleSet(cfg.id);
  return roleManager;
}

test('asigna respetando mínimos y máximos', async () => {
  for (let seed = 1; seed <= 50; seed++) {
    const rm = await setup(seed);
    const players = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    const counts = new Map<string, number>();
    for (const roleId of rm.assignRoles(players).values()) counts.set(roleId, (counts.get(roleId) ?? 0) + 1);
    assert.equal(counts.get('detective'), 1);
    assert.equal(counts.get('asesino'), 1, 'el asesino tiene weight 0: solo entra por mínimo');
    assert.ok((counts.get('mayordomo') ?? 0) <= 1);
  }
});

test('modificadores alteran stats', async () => {
  const rm = await setup();
  rm.assignRoles(['a', 'b', 'c', 'd']);
  rm.setRole('a', 'detective');
  rm.setRole('b', 'asesino');
  assert.equal(rm.getStats('a').interactRange, 96);
  assert.equal(rm.getStats('b').inventoryCapacity, 3);
  assert.ok(rm.getStats('b').destroyableTags.has('incriminatoria'));
});

test('visibilidad: la regla más restrictiva gana y el ojo forense la eleva', async () => {
  const rm = await setup();
  rm.assignRoles(['a', 'b', 'c', 'd']);
  rm.setRole('a', 'mayordomo');
  rm.setRole('b', 'detective');
  rm.setRole('c', 'invitado');
  assert.equal(rm.visibilityFor('a', ['documento', 'fisica']), 'hidden');
  assert.equal(rm.visibilityFor('a', ['llave']), 'full');
  assert.equal(rm.visibilityFor('b', ['fisica', 'coartada_falsa']), 'full'); // forensic_eye
  assert.equal(rm.visibilityFor('c', ['fisica']), 'partial');
});

test('el asesino conoce a su compañero; los demás no', async () => {
  const rm = await setup();
  rm.assignRoles(['a', 'b', 'c', 'd', 'e']);
  rm.setRole('a', 'asesino');
  rm.setRole('b', 'asesino');
  rm.setRole('c', 'detective');
  assert.deepEqual(rm.knownTeammates('a'), ['b']);
  assert.deepEqual(rm.knownTeammates('c'), []);
});

test('rechaza configs incoherentes con todos los motivos', async () => {
  const cfg = await loadConfig();
  cfg.roles[0]!.modifiers.push({ id: 'teletransporte' });
  cfg.roles[1]!.visibility.rules.push({ tags: ['x'], level: 'transparente' as never });
  cfg.minPlayers = 0;
  const { roleManager } = createRoleManager(new InMemoryRoleConfigSource({ [cfg.id]: cfg }), new SeededRandom(1));
  await assert.rejects(roleManager.loadRoleSet(cfg.id), (e: unknown) => {
    assert.ok(e instanceof RoleConfigError);
    assert.equal(e.problems.length, 3);
    return true;
  });
});
