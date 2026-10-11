/** Fuente de aleatoriedad inyectable para que las asignaciones sean testeables. */
export interface IRandom {
  /** Número en [0, 1). */
  next(): number;
}

export const mathRandom: IRandom = { next: () => Math.random() };

/** PRNG determinista (mulberry32) para tests y repeticiones. */
export class SeededRandom implements IRandom {
  constructor(private state: number) {}
  next(): number {
    let t = (this.state += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
}
