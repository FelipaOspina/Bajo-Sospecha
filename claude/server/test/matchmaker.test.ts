import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import type { ServerMessage } from '../../shared/protocol/protocol.js';
import { Matchmaker } from '../src/net/Matchmaker.js';
import { GameGateway } from '../src/net/GameGateway.js';
import { RoomDirectory } from '../src/net/RoomDirectory.js';
import { Room } from '../src/net/Room.js';
import { createRoleManager, InMemoryRoleConfigSource } from '../src/domain/roles/index.js';
import { SeededRandom } from '../src/core/Random.js';
import { Clock, loadNative } from './helpers.js';

const mm = (clock: Clock) => new Matchmaker<string>({ minSize: 4, maxSize: 12, waitMs: 30_000, now: clock.now });

test('matchmaker: menos de 4 no hay cuenta atrás; con 4 empieza; al vencer salen todos', () => {
  const clock = new Clock();
  const m = mm(clock);
  for (const p of ['a', 'b', 'c']) assert.equal(m.enqueue(p), null);
  assert.equal(m.startsAt, null);
  assert.equal(m.enqueue('d'), null);
  assert.equal(m.startsAt, clock.t + 30_000);
  clock.advance(10_000);
  m.enqueue('e');
  assert.equal(m.startsAt, clock.t + 20_000, 'la cuenta atrás no se reinicia al llegar más');
  clock.advance(19_999);
  assert.equal(m.tick(), null);
  clock.advance(1);
  assert.deepEqual(m.tick(), ['a', 'b', 'c', 'd', 'e']);
  assert.equal(m.waiting().length, 0);
  assert.equal(m.startsAt, null);
});

test('matchmaker: si baja de 4 se cancela la cuenta', () => {
  const clock = new Clock();
  const m = mm(clock);
  ['a', 'b', 'c', 'd'].forEach((p) => m.enqueue(p));
  assert.notEqual(m.startsAt, null);
  m.remove('b');
  assert.equal(m.startsAt, null);
  clock.advance(60_000);
  assert.equal(m.tick(), null);
});

test('matchmaker: con 12 arranca ya un grupo de 12; el resto sigue en cola', () => {
  const clock = new Clock();
  const m = mm(clock);
  const ids = Array.from({ length: 13 }, (_, i) => `p${i}`);
  let group: string[] | null = null;
  for (const id of ids) group = m.enqueue(id) ?? group;
  assert.equal(group!.length, 12);
  assert.deepEqual(m.waiting(), ['p12']);
  assert.equal(m.startsAt, null);
});

test('matchmaker: tamaño fijo antiguo (número) = mínimo y máximo', () => {
  const m = new Matchmaker<string>(4);
  assert.equal(m.matchSize, 4);
  assert.equal(m.minSize, 4);
  ['a', 'b', 'c'].forEach((p) => m.enqueue(p));
  assert.equal(m.enqueue('d')!.length, 4);
});

test('gateway: queued lleva minSize y startsAt; al vencer la cuenta todos entran a una sala pública', () => {
  const clock = new Clock();
  const c = loadNative();
  const gateway = new GameGateway(undefined, { minSize: 4, maxSize: 12, waitMs: 30_000, now: clock.now });
  const directory = new RoomDirectory((code, visibility) => {
    const { roleManager, objectives } = createRoleManager(new InMemoryRoleConfigSource({ [c.roleSet.id]: c.roleSet }), new SeededRandom(1));
    roleManager.useRoleSet(structuredClone(c.roleSet));
    return new Room(code, { roles: roleManager, objectives, map: structuredClone(c.map), trial: c.trial, endings: c.endings }, gateway, { visibility, now: clock.now });
  }, 100, new SeededRandom(2));
  gateway.attach(directory);
  const inbox = new Map<string, ServerMessage[]>();
  const ids = ['a', 'b', 'c', 'd', 'e'];
  ids.forEach((id) => { inbox.set(id, []); gateway.open(id, (m) => inbox.get(id)!.push(m)); });
  ids.forEach((id, i) => gateway.message(id, { t: 'queue_match', seq: 1, name: id.toUpperCase() } as never));
  const lastQueued = (id: string) => inbox.get(id)!.filter((m) => m.t === 'queued').at(-1) as Extract<ServerMessage, { t: 'queued' }>;
  assert.deepEqual(lastQueued('a'), { t: 'queued', position: 1, waiting: 5, matchSize: 12, minSize: 4, startsAt: clock.t + 30_000 });
  clock.advance(30_000);
  gateway.tick();
  const rooms = directory.all();
  assert.equal(rooms.length, 1);
  assert.equal(rooms[0]!.state.players.size, 5);
  assert.equal(rooms[0]!.state.visibility, 'public');
  for (const id of ids) {
    assert.ok(inbox.get(id)!.some((m) => m.t === 'welcome'));
    assert.equal(lastQueued(id).position, 0);
  }
});
