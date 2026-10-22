import { readFileSync } from 'node:fs';
import type { Vec2 } from '../../../../shared/protocol/protocol.js';

/** Tramo de muro [ax, ay, bx, by] (px del mapa). */
export type WallSegment = [number, number, number, number];

/** shared/config/maps/office_walls.json (lo exporta el cliente con tools/ExportWalls.tscn). */
export interface WallsFile {
  version: number;
  bounds?: [number, number, number, number];
  walls: WallSegment[];
}

/**
 * Línea de vista del servidor (para los testigos). Todos los tramos tapan la vista,
 * igual que LineOfSight.gd en el cliente. Sin muros, solo cuenta la distancia.
 */
export class LineOfSight {
  constructor(readonly walls: readonly WallSegment[] = []) {}

  /** ¿Ve `a` a `b` a como mucho `maxDistance` px sin ningún muro en medio? */
  canSee(a: Vec2, b: Vec2, maxDistance: number): boolean {
    if (Math.hypot(a.x - b.x, a.y - b.y) > maxDistance) return false;
    return !this.walls.some((w) => segmentsCross(a, b, { x: w[0], y: w[1] }, { x: w[2], y: w[3] }));
  }

  /** Lee el archivo de muros; si falta o está mal, devuelve null (se usa solo la distancia). */
  static load(path: string, warn: (msg: string) => void = () => {}): LineOfSight | null {
    try {
      const raw = JSON.parse(readFileSync(path, 'utf8')) as WallsFile;
      const walls = (raw.walls ?? []).filter((w) => Array.isArray(w) && w.length === 4 && w.every(Number.isFinite));
      return new LineOfSight(walls as WallSegment[]);
    } catch (e) {
      warn(`sin muros (${(e as Error).message}): los testigos solo dependen de la distancia`);
      return null;
    }
  }
}

const cross = (o: Vec2, a: Vec2, b: Vec2) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

/** ¿Se cortan los segmentos pq y rs? (tocar un extremo también tapa). */
export function segmentsCross(p: Vec2, q: Vec2, r: Vec2, s: Vec2): boolean {
  const d1 = cross(r, s, p);
  const d2 = cross(r, s, q);
  const d3 = cross(p, q, r);
  const d4 = cross(p, q, s);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) return true;
  const on = (a: Vec2, b: Vec2, c: Vec2) =>
    Math.min(a.x, b.x) <= c.x && c.x <= Math.max(a.x, b.x) && Math.min(a.y, b.y) <= c.y && c.y <= Math.max(a.y, b.y);
  return (d1 === 0 && on(r, s, p)) || (d2 === 0 && on(r, s, q)) || (d3 === 0 && on(p, q, r)) || (d4 === 0 && on(p, q, s));
}
