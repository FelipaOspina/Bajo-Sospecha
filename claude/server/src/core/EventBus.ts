/**
 * Bus de eventos tipado. Los sistemas de dominio publican hechos; la capa de red
 * (y cualquier otro interesado: logs, métricas, objetivos) se suscribe.
 * Así EvidenceSystem no conoce WebSockets (Inversión de Dependencias).
 */
export interface IEventSink<TEvents> {
  emit<K extends keyof TEvents>(type: K, payload: TEvents[K]): void;
}

type Handler<T> = (payload: T) => void;

export class EventBus<TEvents> implements IEventSink<TEvents> {
  private handlers = new Map<keyof TEvents, Set<Handler<any>>>();

  on<K extends keyof TEvents>(type: K, handler: Handler<TEvents[K]>): () => void {
    let set = this.handlers.get(type);
    if (!set) this.handlers.set(type, (set = new Set()));
    set.add(handler);
    return () => set!.delete(handler);
  }

  emit<K extends keyof TEvents>(type: K, payload: TEvents[K]): void {
    this.handlers.get(type)?.forEach((h) => h(payload));
  }
}
