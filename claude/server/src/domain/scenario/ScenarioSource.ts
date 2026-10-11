import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { compileScenario, type CompiledScenario } from './ScenarioAdapter.js';

export interface IScenarioSource {
  load(scenarioId: string): Promise<unknown>;
}

export class FileScenarioSource implements IScenarioSource {
  constructor(private readonly directory: string) {}
  async load(id: string) {
    if (!/^[a-z0-9_-]+$/i.test(id)) throw new Error(`Id de escenario inválido: ${id}`);
    return JSON.parse(await readFile(join(this.directory, `${id}.json`), 'utf8'));
  }
}

export async function loadScenario(source: IScenarioSource, id: string): Promise<CompiledScenario> {
  return compileScenario(await source.load(id));
}
