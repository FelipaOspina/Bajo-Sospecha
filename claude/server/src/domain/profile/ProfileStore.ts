import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { PlayerProfile } from './types.js';

/** Dónde viven los perfiles. Hoy un JSON en disco; mañana una base de datos. */
export interface ProfileStore {
  get(id: string): PlayerProfile | undefined;
  put(profile: PlayerProfile): void;
}

export class InMemoryProfileStore implements ProfileStore {
  readonly profiles = new Map<string, PlayerProfile>();
  get(id: string) { return this.profiles.get(id); }
  put(profile: PlayerProfile) { this.profiles.set(profile.id, profile); }
}

/**
 * Mock de persistencia: todos los perfiles en un único JSON
 * ({ "version": 1, "profiles": { "<id>": PlayerProfile } }). Se lee al arrancar y se
 * reescribe entero (archivo temporal + rename) poco después de cada cambio.
 */
export class JsonFileProfileStore implements ProfileStore {
  private readonly profiles = new Map<string, PlayerProfile>();
  private timer: NodeJS.Timeout | null = null;

  constructor(private readonly path: string, private readonly debounceMs = 250) {
    try {
      const data = JSON.parse(readFileSync(path, 'utf8')) as { profiles?: Record<string, PlayerProfile> };
      for (const p of Object.values(data.profiles ?? {})) this.profiles.set(p.id, p);
    } catch {
      // Primera vez: sin archivo todavía.
    }
  }

  get(id: string) { return this.profiles.get(id); }

  put(profile: PlayerProfile) {
    this.profiles.set(profile.id, profile);   // misma referencia: dos conexiones con el mismo perfil no se pisan
    if (this.timer) return;
    this.timer = setTimeout(() => this.flush(), this.debounceMs);
  }

  /** Escribe ya (también al cerrar el servidor y en tests). */
  flush(): void {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    mkdirSync(dirname(this.path), { recursive: true });
    const tmp = `${this.path}.tmp`;
    writeFileSync(tmp, JSON.stringify({ version: 1, profiles: Object.fromEntries(this.profiles) }, null, 2));
    renameSync(tmp, this.path);
  }
}
