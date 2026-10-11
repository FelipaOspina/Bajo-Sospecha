import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { EventBus } from '../src/core/EventBus.js';
import { SeededRandom } from '../src/core/Random.js';
import { createEvidenceSystem, type EvidenceEvents } from '../src/domain/evidence/index.js';
import { createRoleManager, InMemoryRoleConfigSource } from '../src/domain/roles/index.js';
import { compileScenario, ScenarioError } from '../src/domain/scenario/ScenarioAdapter.js';
import type { Vec2 } from '../../shared/protocol/protocol.js';

const scenarioPath = fileURLToPath(new URL('../../../../shared/config/scenarios/nexuscore_fraude.json', import.meta.url));
const load = async () => JSON.parse(await readFile(scenarioPath, 'utf8'));

test('el escenario de ejemplo compila y pasa el validador de roles', async () => {
  const compiled = compileScenario(await load());
  const { roleManager } = createRoleManager(
    new InMemoryRoleConfigSource({ [compiled.roleSet.id]: compiled.roleSet }), new SeededRandom(3));
  await roleManager.loadRoleSet(compiled.roleSet.id);
  assert.equal(compiled.map.interactables.length, 5);
  assert.deepEqual(compiled.map.interactables[1]!.position, { x: 640, y: 120 }, 'acepta posición como [x, y]');
  const assigned = roleManager.assignRoles(['a', 'b', 'c', 'd', 'e', 'f']);
  assert.equal(assigned.size, 6);
  assert.equal(roleManager.getRole('ROLE_CTO')!.objectives[0]!.type, 'narrative');
});

test('beneficia/perjudica se traducen en visibilidad y permisos', async () => {
  const compiled = compileScenario(await load());
  const { roleManager } = createRoleManager(
    new InMemoryRoleConfigSource({ [compiled.roleSet.id]: compiled.roleSet }), new SeededRandom(3));
  await roleManager.loadRoleSet(compiled.roleSet.id);
  roleManager.assignRoles(['ceo', 'cto', 'inv', 'leak']);
  roleManager.setRole('ceo', 'ROLE_CEO');
  roleManager.setRole('cto', 'ROLE_CTO');
  roleManager.setRole('inv', 'ROLE_INVESTOR');
  roleManager.setRole('leak', 'ROLE_LEAKER');

  const tagsOf = (id: string) => compiled.map.evidence.find((e) => e.id === id)!.tags;
  assert.equal(roleManager.visibilityFor('cto', tagsOf('CLUE_SERVER_LOGS')), 'full');
  assert.equal(roleManager.visibilityFor('leak', tagsOf('CLUE_SERVER_LOGS')), 'partial');

  const positions = new Map<string, Vec2>();
  const sys = createEvidenceSystem(compiled.map, roleManager, {
    positionOf: (p) => positions.get(p), isAlive: () => true, currentPhase: () => 'investigation', now: () => 0,
  }, new EventBus<EvidenceEvents>());

  positions.set('cto', { x: 200, y: 150 });
  assert.deepEqual(sys.interact('cto', 'spawn_CLUE_SERVER_LOGS'), { ok: false, error: 'not_pocketable' });

  positions.set('ceo', { x: 200, y: 550 });
  const contract = sys.interact('ceo', 'spawn_CLUE_TORN_CONTRACT');
  assert.ok(contract.ok);
  assert.deepEqual(sys.destroy('ceo', contract.value.instanceId), { ok: false, error: 'cannot_destroy' },
    'sin modificador no hay destrucción instantánea: se usa la acción canalizada');
});

test('lista todos los errores del escenario', () => {
  assert.throws(() => compileScenario({
    scenario_id: 'x', title: 'X',
    roles: [{ id: 'A', name: 'A', secret_objectives: [] }],
    evidence_spawns: [
      { id: 'e1', name: 'E', description: '', type: 'video', position: { x: 0, y: 0 }, benefits: ['B'] },
      { id: 'e1', name: 'E', description: '', type: 'item', position: 'aquí' },
    ],
  }), (e: unknown) => {
    assert.ok(e instanceof ScenarioError);
    assert.equal(e.problems.length, 4); // tipo, rol inexistente, id duplicado, posición
    return true;
  });
});

test('permiso por rol: los logs solo los leen CEO, CTO y Filtrador', async () => {
  const compiled = compileScenario(await load());
  const { roleManager } = createRoleManager(
    new InMemoryRoleConfigSource({ [compiled.roleSet.id]: compiled.roleSet }), new SeededRandom(3));
  await roleManager.loadRoleSet(compiled.roleSet.id);
  roleManager.assignRoles(['ceo', 'cto', 'inv', 'leak']);
  roleManager.setRole('cto', 'ROLE_CTO');
  roleManager.setRole('inv', 'ROLE_INVESTOR');
  const sys = createEvidenceSystem(compiled.map, roleManager, {
    positionOf: () => ({ x: 200, y: 150 }), isAlive: () => true, currentPhase: () => 'investigation', now: () => 0,
  }, new EventBus<EvidenceEvents>());
  const [logs] = sys.listInteractables().find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents();
  assert.equal(sys.visibilityOf('cto', logs!), 'full');
  assert.equal(sys.visibilityOf('inv', logs!), 'partial', 'le beneficia, pero no tiene el rol requerido');
  assert.equal(sys.definitionOf(logs!)!.content?.text !== undefined, true);
});

test('requires con referencias rotas se rechaza', () => {
  assert.throws(() => compileScenario({
    scenario_id: 'x', title: 'X',
    roles: [{ id: 'A', name: 'A', secret_objectives: [] }],
    evidence_spawns: [{ id: 'e1', name: 'E', description: '', type: 'item', position: [0, 0],
      requires: { view: { roles: ['Z'] }, collect: { items: ['llave'] } } }],
  }), (e: unknown) => e instanceof ScenarioError && e.problems.length === 2);
});
