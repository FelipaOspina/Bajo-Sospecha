import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';
import type { ClientIntent, RoomSnapshot, ServerMessage } from '../../shared/protocol/protocol.js';
import { SeededRandom } from '../src/core/Random.js';
import type { EvidenceMapConfig } from '../src/domain/evidence/index.js';
import { ProfileService } from '../src/domain/profile/ProfileService.js';
import { InMemoryProfileStore } from '../src/domain/profile/ProfileStore.js';
import type { ProgressionConfig } from '../src/domain/profile/types.js';
import { createRoleManager, InMemoryRoleConfigSource, type RoleSetConfig } from '../src/domain/roles/index.js';
import { SkinCatalog, type SkinConfig } from '../src/domain/skins/SkinCatalog.js';
import { CosmeticCatalog, type CosmeticConfig } from '../src/domain/cosmetics/CosmeticCatalog.js';
import { GameGateway } from '../src/net/GameGateway.js';
import { Matchmaker } from '../src/net/Matchmaker.js';
import { Room } from '../src/net/Room.js';
import { CODE_ALPHABET, RoomDirectory } from '../src/net/RoomDirectory.js';
import type { RoomVisibility } from '../src/net/RoomState.js';
import { WsServer } from '../src/net/WsServer.js';

const cfgUrl = (p: string) => fileURLToPath(new URL(`../../../../shared/config/${p}`, import.meta.url));
const json = async <T>(p: string) => JSON.parse(await readFile(cfgUrl(p), 'utf8')) as T;

/** Servidor completo en memoria (sin sockets): gateway + salas + perfiles. */
async function world() {
  const roles = await json<RoleSetConfig>('roles/mansion_clasica.json');
  const map = await json<EvidenceMapConfig>('evidence/mansion_clasica.json');
  const skins = await json<SkinConfig>('skins/skins.json');
  const catalog = new SkinCatalog(skins, new SeededRandom(2));
  const store = new InMemoryProfileStore();
  const cosmetics = new CosmeticCatalog(await json<CosmeticConfig>('cosmetics/cosmetics.json'));
  const profiles = new ProfileService(await json<ProgressionConfig>('progression/progression.json'), store, catalog, undefined, undefined, cosmetics);
  let now = 0;
  const gateway = new GameGateway(profiles, 4);
  const directory = new RoomDirectory((code: string, visibility: RoomVisibility) => {
    const { roleManager, objectives } = createRoleManager(new InMemoryRoleConfigSource({ [roles.id]: roles }), new SeededRandom(4));
    roleManager.useRoleSet(structuredClone(roles));
    return new Room(code, { roles: roleManager, objectives, map: structuredClone(map), skins: catalog }, gateway, {
      now: () => now, visibility, autoStartDelayMs: 10_000,
      phaseDurationsMs: { briefing: 1000, investigation: 1000, discussion: 1000, voting: 1000 },
      onResolved: (r) => gateway.rewardMatch(r),
    });
  }, 100, new SeededRandom(9));
  gateway.attach(directory);

  const inbox = new Map<string, ServerMessage[]>();
  const seq = new Map<string, number>();
  const open = (id: string) => { inbox.set(id, []); seq.set(id, 0); gateway.open(id, (m) => inbox.get(id)!.push(structuredClone(m))); };
  const send = (id: string, intent: Record<string, unknown>) => {
    seq.set(id, seq.get(id)! + 1);
    gateway.message(id, { ...intent, seq: seq.get(id)! } as ClientIntent);
    const reply = inbox.get(id)!.filter((m) => m.t === 'ack' || m.t === 'rejected').at(-1)!;
    return reply.t === 'rejected' ? reply.reason : 'ok';
  };
  const last = <T extends ServerMessage['t']>(id: string, t: T) => inbox.get(id)!.filter((m) => m.t === t).at(-1) as Extract<ServerMessage, { t: T }> | undefined;
  const lobbyOf = (id: string): RoomSnapshot => last(id, 'welcome')!.snapshot;
  const advance = (ms: number) => { now += ms; directory.tick(); };
  return { gateway, directory, store, open, send, last, lobbyOf, advance, inbox };
}

