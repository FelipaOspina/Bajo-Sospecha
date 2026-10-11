import type { IEventSink } from '../../core/EventBus.js';
import { fail, ok, type Result } from '../../core/Result.js';
import type { IRoleQuery, VisibilityLevel } from '../roles/types.js';
import { RequirementAccessPolicy, type AccessAction, type AccessCheck, type AccessSubject, type IEvidenceAccessPolicy } from './EvidenceAccessPolicy.js';
import type { IEvidenceCatalog } from './EvidenceCatalog.js';
import type { IInventoryStore } from './Inventory.js';
import {
  isDropTarget,
  isEvidenceSource,
  type IEvidenceDropTarget,
  type IInteractable,
} from './interactables/Interactable.js';
import type { InteractableFactoryRegistry, InteractableRegistry } from './interactables/InteractableRegistry.js';
import type { EvidenceAction, EvidenceRuleContext, IEvidenceRule } from './rules/EvidenceRules.js';
import type {
  EvidenceDefinition,
  EvidenceEvents,
  EvidenceInstance,
  EvidenceMapConfig,
  IWorldQuery,
  PlayerId,
} from './types.js';

export interface EvidenceSystemDeps {
  catalog: IEvidenceCatalog;
  interactables: InteractableRegistry;
  factories: InteractableFactoryRegistry;
  inventories: IInventoryStore;
  roles: IRoleQuery;
  world: IWorldQuery;
  rules: IEvidenceRule[];
  events: IEventSink<EvidenceEvents>;
  /** Permisos especiales (rol / llave). Debe ser la misma política que usa AccessRule. */
  access?: IEvidenceAccessPolicy;
  newId?: () => string;
}

/**
 * Lógica autoritativa de pruebas: dónde está cada una, quién puede verla,
 * quién puede cogerla/soltarla/destruirla/mostrarla.
 *
 * - No sabe de red: publica eventos de dominio en un IEventSink.
 * - No sabe de roles concretos: pregunta a IRoleQuery por stats y visibilidad.
 * - No sabe de reglas concretas: ejecuta una cadena de IEvidenceRule.
 */
export class EvidenceSystem {
  private readonly instances = new Map<string, EvidenceInstance>();
  /** Pruebas expuestas públicamente: todos las ven completas desde entonces. */
  private readonly revealed = new Set<string>();
  private seq = 0;
  private readonly access: IEvidenceAccessPolicy;

  constructor(private readonly deps: EvidenceSystemDeps) {
    this.access = deps.access ?? new RequirementAccessPolicy();
  }

  // ───── Preparación ─────

  /** Crea los objetos del mapa y coloca una instancia de cada prueba referenciada. */
  loadMap(map: EvidenceMapConfig): void {
    for (const cfg of map.interactables) {
      const interactable = this.deps.factories.create(cfg);
      this.deps.interactables.add(interactable);

      const refs = [
        ...(typeof cfg.evidenceId === 'string' ? [cfg.evidenceId] : []),
        ...(Array.isArray(cfg.evidenceIds) ? (cfg.evidenceIds as string[]) : []),
      ];
      for (const defId of refs) this.spawn(defId, interactable);
    }
  }

  spawn(definitionId: string, target: IInteractable): EvidenceInstance {
    if (!this.deps.catalog.get(definitionId)) throw new Error(`Prueba no existe en el catálogo: ${definitionId}`);
    if (!isDropTarget(target) || !target.canAccept('')) throw new Error(`No se puede colocar prueba en ${target.id}`);
    const instance: EvidenceInstance = {
      instanceId: this.deps.newId?.() ?? `ev_${++this.seq}`,
      definitionId,
      location: { kind: 'world', interactableId: target.id },
      history: [],
    };
    this.instances.set(instance.instanceId, instance);
    target.put(instance.instanceId);
    return instance;
  }

  // ───── Acciones de jugador (llamadas por la capa de red tras recibir una intención) ─────

