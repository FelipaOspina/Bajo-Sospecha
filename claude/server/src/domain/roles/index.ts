import type { IRandom } from '../../core/Random.js';
import { WeightedRoleAssignment } from './assignment/RoleAssignmentStrategy.js';
import { createDefaultModifierRegistry } from './modifiers/ModifierRegistry.js';
import { createDefaultObjectiveRegistry } from './objectives/ObjectiveRegistry.js';
import type { IRoleConfigSource } from './RoleConfigSource.js';
import { RoleConfigValidator } from './RoleConfigValidator.js';
import { RoleManager } from './RoleManager.js';
import { RestrictiveVisibilityPolicy } from './visibility/ClueVisibilityPolicy.js';

export * from './types.js';
export * from './RoleManager.js';
export * from './RoleConfigSource.js';
export * from './RoleConfigValidator.js';
export * from './modifiers/ModifierRegistry.js';
export * from './objectives/ObjectiveRegistry.js';
export * from './assignment/RoleAssignmentStrategy.js';
export * from './visibility/ClueVisibilityPolicy.js';

/** Composition root del módulo de roles con las implementaciones por defecto. */
export function createRoleManager(source: IRoleConfigSource, rng: IRandom) {
  const modifiers = createDefaultModifierRegistry();
  const objectives = createDefaultObjectiveRegistry();
  const roleManager = new RoleManager({
    source,
    modifiers,
    validator: new RoleConfigValidator(modifiers, objectives),
    assignment: new WeightedRoleAssignment(rng),
    visibility: new RestrictiveVisibilityPolicy(),
  });
  return { roleManager, objectives };
}