test('salas privadas: código de 6 caracteres, unirse por código y errores claros', async () => {
  const w = await world();
  for (const id of ['a', 'b', 'c', 'd', 'e']) { w.open(id); w.send(id, { t: 'hello', name: id.toUpperCase(), protocol: 1 }); }
  assert.equal(w.send('a', { t: 'create_room' }), 'ok');
  const lobby = w.lobbyOf('a').lobby;
  assert.match(lobby.code, new RegExp(`^[${CODE_ALPHABET}]{6}$`));
  assert.equal(lobby.visibility, 'private');
  assert.equal(lobby.hostId, 'a');
  assert.equal(lobby.startsAt, null, 'las privadas no arrancan solas');

  assert.equal(w.send('b', { t: 'join_room', roomCode: 'ZZZZZZ' }), 'room_not_found');
  assert.equal(w.send('b', { t: 'join_room', roomCode: lobby.code.toLowerCase() }), 'ok', 'el código no distingue mayúsculas');
  assert.equal(w.lobbyOf('b').lobby.code, lobby.code);
  assert.equal(w.send('b', { t: 'create_room' }), 'already_in_room');
  for (const id of ['c', 'd']) assert.equal(w.send(id, { t: 'join_room', roomCode: lobby.code }), 'ok');
  // mansion_clasica admite hasta maxPlayers; llenarla:
  const room = w.directory.get(lobby.code)!;
  const max = w.lobbyOf('a').lobby.maxPlayers;
  for (let i = 4; i < max; i++) { const id = `x${i}`; w.open(id); w.send(id, { t: 'join_room', roomCode: lobby.code }); }
  assert.equal(w.send('e', { t: 'join_room', roomCode: lobby.code }), 'room_full');

  // Estado del lobby en tiempo real: skins distintas de las desbloqueadas y "listo".
  const snap = room['projector'].snapshotFor('a') as RoomSnapshot;
  const profileSkins = (id: string) => w.last(id, 'profile')!.profile as { skins: string[] };
  assert.ok(snap.players.filter((p) => ['a', 'b', 'c', 'd'].includes(p.id)).every((p) => profileSkins(p.id).skins.includes(p.skinId!)));
  const taken = snap.players.find((p) => p.id === 'a')!.skinId!;
  assert.equal(w.send('b', { t: 'choose_skin', skinId: taken }), 'skin_taken', 'cada animal, uno por sala');

  // Cosméticos: lo que se pone en el menú lo ven los demás en el lobby al momento.
  assert.equal(w.send('b', { t: 'equip_cosmetic', slot: 'outfit', cosmeticId: 'sudadera_gris' }), 'ok');
  assert.equal(w.send('b', { t: 'equip_cosmetic', slot: 'hat', cosmeticId: 'gorra_azul' }), 'cosmetic_locked');
  const look = (room['projector'].snapshotFor('c') as RoomSnapshot).players.find((p) => p.id === 'b')!.look;
  assert.deepEqual(look, { outfit: 'sudadera_gris' });

  // Chat de sala.
  assert.equal(w.send('a', { t: 'chat', text: '  ¡Vamos   equipo!  ' }), 'ok');
  const chat = w.inbox.get('c')!.find((m) => m.t === 'event' && m.event.e === 'chat');
  assert.ok(chat && chat.t === 'event' && chat.event.e === 'chat' && chat.event.text === '¡Vamos equipo!' && chat.event.name === 'A');

  // Si el host se va, la corona pasa al siguiente.
  w.gateway.close('a');
  assert.equal((room['projector'].snapshotFor('b') as RoomSnapshot).lobby.hostId, 'b');
});

