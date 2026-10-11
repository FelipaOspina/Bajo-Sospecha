import type { PatchOp } from '../../../shared/protocol/protocol.js';

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

/**
 * Diff estructural mínimo entre dos snapshots ya proyectados.
 * - Objetos: recursivo por clave.
 * - Arrays: si cambia la longitud se reemplaza entero; si no, recursivo por índice.
 * Suficiente para salas de ≤ 10 jugadores; sustituible por un encoder binario
 * o por esquemas tipo Colyseus sin tocar Room (depende de IDeltaEncoder).
 */
export interface IDeltaEncoder {
  diff(prev: unknown, next: unknown): PatchOp[];
}

export class JsonDeltaEncoder implements IDeltaEncoder {
  diff(prev: unknown, next: unknown): PatchOp[] {
    const ops: PatchOp[] = [];
    this.walk(prev as Json, next as Json, [], ops);
    return ops;
  }

  private walk(a: Json | undefined, b: Json | undefined, path: (string | number)[], ops: PatchOp[]) {
    if (a === b) return;
    if (b === undefined) { ops.push({ op: 'remove', path }); return; }
    const bothArrays = Array.isArray(a) && Array.isArray(b);
    const bothObjects = !bothArrays && isObj(a) && isObj(b);

    if (bothArrays) {
      if (a.length !== b.length) { ops.push({ op: 'set', path, value: b }); return; }
      b.forEach((v, i) => this.walk(a[i], v, [...path, i], ops));
      return;
    }
    if (bothObjects) {
      for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) this.walk(a[k], b[k], [...path, k], ops);
      return;
    }
    ops.push({ op: 'set', path, value: b });
  }
}

const isObj = (v: unknown): v is { [k: string]: Json } => typeof v === 'object' && v !== null && !Array.isArray(v);
