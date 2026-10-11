import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { RoleSetConfig } from './types.js';

/** Abstracción de origen de configuración: disco, HTTP, base de datos, tests... */
export interface IRoleConfigSource {
  list(): Promise<string[]>;
  load(roleSetId: string): Promise<unknown>;
}

/** Lee shared/config/roles/<id>.json */
export class FileRoleConfigSource implements IRoleConfigSource {
  constructor(private readonly directory: string) {}

  async list(): Promise<string[]> {
    const files = await readdir(this.directory);
    return files.filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5));
  }

  async load(roleSetId: string): Promise<unknown> {
    if (!/^[a-z0-9_-]+$/i.test(roleSetId)) throw new Error(`Id de set de roles inválido: ${roleSetId}`);
    const raw = await readFile(join(this.directory, `${roleSetId}.json`), 'utf8');
    return JSON.parse(raw);
  }
}

/** Origen en memoria, útil para tests o para configs que llegan por red. */
export class InMemoryRoleConfigSource implements IRoleConfigSource {
  constructor(private readonly sets: Record<string, RoleSetConfig>) {}
  async list() { return Object.keys(this.sets); }
  async load(id: string) {
    const set = this.sets[id];
    if (!set) throw new Error(`Set de roles no encontrado: ${id}`);
    return structuredClone(set);
  }
}
