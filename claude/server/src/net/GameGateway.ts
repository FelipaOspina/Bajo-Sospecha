import type { ClientIntent, PlayerId, Resolution, ServerMessage } from '../../../shared/protocol/protocol.js';
import type { ProfileService } from '../domain/profile/ProfileService.js';
import type { PlayerProfile } from '../domain/profile/types.js';
import type { Result } from '../core/Result.js';
import { Matchmaker } from './Matchmaker.js';
import type { IClientTransport, Room } from './Room.js';
import { RoomDirectory } from './RoomDirectory.js';

/** Una conexión abierta (un socket). Su id es también su PlayerId dentro de las salas. */
interface Connection {
  id: PlayerId;
  send: (msg: ServerMessage) => void;
  name: string;
  profile?: PlayerProfile;
  room?: Room;
}

const MAX_NAME = 24;

/**
 * Puerta de entrada independiente del transporte (WsServer solo le pasa mensajes):
 *  - menú: hello (perfil), Executive Pass, tienda de cosméticos, ponérselos y animal preferido;
 *  - salas privadas: create_room (código de 6) y join_room;
 *  - matchmaking público: queue_match / leave_queue (grupos de MATCH_SIZE);
 *  - dentro de una sala, el resto de intenciones van a Room;
 *  - al terminar una partida, reparte XP y monedas a los perfiles.
 */
export class GameGateway implements IClientTransport {
  private readonly conns = new Map<PlayerId, Connection>();
  /** Perfil de cada jugador que ha pasado por una sala (para recompensar aunque se haya ido). */
  private readonly profileOf = new Map<PlayerId, PlayerProfile>();
  readonly matchmaker: Matchmaker<PlayerId>;
  private directory!: RoomDirectory;

  constructor(private readonly profiles?: ProfileService, matchSize = 4) {
    this.matchmaker = new Matchmaker<PlayerId>(matchSize);
  }

  attach(directory: RoomDirectory) { this.directory = directory; }

  send(playerId: PlayerId, msg: ServerMessage): void {
    this.conns.get(playerId)?.send(msg);
  }

  open(id: PlayerId, send: (msg: ServerMessage) => void): void {
    this.conns.set(id, { id, send, name: 'Jugador' });
  }

  close(id: PlayerId): void {
    const c = this.conns.get(id);
    if (!c) return;
    this.leaveQueue(c);
    if (c.room?.phase === 'lobby') this.profileOf.delete(id);
    c.room?.disconnect(id);
    this.conns.delete(id);
  }

  message(id: PlayerId, intent: ClientIntent): void {
    const c = this.conns.get(id);
    if (!c) return;
    if (typeof (intent as { name?: unknown }).name === 'string') c.name = String((intent as { name: string }).name).slice(0, MAX_NAME) || c.name;

    switch (intent.t) {
      case 'hello': return this.hello(c, intent);
      case 'join': return this.legacyJoin(c, intent.roomCode);
      case 'create_room': return this.reply(c, intent.seq, this.createRoom(c));
      case 'join_room': return this.reply(c, intent.seq, this.joinRoom(c, intent.roomCode));
      case 'queue_match': return this.reply(c, intent.seq, this.queue(c));
      case 'leave_queue': this.leaveQueue(c); return this.reply(c, intent.seq, { ok: true, value: null });
      case 'leave_room': return this.reply(c, intent.seq, this.leaveRoom(c));
      case 'claim_pass_reward': return this.profileAction(c, intent.seq, (p) => this.profiles!.claim(p, intent.level, intent.track));
      case 'buy_skin': return this.profileAction(c, intent.seq, (p) => this.profiles!.buySkin(p, intent.skinId));
      case 'buy_premium_pass': return this.profileAction(c, intent.seq, (p) => this.profiles!.buyPremium(p));
      case 'select_skin': return this.profileAction(c, intent.seq, (p) => this.profiles!.selectSkin(p, intent.skinId));
      case 'buy_cosmetic': return this.profileAction(c, intent.seq, (p) => this.profiles!.buyCosmetic(p, intent.cosmeticId));
      case 'equip_cosmetic': {
        this.profileAction(c, intent.seq, (p) => this.profiles!.equipCosmetic(p, intent.slot, intent.cosmeticId));
        if (c.profile) c.room?.setLook(c.id, c.profile.equipped as Record<string, string>);   // en el lobby se ve al momento
        return;
      }
    }
    if (c.room) c.room.handleIntent(id, intent);
    else c.send({ t: 'rejected', seq: intent.seq, reason: 'not_in_room' });
  }

  // ───── Perfil ─────