test('cola pública: agrupa de 4 en 4, cuenta atrás y arranca sola', async () => {
  const w = await world();
  const ids = ['q1', 'q2', 'q3', 'q4', 'q5'];
  for (const id of ids) { w.open(id); w.send(id, { t: 'hello', name: id, protocol: 1 }); }
  for (const id of ids.slice(0, 3)) assert.equal(w.send(id, { t: 'queue_match' }), 'ok');
  assert.deepEqual(w.last('q3', 'queued'), { t: 'queued', position: 3, waiting: 3, matchSize: 4 });
  assert.equal(w.send('q2', { t: 'leave_queue' }), 'ok');
  assert.deepEqual(w.last('q3', 'queued'), { t: 'queued', position: 2, waiting: 2, matchSize: 4 });
  for (const id of ['q2', 'q4', 'q5']) w.send(id, { t: 'queue_match' });

  const matched = ['q1', 'q3', 'q2', 'q4'];
  const code = w.lobbyOf('q1').lobby.code;
  assert.ok(matched.every((id) => w.last(id, 'welcome')?.roomCode === code), 'los 4 primeros, a la misma sala');
  assert.equal(w.last('q5', 'welcome'), undefined);
  assert.deepEqual(w.last('q5', 'queued'), { t: 'queued', position: 1, waiting: 1, matchSize: 4 });
  const room = w.directory.get(code)!;
  const lobby = (room['projector'].snapshotFor('q1') as RoomSnapshot).lobby;
  assert.equal(lobby.visibility, 'public');
  assert.equal(lobby.startsAt, 10_000);
  assert.equal(w.send('q5', { t: 'join_room', roomCode: code }), 'ok', 'una pública con hueco admite código (mansion_clasica tiene más de 4 plazas)');

  w.advance(9_999);
  assert.equal(room.phase, 'lobby');
  w.advance(1);
  assert.equal(room.phase, 'briefing', 'arranca sola al terminar la cuenta atrás');
});

test('al terminar la partida, cada perfil recibe XP, monedas y su pase sube', async () => {
  const w = await world();
  const ids = ['r1', 'r2', 'r3', 'r4'];
  for (const id of ids) { w.open(id); w.send(id, { t: 'hello', name: id, protocol: 1 }); w.send(id, { t: 'queue_match' }); }
  const xpBefore = (w.last('r1', 'profile')!.profile as { xp: number }).xp;
  for (let i = 0; i < 6; i++) w.advance(10_000);   // cuenta atrás + fases
  const rewards = w.last('r1', 'rewards');
  assert.ok(rewards && rewards.rewards.xp > 0 && rewards.rewards.coins > 0);
  const after = w.last('r1', 'profile')!.profile as { xp: number; stats: { played: number } };
  assert.equal(after.xp, xpBefore + rewards.rewards.xp);
  assert.equal(after.stats.played, 1);
  assert.equal(w.send('r1', { t: 'leave_room' }), 'ok', 'vuelve al menú sin cerrar la conexión');
  assert.equal(w.send('r1', { t: 'queue_match' }), 'ok', 'y puede buscar otra partida');
});

test('matchmaker: orden de llegada y grupos exactos', () => {
  const m = new Matchmaker<string>(3);
  assert.equal(m.enqueue('a'), null);
  assert.equal(m.enqueue('a'), null, 'sin duplicados');
  assert.equal(m.enqueue('b'), null);
  assert.equal(m.position('b'), 2);
  assert.deepEqual(m.enqueue('c'), ['a', 'b', 'c']);
  assert.equal(m.waiting().length, 0);
});

test('WebSocket: hello, crear sala y unirse por código con clientes reales', async () => {
  const w = await world();
  const server = new WsServer(0, w.gateway);
  const wss = server.listen();
  const port = (wss.address() as { port: number }).port;
  const client = async () => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const msgs: ServerMessage[] = [];
    ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
    await new Promise((r) => ws.once('open', r));
    let s = 0;
    const until = async (pred: (m: ServerMessage) => boolean) => {
      for (let i = 0; i < 200; i++) { const m = msgs.find(pred); if (m) return m; await new Promise((r) => setTimeout(r, 5)); }
      throw new Error('sin respuesta');
    };
    return { ws, msgs, until, send: (o: Record<string, unknown>) => ws.send(JSON.stringify({ ...o, seq: ++s })) };
  };
  const a = await client();
  const b = await client();
  a.send({ t: 'hello', name: 'Ana', protocol: 1, profileId: 'perfil-de-ana-123' });
  const profile = await a.until((m) => m.t === 'profile');
  assert.equal((profile as { profile: { id: string } }).profile.id, 'perfil-de-ana-123');
  a.send({ t: 'create_room' });
  const welcome = (await a.until((m) => m.t === 'welcome')) as Extract<ServerMessage, { t: 'welcome' }>;
  b.send({ t: 'join_room', roomCode: welcome.roomCode, name: 'Beto', protocol: 1 });
  const joined = (await b.until((m) => m.t === 'welcome')) as Extract<ServerMessage, { t: 'welcome' }>;
  assert.equal(joined.snapshot.players.length, 2);
  a.ws.close(); b.ws.close();
  await server.close();
});
