import type { IEventSink } from '../../core/EventBus.js';
import type { IRoleQuery } from '../roles/types.js';
import { RequirementAccessPolicy } from './EvidenceAccessPolicy.js';
import { EvidenceCatalog } from './EvidenceCatalog.js';
import { EvidenceSystem } from './EvidenceSystem.js';
import { InMemoryInventoryStore } from './Inventory.js';
import { createDefaultInteractableFactories, InteractableRegistry } from './interactables/InteractableRegistry.js';
import { createDefaultEvidenceRules } from './rules/EvidenceRules.js';
import type { EvidenceEvents, EvidenceMapConfig, IWorldQuery } from './types.js';

export * from './types.js';
export * from './EvidenceSystem.js';
export * from './EvidenceCatalog.js';
export * from './EvidenceAccessPolicy.js';
export * from './ChannelSystem.js';
export * from './Inventory.js';
export * from './interactables/Interactable.js';
export * from './interactables/EvidenceSpot.js';
export * from './interactables/EvidenceContainer.js';
export * from './interactables/InteractableRegistry.js';
export * from './rules/EvidenceRules.js';

/** Composition root del módulo de pruebas con las implementaciones por defecto. */
export function createEvidenceSystem(
  map: EvidenceMapConfig,
  roles: IRoleQuery,
  world: IWorldQuery,
  events: IEventSink<EvidenceEvents>,
) {
  const access = new RequirementAccessPolicy();
  const system = new EvidenceSystem({
    catalog: new EvidenceCatalog(map.evidence),
    interactables: new InteractableRegistry(),
    factories: createDefaultInteractableFactories(),
    inventories: new InMemoryInventoryStore(),
    rules: createDefaultEvidenceRules(access),
    access,
    roles,
    world,
    events,
  });
  system.loadMap(map);
  return system;
}