  /**
   * Recoger de un objeto. Con `instanceId` se pide una pieza concreta (la que el
   * jugador está mirando en el visor); sin él, la primera que percibe.
   */
  interact(playerId: PlayerId, interactableId: string, instanceId?: string): Result<EvidenceInstance> {
    const target = this.deps.interactables.get(interactableId);
    if (!target) return fail('unknown_interactable');
    if (!isEvidenceSource(target)) return fail('not_a_source');

    const canPerceive = (id: string) => this.visibilityOf(playerId, id) !== 'hidden';
    const candidateId = instanceId
      ? (target.contents().includes(instanceId) && canPerceive(instanceId) ? instanceId : null)
      : target.pickCandidate({ playerId, canPerceive });
    if (!candidateId) return fail('nothing_found');

    const instance = this.instances.get(candidateId)!;
    const denied = this.runRules('collect', playerId, instance, target);
    if (denied) return fail(denied);

    if (!target.take(candidateId)) return fail('race_lost');
    this.deps.inventories.of(playerId).add(candidateId);
    this.moveTo(instance, { kind: 'inventory', playerId }, playerId, 'collected');
    this.deps.events.emit('evidence.collected', { playerId, interactableId, instanceId: candidateId });
    return ok(instance);
  }

  /** Suelta una prueba en el objeto que acepte más cercano (o en el indicado). */
  drop(playerId: PlayerId, instanceId: string, targetId?: string): Result<IEvidenceDropTarget> {
    const instance = this.ownedBy(playerId, instanceId);
    if (!instance) return fail('not_in_inventory');

    const pos = this.deps.world.positionOf(playerId);
    if (!pos) return fail('unknown_player');
    const found = targetId
      ? this.deps.interactables.get(targetId)
      : this.deps.interactables.nearest(pos, (i) => isDropTarget(i) && i.canAccept(instanceId));
    if (!found || !isDropTarget(found) || !found.canAccept(instanceId)) return fail('no_drop_target');

    const denied = this.runRules('drop', playerId, instance, found);
    if (denied) return fail(denied);

    this.deps.inventories.of(playerId).remove(instanceId);
    found.put(instanceId);
    this.moveTo(instance, { kind: 'world', interactableId: found.id }, playerId, 'dropped');
    this.deps.events.emit('evidence.dropped', { playerId, interactableId: found.id, instanceId });
    return ok(found);
  }

  /** Destruir al instante una prueba del inventario (modificador can_destroy_evidence). */
  destroy(playerId: PlayerId, instanceId: string): Result<EvidenceInstance> {
    const instance = this.ownedBy(playerId, instanceId);
    if (!instance) return fail('not_in_inventory');
    const denied = this.runRules('destroy', playerId, instance);
    if (denied) return fail(denied);
    this.remove(playerId, instance);
    return ok(instance);
  }

  // ───── Acciones canalizadas (las ejecuta ChannelSystem al completarse) ─────

  /**
   * ¿Puede el jugador actuar sobre esta pieza ahora? La lleva encima, o está en el
   * mapa, la percibe y está al alcance de su objeto.
   */
  reachable(playerId: PlayerId, instanceId: string): boolean {
    const inst = this.instances.get(instanceId);
    if (!inst) return false;
    if (inst.location.kind === 'inventory') return inst.location.playerId === playerId;
    if (inst.location.kind !== 'world') return false;
    if (this.visibilityOf(playerId, instanceId) === 'hidden') return false;
    const target = this.deps.interactables.get(inst.location.interactableId);
    const pos = this.deps.world.positionOf(playerId);
    if (!target || !pos) return false;
    const d = Math.hypot(target.position.x - pos.x, target.position.y - pos.y);
    return d <= this.deps.roles.getStats(playerId).interactRange + target.radius;
  }

  /** Borrar una prueba donde esté (en el mapa o en un inventario). Sin comprobar permisos: ya lo hizo quien llama. */
  forceDestroy(playerId: PlayerId, instanceId: string): Result<EvidenceInstance> {
    const inst = this.instances.get(instanceId);
    if (!inst || inst.location.kind === 'destroyed') return fail('nothing_found');
    this.remove(playerId, inst);
    return ok(inst);
  }

