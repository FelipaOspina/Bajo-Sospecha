import type { PlayerId, Vec2 } from '../types.js';

/** Cualquier objeto del mapa con el que se puede interactuar. */
export interface IInteractable {
  readonly id: string;
  readonly type: string;
  readonly position: Vec2;
  readonly radius: number;
  /** Ids de instancias de prueba que contiene ahora mismo. */
  contents(): readonly string[];
}

export interface PickContext {
  playerId: PlayerId;
  /** El sistema le dice al objeto qué puede percibir el jugador. */
  canPerceive(instanceId: string): boolean;
}

/** Objeto del que se pueden sacar pruebas. */
export interface IEvidenceSource extends IInteractable {
  pickCandidate(ctx: PickContext): string | null;
  take(instanceId: string): boolean;
}

/** Objeto en el que se pueden dejar pruebas. */
export interface IEvidenceDropTarget extends IInteractable {
  canAccept(instanceId: string): boolean;
  put(instanceId: string): void;
}

export const isEvidenceSource = (i: IInteractable): i is IEvidenceSource =>
  typeof (i as IEvidenceSource).pickCandidate === 'function';

export const isDropTarget = (i: IInteractable): i is IEvidenceDropTarget =>
  typeof (i as IEvidenceDropTarget).canAccept === 'function';