  private hello(c: Connection, intent: Extract<ClientIntent, { t: 'hello' }>): void {
    if (!this.profiles) { c.send({ t: 'ack', seq: intent.seq }); return; }
    c.profile = this.profiles.load(intent.profileId, c.name);
    c.name = c.profile.name;
    c.send({ t: 'ack', seq: intent.seq });
    this.sendProfile(c);
  }

  private profileAction(c: Connection, seq: number, action: (p: PlayerProfile) => Result<unknown>): void {
    if (!this.profiles || !c.profile) { c.send({ t: 'rejected', seq, reason: 'no_profile' }); return; }
    const r = action(c.profile);
    this.reply(c, seq, r);
    if (r.ok) this.sendProfile(c);
  }

  private sendProfile(c: Connection): void {
    if (this.profiles && c.profile) c.send({ t: 'profile', profile: this.profiles.view(c.profile) });
  }

  /** Room.onResolved: XP y monedas para cada perfil que jugó (gane o pierda). */
  rewardMatch(resolution: Resolution): void {
    if (!this.profiles) return;
    for (const p of resolution.players) {
      const profile = this.profileOf.get(p.id);
      if (!profile) continue;
      const rewards = this.profiles.grantMatch(profile, { won: p.won, objectivesCompleted: p.objectives.filter((o) => o.completed).length });
      const c = this.conns.get(p.id);
      if (c) {
        c.send({ t: 'rewards', rewards });
        this.sendProfile(c);
      }
      this.profileOf.delete(p.id);
    }
  }

  // ───── Salas ─────

  private createRoom(c: Connection): Result<null> {
    if (c.room) return { ok: false, error: 'already_in_room' };
    this.leaveQueue(c);
    try {
      this.enter(c, this.directory.create('private'));
      return { ok: true, value: null };
    } catch (e) {
      return { ok: false, error: (e as Error).message };
    }
  }

  private joinRoom(c: Connection, code: string): Result<null> {
    if (c.room) return { ok: false, error: 'already_in_room' };
    const room = this.directory.get(RoomDirectory.normalizeCode(code));
    if (!room) return { ok: false, error: 'room_not_found' };
    const error = room.joinError();
    if (error) return { ok: false, error };
    this.leaveQueue(c);
    this.enter(c, room);
    return { ok: true, value: null };
  }

  private legacyJoin(c: Connection, code: string | undefined): void {
    if (c.room) return;
    try {
      this.enter(c, this.directory.getOrCreate(RoomDirectory.normalizeCode(code)));
    } catch {
      // Sala empezada o llena: como antes, sin respuesta (el cliente antiguo no la espera).
    }
  }

  private leaveRoom(c: Connection): Result<null> {
    if (!c.room) return { ok: false, error: 'not_in_room' };
    if (c.room.phase === 'lobby') this.profileOf.delete(c.id);
    c.room.disconnect(c.id);
    c.room = undefined;
    return { ok: true, value: null };
  }

  private enter(c: Connection, room: Room): void {
    room.connect(c.id, c.name, {
      ownedSkins: c.profile?.skins, preferredSkin: c.profile?.selectedSkin,
      ...(c.profile ? { look: { ...c.profile.equipped } as Record<string, string> } : {}),
    });
    c.room = room;
    if (c.profile) this.profileOf.set(c.id, c.profile);
  }

  // ───── Matchmaking ─────

  private queue(c: Connection): Result<null> {
    if (c.room) return { ok: false, error: 'already_in_room' };
    const group = this.matchmaker.enqueue(c.id);
    if (group) {
      let room: Room;
      try {
        room = this.directory.create('public');
      } catch (e) {
        for (const id of group) this.matchmaker.enqueue(id);   // vuelven a la cola
        return { ok: false, error: (e as Error).message };
      }
      for (const id of group) {
        const member = this.conns.get(id);
        if (!member) continue;
        member.send({ t: 'queued', position: 0, waiting: 0, matchSize: this.matchmaker.matchSize });
        this.enter(member, room);
      }
    }
    this.broadcastQueue();
    return { ok: true, value: null };
  }

  private leaveQueue(c: Connection): void {
    if (!this.matchmaker.remove(c.id)) return;
    c.send({ t: 'queued', position: 0, waiting: this.matchmaker.waiting().length, matchSize: this.matchmaker.matchSize });
    this.broadcastQueue();
  }

  private broadcastQueue(): void {
    const waiting = this.matchmaker.waiting();
    waiting.forEach((id, i) =>
      this.conns.get(id)?.send({ t: 'queued', position: i + 1, waiting: waiting.length, matchSize: this.matchmaker.matchSize }));
  }

  private reply(c: Connection, seq: number, r: Result<unknown>): void {
    c.send(r.ok ? { t: 'ack', seq } : { t: 'rejected', seq, reason: String(r.error) });
  }
}
