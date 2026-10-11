import { mathRandom, type IRandom } from '../core/Random.js';
import type { Room } from './Room.js';
import type { RoomVisibility } from './RoomState.js';

export type RoomFactory = (code: string, visibility: RoomVisibility) => Room;

/** Sin 0/O ni 1/I/L: se dictan sin confusión. */
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 6;

/**
 * Salas activas por código. Cada sala tiene su propio RoleManager, sistema de
 * pruebas y juicio (creados por la fábrica), así que las partidas no se mezclan.
 */
export class RoomDirectory {
  private readonly rooms = new Map<string, Room>();

  constructor(private readonly factory: RoomFactory, private readonly maxRooms = 100, private readonly rng: IRandom = mathRandom) {}

  /** Normaliza "abcd" → "ABCD"; vacío = sala pública por defecto. */
  static normalizeCode(code: string | undefined): string {
    const c = String(code ?? '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8);
    return c || 'PUBLICA';
  }

  /** Sala nueva con un código de 6 caracteres que no esté en uso. */
  create(visibility: RoomVisibility): Room {
    this.ensureCapacity();
    let code = '';
    do {
      code = Array.from({ length: CODE_LENGTH }, () => CODE_ALPHABET[Math.floor(this.rng.next() * CODE_ALPHABET.length)]).join('');
    } while (this.rooms.has(code));
    const room = this.factory(code, visibility);
    this.rooms.set(code, room);
    return room;
  }

  /** Compatibilidad con el intent 'join' (el código elegido por el cliente crea la sala si no existe). */
  getOrCreate(code: string): Room {
    let room = this.rooms.get(code);
    if (!room) {
      this.ensureCapacity();
      room = this.factory(code, 'private');
      this.rooms.set(code, room);
    }
    return room;
  }

  get(code: string) { return this.rooms.get(code); }
  all() { return [...this.rooms.values()]; }

  /** Avanza todas las salas y cierra las vacías. */
  tick(): void {
    for (const [code, room] of this.rooms) {
      if (room.isEmpty()) { this.rooms.delete(code); continue; }
      room.tick();
    }
  }

  private ensureCapacity(): void {
    if (this.rooms.size >= this.maxRooms) throw new Error('server_full');
  }
}
