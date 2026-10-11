import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import type { RoomSnapshot, ServerMessage } from '../../shared/protocol/protocol.js';
import { SeededRandom } from '../src/core/Random.js';
import { createRoleManager, InMemoryRoleConfigSource } from '../src/domain/roles/index.js';
import { compileScenario, type CompiledScenario } from '../src/domain/scenario/ScenarioAdapter.js';
import { Room } from '../src/net/Room.js';

const cfg = (p: string) => fileURLToPath(new URL(`../../../../${p}`, import.meta.url));

/** Monta una sala con 4 jugadores y roles fijos, ya en investigación. */
async function setupRoom(compiled: CompiledScenario, roles: Record<string, string>) {
  const { roleManager, objectives } = createRoleManager(
    new InMemoryRoleConfigSource({ [compiled.roleSet.id]: compiled.roleSet }), new SeededRandom(1));
  roleManager.useRoleSet(compiled.roleSet);
  let now = 0;
  const inbox = new Map<string, ServerMessage[]>();
  const room = new Room('T', {
    roles: roleManager, objectives, map: compiled.map, trial: compiled.trial, endings: compiled.endings,
  }, { send: (p, m) => inbox.set(p, [...(inbox.get(p) ?? []), structuredClone(m)]) }, { now: () => now, phaseDurationsMs: compiled.phaseDurationsMs });

  const ids = Object.keys(roles);
  ids.forEach((id) => room.connect(id, id.toUpperCase()));
  ids.forEach((id) => room.handleIntent(id, { t: 'ready', seq: 1, ready: true }));
  for (const [id, role] of Object.entries(roles)) roleManager.setRole(id, role);
  now += 60_000; room.tick(); // briefing → investigation
  assert.equal(room.phase, 'investigation');

  const seq = new Map(ids.map((i) => [i, 1]));
  const send = (id: string, intent: Record<string, unknown>) => {
    seq.set(id, seq.get(id)! + 1);
    room.handleIntent(id, { ...intent, seq: seq.get(id)! } as never);
    const last = inbox.get(id)!.at(-1)!;
    return last.t === 'rejected' ? last.reason : 'ok';
  };
  /** Teletransporte de test: varios pasos cortos hasta el destino. */
  const walkTo = (id: string, x: number, y: number) => {
    for (;;) {
      const p = room.state.players.get(id)!.position;
      const d = Math.hypot(x - p.x, y - p.y);
      if (d < 1) return;
      const k = Math.min(1, 50 / d);
      now += 200;
      send(id, { t: 'move', position: { x: p.x + (x - p.x) * k, y: p.y + (y - p.y) * k } });
    }
  };
  const nextPhase = () => { now += 10 * 60_000; room.tick(); };
  const advance = (ms: number) => { now += ms; room.tick(); };
  const snap = (id: string): RoomSnapshot => room['projector'].snapshotFor(id);
  return { room, inbox, send, walkTo, nextPhase, advance, snap, roleManager };
}

const nexus = async () => compileScenario(JSON.parse(await readFile(cfg('shared/config/scenarios/nexuscore_fraude.json'), 'utf8')));