  /**
   * Hacer una copia (dump forense, foto) que va al inventario del jugador. La copia
   * se puede llevar aunque el original sea fijo, y cuenta como la misma pista.
   */
  backup(playerId: PlayerId, instanceId: string): Result<EvidenceInstance> {
    const original = this.instances.get(instanceId);
    const def = original && this.deps.catalog.get(original.definitionId);
    if (!original || !def || original.location.kind === 'destroyed') return fail('nothing_found');
    if (this.carriedWeight(playerId) + def.weight > this.deps.roles.getStats(playerId).inventoryCapacity) return fail('inventory_full');
    const copy: EvidenceInstance = {
      instanceId: this.deps.newId?.() ?? `ev_${++this.seq}`,
      definitionId: def.id,
      location: { kind: 'inventory', playerId },
      history: [{ playerId, action: 'copied', at: this.deps.world.now() }],
      copyOf: instanceId,
    };
    this.instances.set(copy.instanceId, copy);
    this.deps.inventories.of(playerId).add(copy.instanceId);
    this.deps.events.emit('evidence.copied', { playerId, instanceId: copy.instanceId, originalId: instanceId });
    return ok(copy);
  }

  /** Mostrar una prueba a toda la sala (para la fase de discusión). */
  present(playerId: PlayerId, instanceId: string): Result<EvidenceInstance> {
    const instance = this.ownedBy(playerId, instanceId);
    if (!instance) return fail('not_in_inventory');
    const denied = this.runRules('present', playerId, instance);
    if (denied) return fail(denied);

    instance.history.push({ playerId, action: 'presented', at: this.deps.world.now() });
    this.revealed.add(instanceId);
    this.deps.events.emit('evidence.presented', { playerId, instanceId });
    return ok(instance);
  }

  /** Al desconectarse o morir: las pruebas caen donde esté el jugador. */
  spillInventory(playerId: PlayerId): void {
    for (const id of [...this.deps.inventories.of(playerId).items()]) {
      const pos = this.deps.world.positionOf(playerId);
      const target = pos && this.deps.interactables.nearest(pos, (i) => isDropTarget(i) && i.canAccept(id));
      if (!target || !isDropTarget(target)) continue;
      this.deps.inventories.of(playerId).remove(id);
      target.put(id);
      this.moveTo(this.instances.get(id)!, { kind: 'world', interactableId: target.id }, playerId, 'dropped');
      this.deps.events.emit('evidence.dropped', { playerId, interactableId: target.id, instanceId: id });
    }
  }

  // ───── Consultas ─────

  getInstance(instanceId: string) { return this.instances.get(instanceId); }

  /** Objetos del mapa (solo lectura, para proyectar estado hacia los clientes). */
  listInteractables(): readonly IInteractable[] { return this.deps.interactables.all(); }

  definitionOf(instanceId: string): EvidenceDefinition | undefined {
    const inst = this.instances.get(instanceId);
    return inst && this.deps.catalog.get(inst.definitionId);
  }

  isRevealed(instanceId: string): boolean { return this.revealed.has(instanceId); }

  revealedDefinitionIds(): Set<string> {
    return new Set([...this.revealed].map((id) => this.instances.get(id)!.definitionId));
  }

  revealedTags(): string[][] {
    return [...this.revealed].map((id) => this.definitionOf(id)?.tags ?? []);
  }

  destroyedDefinitionIds(): Set<string> {
    return new Set([...this.instances.values()].filter((i) => i.location.kind === 'destroyed').map((i) => i.definitionId));
  }

  holdersOf(definitionId: string): PlayerId[] {
    return [...this.instances.values()]
      .filter((i) => i.definitionId === definitionId && i.location.kind === 'inventory')
      .map((i) => (i.location as { playerId: PlayerId }).playerId);
  }

  catalogName(definitionId: string): string {
    return this.deps.catalog.get(definitionId)?.name ?? definitionId;
  }

