import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { ClientIntent, GameEvent, PlayerId, ServerMessage } from '../../shared/protocol/protocol.js';
import { SeededRandom } from '../src/core/Random.js';
import { createRoleManager, InMemoryRoleConfigSource } from '../src/domain/roles/index.js';
import { compileScenario, type CompiledScenario } from '../src/domain/scenario/ScenarioAdapter.js';
import type { LineOfSight } from '../src/domain/world/LineOfSight.js';
import { Room } from '../src/net/Room.js';

/** Raíz de dev/ (el test compilado vive en dist/server/test). */
export const DEV = fileURLToPath(new URL('../../../../', import.meta.url));
export const NATIVE_PATH = `${DEV}shared/config/scenarios/nexuscore_fraude.json`;
export const LEGACY_PATH = `${DEV}scenarios/caso_fraude_tech_startup.json`;

export const loadNative = (): CompiledScenario => compileScenario(JSON.parse(readFileSync(NATIVE_PATH, 'utf8')));
export const loadLegacy = (): CompiledScenario => compileScenario(JSON.parse(readFileSync(LEGACY_PATH, 'utf8')));

/** Reloj manual. */
export class Clock {
  t = 1_000_000;
  now = () => this.t;
  advance(ms: number) { this.t += ms; }
}

/** Transporte que guarda todo lo enviado. */
export class Recorder {
  readonly sent: { to: PlayerId; msg: ServerMessage }[] = [];
  send(to: PlayerId, msg: ServerMessage) { this.sent.push({ to, msg }); }
  events(to: PlayerId, e?: GameEvent['e']): GameEvent[] {
    return this.sent.filter((s) => s.to === to && s.msg.t === 'event')
      .map((s) => (s.msg as Extract<ServerMessage, { t: 'event' }>).event)
      .filter((ev) => !e || ev.e === e);
  }
  rejections(to: PlayerId): string[] {
    return this.sent.filter((s) => s.to === to && s.msg.t === 'rejected').map((s) => (s.msg as { reason: string }).reason);
  }
  lastRejection(to: PlayerId): string | undefined { return this.rejections(to).at(-1); }
  clear() { this.sent.length = 0; }
}

export interface Game {
  room: Room;
  clock: Clock;
  out: Recorder;
  /** Envía una intención con seq creciente; devuelve el motivo del rechazo o null si se aceptó. */
  act(player: PlayerId, intent: Record<string, unknown> & { t: ClientIntent['t'] }): string | null;
  place(player: PlayerId, x: number, y: number): void;
  /** Pasa el tiempo y hace tick. */
  wait(ms: number): void;
}

/**
 * Sala con el caso nativo, jugadores con los roles indicados (en orden) y ya en la investigación.
 * Con skipGrace salta los 60 s iniciales en los que no se puede silenciar.
 */
export function startGame(roles: string[], opts: { lineOfSight?: LineOfSight; skipGrace?: boolean; scenario?: CompiledScenario } = {}): Game {
  const compiled = opts.scenario ?? loadNative();
  const clock = new Clock();
  const out = new Recorder();
  const { roleManager, objectives } = createRoleManager(new InMemoryRoleConfigSource({ [compiled.roleSet.id]: compiled.roleSet }), new SeededRandom(7));
  roleManager.useRoleSet(structuredClone(compiled.roleSet));
  const room = new Room('TEST01', {
    roles: roleManager, objectives, map: structuredClone(compiled.map), trial: compiled.trial, endings: compiled.endings,
    lineOfSight: opts.lineOfSight, emergency: compiled.emergency, ghostTaskPoints: compiled.ghostTaskPoints, rng: new SeededRandom(3),
  }, out, { phaseDurationsMs: compiled.phaseDurationsMs, now: clock.now });
  const seqs = new Map<PlayerId, number>();
  const act: Game['act'] = (player, intent) => {
    const seq = (seqs.get(player) ?? 0) + 1;
    seqs.set(player, seq);
    const before = out.sent.length;
    room.handleIntent(player, { ...intent, seq } as unknown as ClientIntent);
    const reply = out.sent.slice(before).find((s) => s.to === player && (s.msg.t === 'ack' || s.msg.t === 'rejected'));
    return reply?.msg.t === 'rejected' ? (reply.msg as { reason: string }).reason : null;
  };
  const ids = roles.map((_, i) => `p${i}`);
  ids.forEach((id) => room.connect(id, id.toUpperCase()));
  ids.forEach((id) => act(id, { t: 'ready', ready: true }));
  roles.forEach((r, i) => roleManager.setRole(ids[i]!, r));
  const game: Game = {
    room, clock, out, act,
    place: (p, x, y) => { const rec = room.state.players.get(p)!; rec.position = { x, y }; rec.lastSeenPosition = rec.ghost ? rec.lastSeenPosition : { x, y }; },
    wait: (ms) => { clock.advance(ms); room.tick(); },
  };
  game.wait(10_001);   // briefing → investigación
  if (room.phase !== 'investigation') throw new Error(`fase inesperada ${room.phase}`);
  if (opts.skipGrace) game.wait(60_000);
  return game;
}

/** Mete una pista concreta en el inventario de un jugador (la recoge de su sitio). */
export function give(g: Game, player: PlayerId, clueId: string): void {
  const spot = g.room.evidence.listInteractables().find((i) => i.id === `spawn_${clueId}`)!;
  const prev = g.room.state.players.get(player)!.position;
  g.place(player, spot.position.x, spot.position.y);
  const r = g.room.evidence.interact(player, spot.id);
  if (!r.ok) throw new Error(`no se pudo dar ${clueId} a ${player}: ${r.error}`);
  g.place(player, prev.x, prev.y);
}