test('juicio completo: exponer pruebas, votar una decisión narrativa y resolver los finales', async () => {
  const { room, send, walkTo, nextPhase, advance, snap } = await setupRoom(await nexus(), {
    ceo: 'ROLE_CEO', cto: 'ROLE_CTO', inv: 'ROLE_INVESTOR', leak: 'ROLE_LEAKER',
  });

  // El CTO saca copia de los logs (6 s) y foto de la laptop (3 s): son fijos, se lleva las copias.
  walkTo('cto', 200, 150);
  const logsId = snap('cto').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents[0]!.instanceId;
  assert.equal(send('cto', { t: 'channel_start', evidenceInstanceId: logsId, action: 'backup' }), 'ok');
  advance(6_000);
  walkTo('cto', 640, 120);
  const laptopId = snap('cto').interactables.find((i) => i.id === 'spawn_CLUE_UNLOCKED_LAPTOP')!.contents[0]!.instanceId;
  assert.equal(send('cto', { t: 'channel_start', evidenceInstanceId: laptopId, action: 'backup' }), 'ok');
  advance(3_000);
  assert.equal(snap('cto').you!.inventory.filter((e) => e.isCopy).length, 2);
  assert.equal(snap('ceo').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents.length, 1, 'el original sigue en su sitio');
  // El inversor recoge el pendrive.
  walkTo('inv', 1050, 550);
  assert.equal(send('inv', { t: 'interact', interactableId: 'spawn_CLUE_ENCRYPTED_PENDRIVE' }), 'ok');

  nextPhase();
  assert.equal(room.phase, 'discussion');
  const [logs, laptop] = snap('cto').you!.inventory.map((n) => n.instanceId);
  assert.equal(send('cto', { t: 'present_evidence', evidenceInstanceId: logs }), 'ok');
  assert.equal(send('cto', { t: 'present_evidence', evidenceInstanceId: laptop }), 'ok');
  assert.equal(send('cto', { t: 'present_evidence', evidenceInstanceId: logs }), 'already_presented');

  // La mesa es pública: el inversor (sin permiso de leer los logs) los ve completos ahí.
  const deck = snap('inv').trial.deck;
  assert.equal(deck.length, 2);
  assert.equal(deck[0]!.evidence.name, 'Logs de Auditoría en Servidor Central');
  assert.equal(snap('inv').trial.options.map((o) => o.id).join(), 'despedir_ceo,despedir_cto,despedir_filtrador,abstain');

  nextPhase();
  assert.equal(room.phase, 'voting');
  for (const p of ['cto', 'inv', 'leak']) send(p, { t: 'vote', optionId: 'despedir_ceo' });
  assert.deepEqual(snap('ceo').trial.voted.sort(), ['cto', 'inv', 'leak']);
  assert.equal(snap('ceo').trial.myVote, null, 'el voto ajeno no se ve');
  assert.equal(send('ceo', { t: 'vote', optionId: 'despedir_cto' }), 'ok');

  assert.equal(room.phase, 'results', 'todos votaron: pasa a resultados sin esperar');
  const res = snap('ceo').trial.resolution!;
  assert.equal(res.verdict.optionId, 'despedir_ceo');
  assert.deepEqual(res.verdict.tally, { despedir_ceo: 3, despedir_cto: 1 });
  assert.deepEqual(res.verdict.accused, ['ceo']);
  assert.deepEqual(res.endings.map((e) => e.id).sort(), ['cto_gana', 'inversor_gana']);
  assert.deepEqual(res.winners.sort(), ['cto', 'inv']);
  assert.equal(res.players.find((p) => p.id === 'ceo')!.roleId, 'ROLE_CEO', 'al final se revelan los roles');
});

test('acciones canalizadas: el CEO purga los logs; moverse interrumpe; solo lo ven los cercanos', async () => {
  const { room, inbox, send, walkTo, nextPhase, advance, snap } = await setupRoom(await nexus(), {
    ceo: 'ROLE_CEO', cto: 'ROLE_CTO', inv: 'ROLE_INVESTOR', leak: 'ROLE_LEAKER',
  });
  walkTo('ceo', 200, 150);
  walkTo('cto', 250, 200);           // cerca: verá la barra
  walkTo('inv', 1050, 550);          // lejos: no la verá
  const logs = snap('ceo').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents[0]!;
  assert.deepEqual(logs.actions?.map((a) => a.kind), ['delete'], 'el CEO solo ve su acción');
  assert.equal(send('cto', { t: 'channel_start', evidenceInstanceId: logs.instanceId, action: 'delete' }), 'action_not_allowed');

  assert.equal(send('ceo', { t: 'channel_start', evidenceInstanceId: logs.instanceId, action: 'delete' }), 'ok');
  assert.equal(snap('cto').players.find((p) => p.id === 'ceo')!.channel?.label, 'Purgar partición /var/log/audit.log');
  assert.equal(snap('cto').players.find((p) => p.id === 'ceo')!.channel?.durationMs, 10_000);
  assert.equal(snap('inv').players.find((p) => p.id === 'ceo')!.channel, undefined, 'lejos no se ve');
  assert.ok(!JSON.stringify(inbox.get('inv')).includes('channel_started'));

  // Moverse interrumpe.
  advance(4_000);
  walkTo('ceo', 230, 150);
  const finished = inbox.get('cto')!.filter((m) => m.t === 'event' && m.event.e === 'channel_finished').at(-1);
  assert.ok(finished && finished.t === 'event' && finished.event.e === 'channel_finished' && !finished.event.ok && finished.event.reason === 'moved');
  assert.equal(snap('ceo').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents.length, 1);

  // Quieto 10 s: los logs desaparecen para todos.
  walkTo('ceo', 200, 150);
  send('ceo', { t: 'channel_start', evidenceInstanceId: logs.instanceId, action: 'delete' });
  advance(10_000);
  assert.equal(snap('inv').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents.length, 0);

  // Contrato a la trituradora (5 s) y empate en el voto: gana el CEO.
  walkTo('ceo', 200, 550);
  const contract = snap('ceo').interactables.find((i) => i.id === 'spawn_CLUE_TORN_CONTRACT')!.contents[0]!.instanceId;
  send('ceo', { t: 'channel_start', evidenceInstanceId: contract, action: 'delete' });
  advance(5_000);
  nextPhase(); nextPhase();
  send('ceo', { t: 'vote', optionId: 'despedir_cto' });
  send('cto', { t: 'vote', optionId: 'despedir_ceo' });
  nextPhase();
  const res = snap('cto').trial.resolution!;
  assert.equal(res.verdict.optionId, null);
  assert.deepEqual(res.endings.map((e) => e.id), ['ceo_gana']);
  assert.equal(room.phase, 'results');
});

