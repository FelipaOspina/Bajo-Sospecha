import type { EvidenceDefinition } from './types.js';

export interface IEvidenceCatalog {
  get(definitionId: string): EvidenceDefinition | undefined;
  all(): readonly EvidenceDefinition[];
}

export class EvidenceCatalog implements IEvidenceCatalog {
  private readonly byId: Map<string, EvidenceDefinition>;

  constructor(definitions: EvidenceDefinition[]) {
    this.byId = new Map();
    for (const d of definitions) {
      if (this.byId.has(d.id)) throw new Error(`Prueba duplicada en catálogo: ${d.id}`);
      if (!Array.isArray(d.tags) || !(d.weight >= 0)) throw new Error(`Prueba mal definida: ${d.id}`);
      this.byId.set(d.id, Object.freeze({ ...d, tags: [...d.tags] }));
    }
    for (const d of definitions) {
      for (const req of [d.access?.view, d.access?.collect]) {
        for (const item of req?.items ?? []) {
          if (!this.byId.has(item)) throw new Error(`Prueba ${d.id}: el ítem requerido "${item}" no existe`);
        }
      }
    }
  }

  get(id: string) { return this.byId.get(id); }
  all() { return [...this.byId.values()]; }
}
