import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { EventBus } from '../src/core/EventBus.js';
import { SeededRandom } from '../src/core/Random.js';
import { createEvidenceSystem, type EvidenceEvents, type EvidenceMapConfig } from '../src/domain/evidence/index.js';
import { createRoleManager, InMemoryRoleConfigSource, type RoleSetConfig } from '../src/domain/roles/index.js';
import type { RoomPhase, Vec2 } from '../../shared/protocol/protocol.js';

const cfgUrl = (p: string) => fileURLToPath(new URL(`../../../../shared/config/${p}`, import.meta.url));

async function setup() {
  const roles = JSON.parse(await readFile(cfgUrl('roles/mansion_clasica.json'), 'utf8')) as RoleSetConfig;
  const map = JSON.parse(await readFile(cfgUrl('evidence/mansion_clasica.json'), 'utf8')) as EvidenceMapConfig;
  const { roleManager } = createRoleManager(new InMemoryRoleConfigSource({ [roles.id]: roles }), new SeededRandom(1));
  await roleManager.loadRoleSet(roles.id);
  roleManager.assignRoles(['det', 'ase', 'may', 'inv']);
  roleManager.setRole('det', 'detective');
  roleManager.setRole('ase', 'asesino');
  roleManager.setRole('may', 'mayordomo');
  roleManager.setRole('inv', 'invitado');

  const positions = new Map<string, Vec2>();
  let phase: RoomPhase = 'investigation';
  const bus = new EventBus<EvidenceEvents>();
  const events: string[] = [];
  bus.on('evidence.collected', (e) => events.push(`collected:${e.playerId}:${e.interactableId}`));
  bus.on('evidence.destroyed', (e) => events.push(`destroyed:${e.playerId}`));

  const system = createEvidenceSystem(map, roleManager, {
    positionOf: (p) => positions.get(p),
    isAlive: () => true,
    currentPhase: () => phase,
    now: () => 0,
  }, bus);
  return { system, positions, events, setPhase: (p: RoomPhase) => (phase = p) };
}

test('recoger una prueba cercana la mueve al inventario y emite evento', async () => {
  const { system, positions, events } = await setup();
  positions.set('det', { x: 130, y: 330 });
  const r = system.interact('det', 'cocina_cajon');
  assert.ok(r.ok);
  assert.equal(system.inventoryOf('det').length, 1);
  assert.deepEqual(events, ['collected:det:cocina_cajon']);
  assert.equal(system.interact('det', 'cocina_cajon').ok, false, 'el cajón ya está vacío');
});

test('fuera de rango o fuera de fase se rechaza', async () => {
  const { system, positions, setPhase } = await setup();
  positions.set('inv', { x: 600, y: 600 });
  assert.deepEqual(system.interact('inv', 'cocina_cajon'), { ok: false, error: 'out_of_range' });
  positions.set('inv', { x: 120, y: 340 });
  setPhase('discussion');
  assert.deepEqual(system.interact('inv', 'cocina_cajon'), { ok: false, error: 'wrong_phase' });
});

test('una prueba oculta para el rol no se puede encontrar', async () => {
  const { system, positions } = await setup();
  positions.set('may', { x: 900, y: 520 });
  assert.deepEqual(system.interact('may', 'jardin_suelo'), { ok: false, error: 'nothing_found' });
});

test('el contenedor entrega la primera prueba visible', async () => {
  const { system, positions } = await setup();
  positions.set('may', { x: 400, y: 600 });
  const r = system.interact('may', 'salon_baul');
  assert.ok(r.ok && r.value.definitionId === 'llave_sotano');
});

test('capacidad de inventario según modificadores', async () => {
  const { system, positions } = await setup();
  // asesino: capacidad 5 - 2 = 3; cuchillo pesa 2, llave 1, huella 1 → la huella no cabe
  for (const [id, pos] of [['cocina_cajon', { x: 120, y: 340 }], ['pasillo_cuadro', { x: 300, y: 120 }]] as const) {
    positions.set('ase', pos);
    assert.ok(system.interact('ase', id).ok);
  }
  positions.set('ase', { x: 900, y: 520 });
  assert.deepEqual(system.interact('ase', 'jardin_suelo'), { ok: false, error: 'inventory_full' });
});

test('solo quien tiene permiso puede destruir, y solo pruebas con la etiqueta', async () => {
  const { system, positions, events } = await setup();
  positions.set('ase', { x: 120, y: 340 });
  const knife = system.interact('ase', 'cocina_cajon');
  assert.ok(knife.ok);
  positions.set('det', { x: 900, y: 520 });
  const print = system.interact('det', 'jardin_suelo');
  assert.ok(print.ok);
  assert.deepEqual(system.destroy('det', print.value.instanceId), { ok: false, error: 'cannot_destroy' });
  assert.ok(system.destroy('ase', knife.value.instanceId).ok);
  assert.equal(system.visibilityOf('det', knife.value.instanceId), 'hidden');
  assert.ok(events.includes('destroyed:ase'));
});

test('soltar deja la prueba en el punto libre más cercano', async () => {
  const { system, positions } = await setup();
  positions.set('inv', { x: 120, y: 340 });
  const r = system.interact('inv', 'cocina_cajon');
  assert.ok(r.ok);
  const d = system.drop('inv', r.value.instanceId);
  assert.ok(d.ok && d.value.id === 'cocina_cajon');
});

test('permiso con llave: sin ella la carta se ve en parcial y no se recoge; con ella, sí', async () => {
  const { system, positions } = await setup();
  positions.set('det', { x: 610, y: 210 });
  const [carta] = system.listInteractables().find((i) => i.id === 'estudio_mesa')!.contents();
  assert.equal(system.visibilityOf('det', carta!), 'partial');
  assert.deepEqual(system.accessOf('det', carta!, 'view'), { ok: false, missing: 'item', missingItems: ['llave_estudio'] });
  assert.deepEqual(system.interact('det', 'estudio_mesa'), { ok: false, error: 'requires_item' });

  positions.set('det', { x: 300, y: 120 });
  assert.ok(system.interact('det', 'pasillo_cuadro').ok);
  positions.set('det', { x: 610, y: 210 });
  assert.equal(system.visibilityOf('det', carta!), 'full');
  assert.ok(system.interact('det', 'estudio_mesa', carta).ok, 'recoge la pieza concreta pedida');
});

test('pedir una pieza concreta de un contenedor', async () => {
  const { system, positions } = await setup();
  positions.set('inv', { x: 400, y: 600 });
  const [, ticket] = system.listInteractables().find((i) => i.id === 'salon_baul')!.contents();
  const r = system.interact('inv', 'salon_baul', ticket);
  assert.ok(r.ok && r.value.definitionId === 'ticket');
  assert.deepEqual(system.interact('inv', 'salon_baul', 'no-existe'), { ok: false, error: 'nothing_found' });
});