test('privacidad: nadie recibe el rol ni los objetivos secretos de otro jugador antes del final', async () => {
  const compiled = await nexus();
  const roles = { ceo: 'ROLE_CEO', cto: 'ROLE_CTO', inv: 'ROLE_INVESTOR', leak: 'ROLE_LEAKER' };
  const { room, inbox, send, walkTo, nextPhase } = await setupRoom(compiled, roles);
  walkTo('inv', 1050, 550);
  send('inv', { t: 'interact', interactableId: 'spawn_CLUE_ENCRYPTED_PENDRIVE' });
  nextPhase(); // discusión

  const secretsOf = (roleId: string) => {
    const r = compiled.roleSet.roles.find((x) => x.id === roleId)!;
    return [r.description, ...r.objectives.map((o) => o.description)];
  };
  for (const [viewer, myRole] of Object.entries(roles)) {
    const wire = JSON.stringify(inbox.get(viewer));
    for (const [other, role] of Object.entries(roles)) {
      if (other === viewer) continue;
      for (const secret of secretsOf(role)) {
        if (secretsOf(myRole).includes(secret)) continue;
        assert.ok(!wire.includes(secret), `${viewer} recibió un secreto de ${other}: "${secret.slice(0, 40)}..."`);
      }
    }
    // Ningún snapshot ni delta asocia a otro jugador con un rol.
    const order = [...room.state.players.keys()];
    for (const m of inbox.get(viewer)!) {
      if (m.t === 'welcome' || m.t === 'snapshot') {
        for (const p of m.snapshot.players) assert.ok(p.roleId === undefined || p.id === viewer, `${viewer} vio el rol de ${p.id}`);
      }
      if (m.t === 'delta') {
        for (const op of m.ops) {
          if (op.path[0] !== 'players' || op.op !== 'set') continue;
          const touched = op.path.length >= 3 ? [order[op.path[1] as number]] : [];
          const value = JSON.stringify(op.value ?? '');
          if (op.path.includes('roleId')) assert.equal(touched[0], viewer, `${viewer} recibió el rol de ${touched[0]}`);
          if (op.path.length <= 2 && value.includes('roleId')) {
            const players = (Array.isArray(op.value) ? op.value : [op.value]) as { id: string; roleId?: string }[];
            for (const p of players) assert.ok(p.roleId === undefined || p.id === viewer, `${viewer} vio el rol de ${p.id}`);
          }
        }
      }
    }
  }
});