  inventoryOf(playerId: PlayerId): EvidenceInstance[] {
    return this.deps.inventories.of(playerId).items().map((id) => this.instances.get(id)!);
  }

  inventoryTags(playerId: PlayerId): string[][] {
    return this.inventoryOf(playerId).map((i) => this.deps.catalog.get(i.definitionId)?.tags ?? []);
  }

  /**
   * Qué percibe un jugador de una prueba. Las que lleva en el inventario siempre las
   * ve completas. Si no cumple el permiso de 'view', como mucho la ve en parcial.
   */
  visibilityOf(viewerId: PlayerId, instanceId: string): VisibilityLevel {
    const inst = this.instances.get(instanceId);
    if (!inst || inst.location.kind === 'destroyed') return 'hidden';
    if (inst.location.kind === 'inventory' && inst.location.playerId === viewerId) return 'full';
    if (this.revealed.has(instanceId)) return 'full';
    const def = this.deps.catalog.get(inst.definitionId);
    if (!def) return 'hidden';
    const level = this.deps.roles.visibilityFor(viewerId, def.tags);
    if (level === 'full' && !this.access.check(def, 'view', this.subjectOf(viewerId)).ok) return 'partial';
    return level;
  }

  /** Permiso especial de un jugador sobre una prueba (para avisarle en la UI de qué le falta). */
  accessOf(viewerId: PlayerId, instanceId: string, action: AccessAction): AccessCheck {
    const def = this.definitionOf(instanceId);
    if (!def) return { ok: false };
    return this.access.check(def, action, this.subjectOf(viewerId));
  }

  // ───── Internos ─────

  private ownedBy(playerId: PlayerId, instanceId: string): EvidenceInstance | undefined {
    if (!this.deps.inventories.of(playerId).has(instanceId)) return undefined;
    return this.instances.get(instanceId);
  }

  private subjectOf(playerId: PlayerId): AccessSubject {
    return {
      roleId: this.deps.roles.getRoleOf(playerId)?.id,
      carried: new Set(this.inventoryOf(playerId).map((i) => i.definitionId)),
    };
  }

  private remove(playerId: PlayerId, inst: EvidenceInstance): void {
    if (inst.location.kind === 'inventory') this.deps.inventories.of(inst.location.playerId).remove(inst.instanceId);
    if (inst.location.kind === 'world') {
      const source = this.deps.interactables.get(inst.location.interactableId);
      if (source && isEvidenceSource(source)) source.take(inst.instanceId);
    }
    this.moveTo(inst, { kind: 'destroyed', by: playerId }, playerId, 'destroyed');
    this.deps.events.emit('evidence.destroyed', { playerId, instanceId: inst.instanceId });
  }

  private carriedWeight(playerId: PlayerId): number {
    return this.inventoryOf(playerId).reduce((acc, i) => acc + (this.deps.catalog.get(i.definitionId)?.weight ?? 0), 0);
  }

  private runRules(
    action: EvidenceAction,
    playerId: PlayerId,
    instance: EvidenceInstance,
    interactable?: IInteractable,
  ): string | null {
    const ctx: EvidenceRuleContext = {
      action,
      playerId,
      playerPosition: this.deps.world.positionOf(playerId) ?? { x: Infinity, y: Infinity },
      alive: this.deps.world.isAlive(playerId),
      phase: this.deps.world.currentPhase(),
      stats: this.deps.roles.getStats(playerId),
      carriedWeight: this.carriedWeight(playerId),
      instance,
      definition: this.deps.catalog.get(instance.definitionId)!,
      interactable,
      subject: this.subjectOf(playerId),
    };
    for (const rule of this.deps.rules) {
      if (!rule.appliesTo.includes(action)) continue;
      const reason = rule.check(ctx);
      if (reason) return reason;
    }
    return null;
  }

  private moveTo(
    instance: EvidenceInstance,
    location: EvidenceInstance['location'],
    playerId: PlayerId,
    action: EvidenceInstance['history'][number]['action'],
  ) {
    instance.location = location;
    instance.history.push({ playerId, action, at: this.deps.world.now() });
  }
}