test('el caso original en formato libre se carga sin tocar el archivo', async () => {
  const raw = JSON.parse(await readFile(cfg('scenarios/caso_fraude_tech_startup.json'), 'utf8'));
  const compiled = compileScenario(raw);
  assert.equal(compiled.roleSet.id, 'case_002_tech_fraud');
  assert.equal(compiled.roleSet.maxPlayers, 4, 'solo hay 4 roles');
  assert.ok(compiled.warnings.some((w) => w.includes('player_count.max')));
  const logs = compiled.map.evidence.find((e) => e.id === 'CLUE_SERVER_LOGS')!;
  assert.equal(logs.pocketable, false);
  assert.equal(logs.medium, 'digital/critica', 'el aspecto (marco del visor) sale del type del caso');
  assert.ok(logs.tags.includes('beneficia:ROLE_CTO') && logs.tags.includes('perjudica:ROLE_CEO'));
  assert.deepEqual(compiled.map.interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')!.position, { x: 200, y: 150 });
  const type = (id: string) => compiled.scenario.evidence_spawns.find((e) => e.id === id)!.type;
  assert.deepEqual(['CLUE_SERVER_LOGS', 'CLUE_UNLOCKED_LAPTOP', 'CLUE_TORN_CONTRACT', 'CLUE_ENCRYPTED_PENDRIVE'].map(type), ['text', 'photo', 'item', 'item']);
  assert.equal(compiled.trial?.max_presented_per_player, 2, 'leído de las reglas de la confrontación');
  assert.equal(compiled.phaseDurationsMs.investigation, 180_000);
  assert.deepEqual(compiled.endings.map((e) => e.id), ['culpable_descubierto', 'culpable_impune']);
  assert.deepEqual(logs.actions?.map((a) => [a.kind, a.seconds]), [['delete', 10], ['backup', 6]], 'deletion/backup → acciones canalizadas');
  assert.deepEqual(compiled.trial?.options?.map((o) => o.accuses_role), ['ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER'], 'una acusación por personaje');

  // Y se puede jugar: el veredicto contra el CEO hace ganar a los inocentes.
  const { send, nextPhase, snap } = await setupRoom(compiled, { a: 'ROLE_CEO', b: 'ROLE_CTO', c: 'ROLE_INVESTOR', d: 'ROLE_LEAKER' });
  const logsView = snap('a').interactables.find((i) => i.id === 'spawn_CLUE_SERVER_LOGS')?.contents[0];
  assert.ok(logsView);
  assert.equal(logsView.visibility, 'partial', 'al CEO no le beneficia: vista parcial');
  assert.equal(logsView.medium, 'digital/critica', 'pero ve que es una terminal');
  assert.equal(logsView.name, undefined);
  nextPhase(); nextPhase();
  for (const p of ['a', 'b', 'c', 'd']) send(p, { t: 'vote', optionId: p === 'a' ? 'abstain' : 'acusar_role_ceo' });
  const res = snap('b').trial.resolution!;
  assert.deepEqual(res.endings.map((e) => e.id), ['culpable_descubierto']);
  assert.deepEqual(res.winners.sort(), ['b', 'c', 'd']);
});

test('lo que se expone en la mesa llega a los clientes por delta', async () => {
  const raw = JSON.parse(await readFile(cfg('scenarios/caso_fraude_tech_startup.json'), 'utf8'));
  const { inbox, send, walkTo, nextPhase, advance, room } = await setupRoom(compileScenario(raw), { a: 'ROLE_CEO', b: 'ROLE_CTO', c: 'ROLE_INVESTOR', d: 'ROLE_LEAKER' });
  room.tick();
  walkTo('b', 200, 150);
  const logs = room['projector'].snapshotFor('b').interactables.find((i: { id: string }) => i.id === 'spawn_CLUE_SERVER_LOGS')!.contents[0]!.instanceId;
  assert.equal(send('b', { t: 'channel_start', evidenceInstanceId: logs, action: 'backup' }), 'ok');
  advance(7_000);
  nextPhase(); // → debate
  const copy = room['projector'].snapshotFor('b').you!.inventory[0]!.instanceId;
  assert.equal(send('b', { t: 'present_evidence', evidenceInstanceId: copy }), 'ok');
  room.tick();

  // Reconstruye el estado de 'c' como lo hace el cliente: snapshot + deltas.
  let state: Record<string, unknown> = {};
  for (const m of inbox.get('c')!) {
    if (m.t === 'welcome' || m.t === 'snapshot') state = structuredClone(m.snapshot) as never;
    if (m.t === 'delta') for (const op of m.ops) applyOp(state, op.path, op.op === 'set' ? op.value : undefined);
  }
  const deck = (state.trial as { deck: { presentedBy: string }[] }).deck;
  assert.equal(deck.length, 1, 'el delta incluye la carta nueva');
  assert.equal(deck[0]!.presentedBy, 'b');
});

function applyOp(root: Record<string, unknown>, path: (string | number)[], value: unknown) {
  let node = root as Record<string | number, unknown>;
  for (const k of path.slice(0, -1)) node = node[k] as Record<string | number, unknown>;
  const last = path.at(-1)!;
  if (value === undefined) delete node[last]; else node[last] = structuredClone(value);
}
